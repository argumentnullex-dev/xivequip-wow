-- Evaluation/CandidateNormalizer.lua
-- Doc section 6's Normalized Candidate Model: extract stable item facts
-- once from an already-resolved item link, rather than re-parsing the same
-- item repeatedly across planner-specific code.
--
-- Takes a link + caller-supplied source metadata, not a raw ItemLocation --
-- location -> link resolution (with all of Core.linkFromLocation's
-- fallbacks: bag scan, pending-data retry, GUID identity) is a Collector-
-- stage concern (doc section 4), owned by whatever eventually replaces
-- Core.chooseForSlot's bag-scan (Phase 3+). Duplicating that resolution
-- here before there's an actual caller risks it silently diverging from
-- the real thing.
--
-- Weapon damage/speed extraction includes a tooltip fallback so native Pawn
-- scales do not advertise supported weapon keys
-- that silently score as zero when GetItemStats omits damage fields.
local addonName, XIVEquip = ...
XIVEquip.Evaluation = XIVEquip.Evaluation or {}
local Evaluation = XIVEquip.Evaluation

local CandidateNormalizer = {}
Evaluation.CandidateNormalizer = CandidateNormalizer

-- Blizzard GetItemStats token -> XIVWeights stat feature name. A small,
-- independent map -- low-churn enough that keeping it local beats coupling
-- normalization to an integration module.
local STAT_TOKEN_MAP = {
  ITEM_MOD_STRENGTH = "strength", ITEM_MOD_STRENGTH_SHORT = "strength",
  ITEM_MOD_AGILITY = "agility", ITEM_MOD_AGILITY_SHORT = "agility",
  ITEM_MOD_INTELLECT = "intellect", ITEM_MOD_INTELLECT_SHORT = "intellect",
  ITEM_MOD_STAMINA = "stamina", ITEM_MOD_STAMINA_SHORT = "stamina",
  ITEM_MOD_ARMOR = "armor", ITEM_MOD_ARMOR_SHORT = "armor", RESISTANCE0_NAME = "armor",
  ITEM_MOD_BONUS_ARMOR_SHORT = "bonusArmor",
  ITEM_MOD_CRIT_RATING = "criticalStrike", ITEM_MOD_CRIT_RATING_SHORT = "criticalStrike",
  ITEM_MOD_HASTE_RATING = "haste", ITEM_MOD_HASTE_RATING_SHORT = "haste",
  ITEM_MOD_MASTERY_RATING = "mastery", ITEM_MOD_MASTERY_RATING_SHORT = "mastery",
  ITEM_MOD_VERSATILITY = "versatility", ITEM_MOD_VERSATILITY_SHORT = "versatility",
  ITEM_MOD_LIFESTEAL = "leech",
  ITEM_MOD_AVOIDANCE_RATING = "avoidance",
  ITEM_MOD_SPEED_RATING = "movementSpeed", ITEM_MOD_SPEED_RATING_SHORT = "movementSpeed",
}

