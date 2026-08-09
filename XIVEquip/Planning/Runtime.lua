-- Planning/Runtime.lua
-- Live runtime adapter for the shadow coordinator. It keeps game/Pawn API
-- touchpoints above the evaluation pipeline so downstream modules consume
-- EvaluationContext, candidates, and injected scoring only.
local addonName, XIVEquip = ...
XIVEquip.Planning = XIVEquip.Planning or {}
local Planning = XIVEquip.Planning

local Runtime = {}
Planning.Runtime = Runtime

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
  runtime.GetSpecialization = function() return call(_G.GetSpecialization) end
  runtime.GetSpecializationInfo = function(index) return call(_G.GetSpecializationInfo, index) end
  runtime.UnitLevel = function(unit) return call(_G.UnitLevel, unit) end
  runtime.IsDualWielding = function() return call(_G.IsDualWielding) end

  runtime.PawnProvider = function()
    local Pawn = XIVEquip.Pawn
    local XIVWeights = XIVEquip.XIVWeights
    if not (Pawn and XIVWeights and XIVWeights.Providers and XIVWeights.Providers.Pawn) then return nil end
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
    return XIVWeights.Providers.Pawn.New(adapter)
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
    local source = context and context.weights and context.weights.source
    if source and source.kind == "pawn" then return "XIVWeights/Pawn" end
    if source and source.kind == "xivequip-default-copy" then return "XIVWeights/Default" end
    if source and source.kind == "manual" then return "XIVWeights/Manual" end
    return "XIVWeights"
  end

  runtime.Comparer = function() return nil, nil end
  runtime.Close = function()
    if closed then return end
    closed = true
  end

  return runtime
end
