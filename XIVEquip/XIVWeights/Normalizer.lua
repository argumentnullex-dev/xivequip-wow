-- XIVWeights/Normalizer.lua
-- Implements the doc's normalization invariant (section 8.1) and missing-
-- weight semantics (section 8.2). Input is already mapped into XIVWeights
-- feature names -- source-key mapping is a Provider's job, not this file's.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
local XIVWeights = XIVEquip.XIVWeights

local Normalizer = {}
XIVWeights.Normalizer = Normalizer

-- Normalize(rawWeights) -> weights
-- rawWeights: map of XIVWeights feature name -> raw source weight.
--
-- normalizedWeight = sourceWeight / maximumPositiveSourceWeight (8.1), so the
-- single strongest modeled feature normalizes to 1.0. A feature absent from
-- rawWeights normalizes to 0 (8.2) -- missing means ignored, not "average".
--
-- The native-scale invariant (8.1) is a 0..1 range: there is no "negative
-- XIVWeights value" concept in Phase 1. A nonpositive ordinary source weight
-- (an explicit penalty, or simply <= 0) normalizes to 0 rather than to a
-- negative fraction -- introducing signed valuation would be a deliberate
-- architecture change, not an incidental side effect of normalization.
-- Pawn's huge negative weapon-usability sentinels are a separate concept
-- entirely (a policy/capability signal, dropped during conversion by the
-- Pawn Provider -- see Providers/Pawn.lua) and never reach this function.
--
-- If there is no positive source weight at all (empty scale, or a scale
-- that only penalizes features), every feature normalizes to 0 rather than
-- dividing by zero -- there is no anchor to normalize against.
function Normalizer.Normalize(rawWeights)
  rawWeights = rawWeights or {}

  local maxPositive = 0
  for _, feature in ipairs(XIVWeights.FEATURES) do
    local w = rawWeights[feature]
    if type(w) == "number" and w > maxPositive then
      maxPositive = w
    end
  end

  local normalized = {}
  for _, feature in ipairs(XIVWeights.FEATURES) do
    local w = rawWeights[feature]
    if type(w) == "number" and w > 0 and maxPositive > 0 then
      normalized[feature] = w / maxPositive
    else
      normalized[feature] = 0
    end
  end
  return normalized
end