-- Every stat-shaped XIVWeights feature (weapon features excluded -- those
-- live under candidate.weapon instead, matching doc section 6's shape).
-- Always emitted with an explicit 0 default, mirroring how the doc's own
-- illustrative candidate.stats example lists every field.
local STAT_FEATURES = {
  "strength", "agility", "intellect",
  "stamina", "armor", "bonusArmor",
  "criticalStrike", "haste", "mastery", "versatility",
  "leech", "avoidance", "movementSpeed", "indestructible",
}

local WEAPON_TOKEN_MAP = {
  ITEM_MIN_DAMAGE = "minimumDamage",
  ITEM_MAX_DAMAGE = "maximumDamage",
  ITEM_MOD_DAMAGE_PER_SECOND = "dps", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
  ITEM_WEAPON_SPEED = "swingIntervalSeconds",
  Speed = "swingIntervalSeconds",
}

local WEAPON_EQUIPLOCS = {
  INVTYPE_WEAPON = true,
  INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_2HWEAPON = true,
  INVTYPE_RANGED = true,
  INVTYPE_RANGEDRIGHT = true,
  INVTYPE_THROWN = true,
}

local function parseItemID(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hitem:(%d+)") or link:match("item:(%d+)"))
end

local function getItemStatsCompat(link)
  local fn = _G.GetItemStats or (C_Item and C_Item.GetItemStats)
  if type(fn) ~= "function" then return {} end
  return fn(link) or {}
end

local function getWeaponDamageAndSpeed(link, perf)
  if not (link and C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function") then return nil end
  if perf then perf:Add("normalization.tooltip_reads", 1) end
  local tip = C_TooltipInfo.GetHyperlink(link)
  if not (tip and type(tip.lines) == "table") then return nil end

  local minD, maxD, speed
  local function grab(text)
    if type(text) ~= "string" then return end
    local a, b = text:match("(%d+)%s*%-%s*(%d+)%s+[Dd]amage")
    if a and b then
      minD = tonumber(a)
      maxD = tonumber(b)
    end
    local sp = text:match("[Ss]peed%s+([%d%.]+)")
    if sp then speed = tonumber(sp) end
  end

  for _, line in ipairs(tip.lines) do
    grab(line.leftText)
    grab(line.rightText)
  end
  return minD, maxD, speed
end

-- resolveUniqueness(itemID, link) -> key, limit
-- Faithfully reproduces Core.GetUniqueInfo's exact semantics
-- (Core/GearCore.lua:60-96), which the black-box scenario tests already
-- rely on being correct. This matters because C_Item.GetItemUniqueness's
-- first return is a *limitCategory number*, not an opaque key -- category
-- 0 specifically means "this exact item is unique with itself" (an
-- ordinary Unique-Equipped item), not "not unique." 0 is truthy in Lua, so
-- treating it as the key directly (the previous bug here) would make every
-- ordinary Unique-Equipped item collide with every other one. A nonzero
-- category is a *shared* category (e.g. a legendary-effect slot multiple
-- item IDs draw from) and must stay distinct from the item-specific case.
local function resolveUniqueness(itemID, link)
  local itemInfo = link or itemID
  if C_Item and type(C_Item.GetItemUniqueness) == "function" then
    local ok, category, limit = pcall(C_Item.GetItemUniqueness, itemInfo)
    if ok and category and limit then
      local categoryID = tonumber(category)
      local uniqueLimit = tonumber(limit) or 0
      if categoryID and categoryID ~= 0 and uniqueLimit > 0 then
        return "category:" .. tostring(category), uniqueLimit
      end
      if categoryID == 0 and uniqueLimit > 0 and itemID then
        return "item:" .. tostring(itemID), uniqueLimit
      end
    end
  end
  if C_Item and type(C_Item.GetItemUniquenessByID) == "function" then
    local ok, isUnique, categoryName, categoryCount, categoryID = pcall(C_Item.GetItemUniquenessByID, itemInfo)
    if ok then
      local uniqueLimit = tonumber(categoryCount) or 0
      local numericCategoryID = tonumber(categoryID)
      if numericCategoryID and numericCategoryID ~= 0 and uniqueLimit > 0 then
        return "category:" .. tostring(categoryID), uniqueLimit
      end
      if isUnique then
        return "item:" .. tostring(itemID or itemInfo), uniqueLimit > 0 and uniqueLimit or 1
      end
      if numericCategoryID == 0 and uniqueLimit > 0 and itemID then
        return "item:" .. tostring(itemID), uniqueLimit
      end
      if categoryName and uniqueLimit > 0 then
        return "category:" .. tostring(categoryName), uniqueLimit
      end
    end
  end
  return nil, nil
end

-- FromLink(link, source) -> candidate|nil, reason
-- source: caller-supplied identity/location metadata, e.g.
--   { kind = "bag", bag = 0, slot = 4, guid = "...", physicalID = "bag:0:4" }
-- Passed through verbatim on the returned candidate.
function CandidateNormalizer.FromLink(link, source, opts)
  source = source or {}
  opts = opts or {}
  local itemID = parseItemID(link) or source.itemID
  local itemInfo = itemID or link
  if itemInfo == nil then return nil, "invalid-item-info" end

  local okInstant, resolvedItemID, _, _, equipLoc, _, itemClassID, itemSubclassID = pcall(GetItemInfoInstant, itemInfo)
  if not okInstant or not equipLoc then return nil, "pending-item-data" end
  itemID = itemID or resolvedItemID
  local _, _, _, baseItemLevel, requiredLevel, _, _, _, _, _, _, _, _, _, _, setID = GetItemInfo(link)

  -- GetItemInfo's 4th return is the item's *base* level. GetDetailedItemLevelInfo
  -- returns the *effective* level shown on the tooltip (accounting for item
  -- upgrades/track), which is what a candidate's value should reflect --
  -- so it's tried first, not just as a fallback for when the base level is
  -- somehow unavailable (a valid cached item almost always has a numeric
  -- base level, which would otherwise make this fallback dead code).
  local detailedLevelFn = (C_Item and C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
  local itemLevel
  if type(detailedLevelFn) == "function" then
    local effectiveLevel = detailedLevelFn(link)
    if type(effectiveLevel) == "number" and effectiveLevel > 0 then
      itemLevel = effectiveLevel
    end
  end
  if not itemLevel then
    itemLevel = baseItemLevel
  end

  local uniqueKey, uniqueLimit = resolveUniqueness(itemID, link)

  local rawStats = getItemStatsCompat(link)

  local stats = {}
  for _, feature in ipairs(STAT_FEATURES) do stats[feature] = 0 end
  for token, feature in pairs(STAT_TOKEN_MAP) do
    local amount = rawStats[token]
    if type(amount) == "number" then
      stats[feature] = stats[feature] + amount
    end
  end

  local weapon = { dps = 0, minimumDamage = 0, maximumDamage = 0, swingIntervalSeconds = 0 }
  for token, field in pairs(WEAPON_TOKEN_MAP) do
    local amount = rawStats[token]
    if type(amount) == "number" then
      weapon[field] = amount
    end
  end
  if WEAPON_EQUIPLOCS[equipLoc]
      and (weapon.minimumDamage == 0 or weapon.maximumDamage == 0 or weapon.swingIntervalSeconds == 0) then
    local tmin, tmax, tspeed = getWeaponDamageAndSpeed(link, opts.perf)
    if type(tmin) == "number" and weapon.minimumDamage == 0 then weapon.minimumDamage = tmin end
    if type(tmax) == "number" and weapon.maximumDamage == 0 then weapon.maximumDamage = tmax end
    if type(tspeed) == "number" and weapon.swingIntervalSeconds == 0 then weapon.swingIntervalSeconds = tspeed end
  end
  if weapon.dps == 0 and weapon.minimumDamage > 0 and weapon.maximumDamage > 0 and weapon.swingIntervalSeconds > 0 then
    weapon.dps = ((weapon.minimumDamage + weapon.maximumDamage) / 2) / weapon.swingIntervalSeconds
  end

  return {
    itemID = itemID,
    link = link,
    guid = source.guid,
    physicalID = source.physicalID,
    source = source,
    equip = {
      equipLoc = equipLoc,
      itemClassID = itemClassID,
      itemSubclassID = itemSubclassID,
      requiredLevel = requiredLevel,
    },
    itemLevel = itemLevel,
    setID = tonumber(setID),
    uniqueness = { key = uniqueKey, limit = uniqueLimit },
    stats = stats,
    weapon = weapon,
  }
end
