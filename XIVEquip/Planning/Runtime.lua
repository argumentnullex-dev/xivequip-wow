-- Planning/Runtime.lua
-- Live runtime adapter for the shadow coordinator. It keeps game/Pawn API
-- touchpoints above the evaluation pipeline so downstream modules consume
-- EvaluationContext, candidates, and injected scoring only.
local addonName, XIVEquip = ...
XIVEquip.Planning = XIVEquip.Planning or {}
local Planning = XIVEquip.Planning

local Runtime = {}
Planning.Runtime = Runtime
local sharedPawnProvider

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
  return nil
end

function Runtime.Live()
  local runtime = {}
  local closed = false

  runtime.UnitClass = function(unit) return call(_G.UnitClass, unit) end
  runtime.UnitName = function(unit) return call(_G.UnitName, unit) end
  runtime.GetRealmName = function() return call(_G.GetRealmName) end
  runtime.IsAddOnLoaded = function(name)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
      return call(C_AddOns.IsAddOnLoaded, name) == true
    end
    if type(_G.IsAddOnLoaded) == "function" then
      return call(_G.IsAddOnLoaded, name) == true
    end
    return name == "Pawn" and XIVEquip.Pawn ~= nil
  end
  runtime.GetSpecialization = function() return call(_G.GetSpecialization) end
  runtime.GetSpecializationInfo = function(index) return call(_G.GetSpecializationInfo, index) end
  runtime.UnitLevel = function(unit) return call(_G.UnitLevel, unit) end
  runtime.IsDualWielding = function() return call(_G.IsDualWielding) end

  runtime.PawnProvider = function()
    if sharedPawnProvider then return sharedPawnProvider end
    local Pawn = XIVEquip.Pawn
    local XIVWeights = XIVEquip.XIVWeights
    if not (Pawn and XIVWeights and XIVWeights.Providers and XIVWeights.Providers.Pawn) then return nil end
    if not runtime.IsAddOnLoaded("Pawn") then return nil end
    local adapter = {
      ListScales = function()
        if type(Pawn.GetActiveScales) == "function" then return Pawn.GetActiveScales() end
        return {}
      end,
      ResolveValues = function(selection)
        if selection and type(Pawn.GetScaleValues) == "function" then
          local values, entry = Pawn.GetScaleValues(selection)
          if type(values) == "table" then return values, entry end
        end
        if not selection and type(Pawn.GetBestScaleValuesForPlayer) == "function" then
          return Pawn.GetBestScaleValuesForPlayer()
        end
        if type(Pawn.GetActiveScales) == "function" then
          for _, entry in ipairs(Pawn.GetActiveScales() or {}) do
            if entry and (entry.key == selection or entry.name == selection) then
              return entry.values, entry
            end
          end
        end
        return nil, nil
      end,
    }
    sharedPawnProvider = XIVWeights.Providers.Pawn.New(adapter)
    return sharedPawnProvider
  end

  runtime.ResolveWeights = function()
    local specIndex = runtime.GetSpecialization()
    local specID = specIndex and runtime.GetSpecializationInfo(specIndex)
    if specID and XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config then
      return XIVEquip.XIVWeights.Config.ResolveForSpec(specID, runtime)
    end
    return XIVEquip.XIVWeights.NewScale({ id = "fallback:empty", source = { kind = "empty" }, weights = {} })
  end

  runtime.ScoreCandidate = function(candidate, context, slot)
    if context and context.weights then return XIVEquip.Evaluation.CandidateEvaluator.Score(candidate, context) end
    return 0
  end

  runtime.ScoreSource = function(context)
    local scale = context and context.weights
    local Config = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config
    if Config and type(Config.ResolvedScaleSourceLabel) == "function" then
      return Config.ResolvedScaleSourceLabel(scale)
    end
    return "XIVWeights"
  end

  runtime.Comparer = function() return nil, nil end
  runtime.Close = function()
    if closed then return end
    closed = true
  end

  return runtime
end
