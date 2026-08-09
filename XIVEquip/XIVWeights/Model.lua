-- XIVWeights/Model.lua
-- Native valuation vocabulary and Scale shape (architecture proposal doc,
-- section 9 "Initial XIVWeights Feature Vocabulary" and section 39 module
-- boundaries). Everything else under XIVWeights/ builds on FEATURES/NewScale.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
local XIVWeights = XIVEquip.XIVWeights

-- The ordinary XIVWeights feature vocabulary (doc 9.1-9.5). Anything not in
-- this list is not a core weight dimension -- Providers map their own
-- source-specific keys onto this fixed set during conversion.
XIVWeights.FEATURES = {
  -- primary attributes (9.1)
  "strength", "agility", "intellect",
  -- defensive/base properties (9.2)
  "stamina", "armor", "bonusArmor",
  -- secondary ratings (9.3)
  "criticalStrike", "haste", "mastery", "versatility",
  -- tertiary/minor properties (9.4)
  "leech", "avoidance", "movementSpeed", "indestructible",
  -- weapon properties (9.5)
  "weaponDps", "weaponMinDamage", "weaponMaxDamage", "weaponSwingIntervalSeconds",
}

XIVWeights.FEATURE_SET = {}
for _, feature in ipairs(XIVWeights.FEATURES) do
  XIVWeights.FEATURE_SET[feature] = true
end

-- NewScale: build an XIVWeights.Scale record. `weights` should already be
-- normalized (see Normalizer.Normalize) before being handed to the Scorer.
-- Copies every field the caller supplies (not just the well-known ones) so
-- supplemental namespaces such as `setBonuses` (doc section 14) survive
-- construction -- only source/weights/meta get a default when omitted.
function XIVWeights.NewScale(fields)
  fields = fields or {}
  local scale = {}
  for key, value in pairs(fields) do
    scale[key] = value
  end
  scale.source = scale.source or { kind = "manual" }
  scale.weights = scale.weights or {}
  scale.meta = scale.meta or {}
  return scale
end
