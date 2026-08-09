-- XIVWeights/Scorer.lua
-- Pure scale application: weighted sum over an already-measured feature
-- vector (doc section 10.2-10.4 for the weapon min/max-vs-dps preference).
-- No item-fetching or game-API calls here -- extracting a candidate's
-- feature vector from a real item is Phase 2's Normalized Candidate Model
-- (doc section 6); this module only knows how to apply a Scale to numbers.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
local XIVWeights = XIVEquip.XIVWeights

local Scorer = {}
XIVWeights.Scorer = Scorer

local WEAPON_MIN = "weaponMinDamage"
local WEAPON_MAX = "weaponMaxDamage"
local WEAPON_DPS = "weaponDps"

-- Score(scale, featureVector) -> number
-- featureVector: map of XIVWeights feature name -> measured item quantity.
function Scorer.Score(scale, featureVector)
  local weights = (scale and scale.weights) or {}
  featureVector = featureVector or {}

  local total = 0
  for _, feature in ipairs(XIVWeights.FEATURES) do
    if feature ~= WEAPON_MIN and feature ~= WEAPON_MAX and feature ~= WEAPON_DPS then
      local amount = featureVector[feature]
      local weight = weights[feature]
      if type(amount) == "number" and type(weight) == "number" then
        total = total + amount * weight
      end
    end
  end

  -- Weapon value: a scale that values min/max damage effectively values
  -- average damage per swing, which naturally favors slower weapons at
  -- equal DPS (doc 10.3) -- so when the scale has either min or max weight,
  -- that takes precedence over DPS entirely (doc 10.4's Pawn-parity
  -- semantics), rather than summing both and double-counting weapon value.
  --
  -- A normalized/provider-produced scale always has an explicit numeric 0
  -- for every absent feature (Normalizer.Normalize's 8.2 semantics), and 0
  -- is truthy in Lua -- so "has a min/max weight" must mean "has a *nonzero*
  -- min/max weight", or a DPS-only scale would always take this branch and
  -- silently score 0 for every weapon.
  local minW, maxW = weights[WEAPON_MIN], weights[WEAPON_MAX]
  local hasMinMaxWeight = (type(minW) == "number" and minW ~= 0) or (type(maxW) == "number" and maxW ~= 0)
  if hasMinMaxWeight then
    local minAmount, maxAmount = featureVector[WEAPON_MIN], featureVector[WEAPON_MAX]
    if type(minAmount) == "number" and type(minW) == "number" then
      total = total + minAmount * minW
    end
    if type(maxAmount) == "number" and type(maxW) == "number" then
      total = total + maxAmount * maxW
    end
  else
    local dpsW = weights[WEAPON_DPS]
    local dpsAmount = featureVector[WEAPON_DPS]
    if type(dpsAmount) == "number" and type(dpsW) == "number" then
      total = total + dpsAmount * dpsW
    end
  end

  return total
end
