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

local function resolvePawnWeights()
  local Pawn = XIVEquip.Pawn
  local XIVWeights = XIVEquip.XIVWeights
  if not (Pawn and type(Pawn.GetBestScaleValuesForPlayer) == "function" and XIVWeights and XIVWeights.Providers) then
    return nil
  end

  local rawValues, entry = Pawn.GetBestScaleValuesForPlayer()
  if type(rawValues) ~= "table" then return nil end

  local adapter = {
    ListScales = function()
      if type(Pawn.GetActiveScales) == "function" then return Pawn.GetActiveScales() end
      return {}
    end,
    ResolveValues = function()
      return rawValues, entry
    end,
  }

  local provider = XIVWeights.Providers.Pawn.New(adapter)
  local providerScale = provider:Resolve(nil, nil)
  return XIVWeights.Resolver.Resolve(providerScale, nil)
end

function Runtime.Live()
  local runtime = {}
  local cmp, resolution
  if XIVEquip.Comparers and type(XIVEquip.Comparers.StartPass) == "function" then
    cmp, resolution = XIVEquip.Comparers:StartPass()
  end
  local resolvedKey = resolution and resolution.resolved_key

  runtime.UnitClass = function(unit) return call(_G.UnitClass, unit) end
  runtime.GetSpecialization = function() return call(_G.GetSpecialization) end
  runtime.GetSpecializationInfo = function(index) return call(_G.GetSpecializationInfo, index) end
  runtime.UnitLevel = function(unit) return call(_G.UnitLevel, unit) end
  runtime.IsDualWielding = function() return call(_G.IsDualWielding) end

  runtime.ResolveWeights = function()
    if resolvedKey == "pawn" then
      local scale = resolvePawnWeights()
      if scale then return scale end
    end
    return XIVEquip.XIVWeights.NewScale({ id = "fallback:ilvl", source = { kind = "ilvl" }, weights = {} })
  end

  runtime.ScoreCandidate = function(candidate, context, slot)
    if context and context.weights and context.weights.source and context.weights.source.kind == "pawn" then
      return XIVEquip.Evaluation.CandidateEvaluator.Score(candidate, context)
    end
    return tonumber(candidate and candidate.itemLevel) or 0
  end

  runtime.ScoreSource = function(context)
    if context and context.weights and context.weights.source and context.weights.source.kind == "pawn" then
      return "XIVWeights/Pawn"
    end
    if resolution and resolution.fallback_used then
      return "item-level fallback"
    end
    if resolvedKey == "ilvl" then return "Item Level" end
    return "item-level fallback"
  end

  runtime.Comparer = function() return cmp, resolution end
  runtime.Close = function()
    if XIVEquip.Comparers and type(XIVEquip.Comparers.EndPass) == "function" then
      XIVEquip.Comparers:EndPass()
    end
  end

  return runtime
end
