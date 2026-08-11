-- XIVWeights/Providers/Pawn.lua
-- Converts Pawn scale weights into XIVWeights.Scale records (doc section
-- 11, 12, 31). This Provider only converts *scale weights* -- it does not
-- read or score items, so it has no dependency on planner item extraction.
--
-- Takes an injected adapter rather than reaching for the real Pawn
-- integration directly, so this is unit-testable without the real Pawn
-- addon loaded. In particular, Integrations/Pawn.lua's GetActiveScales() gives
-- *custom* (SV-backed) scale entries a real `values` table, but *provider*
-- (API-backed) scale entries have `values == nil` and need a separate
-- fetch from the integration adapter before they
-- have anything to convert. A ResolveValues that just returns `entry.values`
-- for an explicitly selected scale -- as sketched below -- only works for
-- custom scales; a real adapter must fall back to the provider-values fetch
-- when `entry.values` is nil:
--   { ListScales = function() return XIVEquip.Pawn.GetActiveScales() end,
--     ResolveValues = function(selection)
--       if not selection then return XIVEquip.Pawn.GetBestScaleValuesForPlayer() end
--       for _, entry in ipairs(XIVEquip.Pawn.GetActiveScales()) do
--         if entry.key == selection then
--           -- entry.values may be nil here for a provider-type scale --
--           -- a real adapter needs its own provider-values fetch, not
--           -- shown here.
--           return entry.values, entry
--         end
--       end
--     end }
--
-- Pawn's own "unusable" sentinel (a weight <= -999999 on weapon-type keys
-- like IsAxe1H/IsOffHand) is intentionally dropped during conversion, not
-- copied into XIVWeights.Scale -- per doc 31.2, "illegal" is a policy/
-- capability concern, not a native scoring field, and the policy layer that
-- would consume it doesn't exist until Phase 2.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
XIVEquip.XIVWeights.Providers = XIVEquip.XIVWeights.Providers or {}
local XIVWeights = XIVEquip.XIVWeights

local Pawn = {}
XIVWeights.Providers.Pawn = Pawn

-- Bumping this invalidates every cached conversion even when the source
-- scale's own weights are unchanged (doc 12.3). Exposed as a field (not a
-- local) so it's overridable in tests without editing this file.
Pawn.ConverterVersion = 1

-- Pawn stat key -> XIVWeights feature. Only the ordinary vocabulary from
-- doc 9/31.1 -- weapon-type usability booleans are not in this map, so they
-- never make it into a converted Scale.
local PAWN_KEY_MAP = {
  Strength = "strength",
  Agility = "agility",
  Intellect = "intellect",
  Stamina = "stamina",
  Armor = "armor",
  BonusArmor = "bonusArmor",
  CritRating = "criticalStrike",
  HasteRating = "haste",
  MasteryRating = "mastery",
  Versatility = "versatility",
  Leech = "leech",
  AvoidanceRating = "avoidance",
  MovementSpeed = "movementSpeed",
  Indestructible = "indestructible",
  Dps = "weaponDps",
  MinDamage = "weaponMinDamage",
  MaxDamage = "weaponMaxDamage",
  Speed = "weaponSwingIntervalSeconds",
}

-- Canonical hash over only the keys this converter actually consumes, with
-- deterministic ordering and number formatting (doc 12.2) -- UI color,
-- display order, and other non-scoring metadata never invalidate the cache.
local function canonicalHash(rawValues)
  local keys = {}
  for pawnKey in pairs(PAWN_KEY_MAP) do
    if rawValues[pawnKey] ~= nil then keys[#keys + 1] = pawnKey end
  end
  table.sort(keys)

  local parts = { "v" .. tostring(Pawn.ConverterVersion) }
  for _, pawnKey in ipairs(keys) do
    parts[#parts + 1] = pawnKey .. "=" .. string.format("%.6f", tonumber(rawValues[pawnKey]) or 0)
  end
  return table.concat(parts, "|")
end

local function convert(rawValues, entry)
  local mapped = {}
  for pawnKey, feature in pairs(PAWN_KEY_MAP) do
    local w = rawValues[pawnKey]
    if type(w) == "number" then
      mapped[feature] = w
    end
  end

  return XIVWeights.NewScale({
    id = "pawn:" .. tostring(entry and entry.key or "unknown"),
    name = entry and entry.name,
    source = { kind = "pawn", key = entry and entry.key },
    weights = XIVWeights.Normalizer.Normalize(mapped),
  })
end

local Methods = {}
local PawnProviderMT = { __index = Methods }

-- New(adapter) -> Pawn provider, per the Provider contract:
--   provider:ListScales(context)
--   provider:Resolve(selection, context)
function Pawn.New(adapter)
  assert(adapter, "Pawn provider requires an adapter")
  return setmetatable({ adapter = adapter, cache = {} }, PawnProviderMT)
end

function Methods:ListScales(context)
  return self.adapter.ListScales(context) or {}
end

-- Resolve(selection, context) -> Scale. `selection` is the Pawn scale key,
-- or nil to use the adapter's "best scale for this player" resolution.
function Methods:Resolve(selection, context)
  local rawValues, entry = self.adapter.ResolveValues(selection, context)
  assert(type(rawValues) == "table", "Pawn provider: no scale values available")

  local cacheKey = (entry and entry.key) or selection or "default"
  local hash = canonicalHash(rawValues)

  local cached = self.cache[cacheKey]
  if cached and cached.hash == hash then
    return cached.scale
  end

  local scale = convert(rawValues, entry)
  self.cache[cacheKey] = { hash = hash, scale = scale }
  return scale
end
