-- tests/harness/fake_world.lua
-- Centralizes the fake-WoW API surface duplicated across
-- tests/specs/weapons_spec.lua and tests/specs/paired_slots_spec.lua (doc
-- section 12). Builds a declarative scenario's item registry, equipped
-- slots, and bags, and installs the _G stubs the real planners need.
--
-- Scenario shape (see doc section 4):
--   scenario.character = { classFile, specID, specName, level, dualWielding }
--   scenario.items[key] = { itemID, equipLoc, classID, subclassID, itemLevel,
--                            scores = {[slotID]=n}, uniqueKey, uniqueLimit,
--                            requiredLevel, guid, loaded }
--   scenario.equipped[slotID] = "key"
--   scenario.bags[bagIndex] = { "key", ..., {item="key", guid="override"} }
--
-- Item keys are the human-readable authoring surface; everything the mock
-- exposes to production code (and everything ScenarioRunner reads back)
-- works in real itemIDs, matching the doc's normalized output format.

local FakeWorld = {}

local function parseItemID(info)
  if type(info) == "number" then return info end
  if type(info) == "string" then
    return tonumber(info:match("|Hitem:(%d+)") or info:match("item:(%d+)"))
  end
  if type(info) == "table" then return info.itemID or info.id end
  return nil
end

local function itemLink(id)
  return "|Hitem:" .. tostring(id) .. "::::::::::::|h[item-" .. tostring(id) .. "]|h"
end
FakeWorld.ItemLink = itemLink

-- Equip-loc tokens that occupy both hand slots (mirrors Weapons.lua's MH2H
-- table). Needed only for the physical-slot-constraint modeled inside
-- EquipCursorItem below.
local MH2H_EQUIPLOC = {
  INVTYPE_2HWEAPON = true,
  INVTYPE_RANGED = true,
  INVTYPE_RANGEDRIGHT = true,
  INVTYPE_THROWN = true,
}

function FakeWorld.Install(scenario)
  scenario = scenario or {}
  local character = scenario.character or {}

  local byKey, byID = {}, {}
  for key, def in pairs(scenario.items or {}) do
    local id = assert(def.itemID, "scenario item '" .. tostring(key) .. "' needs an itemID")
    local record = {
      key = key,
      itemID = id,
      link = def.link or itemLink(id),
      guid = def.guid or ("guid-" .. tostring(id)),
      equipLoc = def.equipLoc,
      classID = def.classID or 2,
      subclassID = def.subclassID or 0,
      ilvl = def.itemLevel or def.ilvl or 1,
      requiredLevel = def.requiredLevel or 1,
      scores = def.scores or {},
      uniqueKey = def.uniqueKey,
      uniqueLimit = def.uniqueLimit,
      uniqueFallback = def.uniqueFallback,
      equippable = def.equippable,
      loaded = def.loaded,
      stats = def.stats or {},
      setID = def.setID,
    }
    byKey[key] = record
    byID[id] = record
  end

  local function resolveEntry(entry)
    if entry == nil then return nil end
    if type(entry) == "table" then
      local base = byKey[entry.item]
      if not base then return nil end
      local copy = {}
      for k, v in pairs(base) do copy[k] = v end
      if entry.guid then copy.guid = entry.guid end
      return copy
    end
    return byKey[entry]
  end

  local equippedSlot = {}
  for slotID, entry in pairs(scenario.equipped or {}) do
    equippedSlot[slotID] = resolveEntry(entry)
  end

  local bagSlots = {}
  for bagIndex, entries in pairs(scenario.bags or {}) do
    local slots = {}
    for i, entry in ipairs(entries) do
      slots[i] = resolveEntry(entry)
    end
    bagSlots[bagIndex] = slots
  end

  local function itemForLoc(loc)
    if not loc then return nil end
    if loc.equipmentSlot then return equippedSlot[loc.equipmentSlot] end
    local bag = bagSlots[loc.bagID]
    return bag and bag[loc.slotIndex]
  end

  _G.NUM_BAG_SLOTS = 4
  _G.UnitClass = function() return character.className or "Player", character.classFile or "WARRIOR" end
  _G.UnitLevel = function() return character.level or 80 end
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return character.specID, character.specName end
  _G.IsDualWielding = function() return character.dualWielding == true end

  -- Real WoW ItemLocation is one unified object type: every instance has
  -- both GetEquipmentSlot and GetBagAndSlot, whichever doesn't apply just
  -- returns nil. Core.equipByBasics's branching (`if loc.GetEquipmentSlot
  -- then local inv = loc:GetEquipmentSlot(); if inv then ... end; if
  -- loc.GetBagAndSlot then bag,slot = loc:GetBagAndSlot() end end`) depends
  -- on that -- a bag-sourced location needs GetEquipmentSlot to exist and
  -- return nil, not be absent, or the real function's bag-path code never
  -- runs at all.
  _G.ItemLocation = {}
  function ItemLocation:CreateFromBagAndSlot(bag, slot)
    return {
      bagID = bag,
      slotIndex = slot,
      GetBagAndSlot = function(self) return self.bagID, self.slotIndex end,
      GetEquipmentSlot = function() return nil end,
    }
  end

  function ItemLocation:CreateFromEquipmentSlot(slot)
    return {
      equipmentSlot = slot,
      GetEquipmentSlot = function(self) return self.equipmentSlot end,
      GetBagAndSlot = function() return nil end,
    }
  end

  -- Titan's Grip is the one spec where a two-handed main hand doesn't force
  -- the offhand empty -- it can legally hold *either* another 2H weapon or
  -- a 1H weapon (Blizzard's own tooltip: "one-hand weapons, and two-hand
  -- weapons (or a combination)"). That means the offhand's current item
  -- *shape* can't tell you whether the physical slot constraint applies --
  -- only the character's capability can. This mirrors Weapons.lua's own
  -- policyForSpec(): allowTitanGrip is true only for WARRIOR spec 72, a
  -- fixed game-design fact (which spec has the passive), not a
  -- scoring/planning decision -- the same category of "class capability"
  -- constant Item.armor()'s ARMOR_SUBCLASS table already encodes for armor
  -- proficiency.
  local allowTitanGrip = character.classFile == "WARRIOR" and character.specID == 72

  -- Cursor-based equip mechanics, backing the real Core.equipByBasics (not
  -- a mocked replacement for it -- see ScenarioRunner). PickupInventoryItem/
  -- PickupContainerItem move an item onto a one-slot "cursor"; EquipCursorItem
  -- places the cursor item into a slot and puts whatever was there onto the
  -- cursor in exchange (the real client's equip-swap behavior); ClearCursor
  -- drops whatever's left on the cursor (modeling "went to bags", which this
  -- harness doesn't track a specific location for -- final-state assertions
  -- don't need it, per doc section 11).
  local cursor

  _G.PickupInventoryItem = function(inv)
    cursor = equippedSlot[inv]
    equippedSlot[inv] = nil
  end

  _G.ClearCursor = function()
    cursor = nil
  end

  _G.EquipCursorItem = function(targetSlot)
    if not targetSlot then return end
    local displaced = equippedSlot[targetSlot]
    equippedSlot[targetSlot] = cursor
    cursor = displaced

    -- A two-handed weapon physically occupies the offhand slot too, so the
    -- client clears slot 17 as a side effect of this specific equip action
    -- -- unless the character can legally hold something there alongside a
    -- 2H main hand (Titan's Grip), in which case whatever's in slot 17 is
    -- exactly what the planner decided it should be and this must not
    -- touch it.
    if targetSlot == 16 and not allowTitanGrip then
      local mh = equippedSlot[16]
      if mh and MH2H_EQUIPLOC[mh.equipLoc] then
        equippedSlot[17] = nil
      end
    end
  end

  _G.C_Container = {
    GetContainerNumSlots = function(bag)
      return #(bagSlots[bag] or {})
    end,
    GetContainerItemInfo = function(bag, slot)
      local item = bagSlots[bag] and bagSlots[bag][slot]
      if not item then return nil end
      return { itemID = item.itemID, hyperlink = item.link }
    end,
    GetContainerItemLink = function(bag, slot)
      local item = bagSlots[bag] and bagSlots[bag][slot]
      return item and item.link or nil
    end,
    PickupContainerItem = function(bag, slot)
      local bagTable = bagSlots[bag]
      cursor = bagTable and bagTable[slot] or nil
      if bagTable then bagTable[slot] = nil end
    end,
  }

  -- Blizzard-token -> amount table, per scenario item's `stats` field
  -- (Evaluation/CandidateNormalizer.lua's raw-stat extraction source).
  local function getItemStats(info)
    local id = parseItemID(info)
    local item = id and byID[id]
    return item and item.stats or {}
  end

  -- Requesting item data is how the real client resolves a pending item;
  -- mark it loaded here so a scenario's second PlanBest pass succeeds,
  -- modeling "data becomes available shortly after being requested".
  _G.C_Item = {
    DoesItemExist = function(loc) return itemForLoc(loc) ~= nil end,
    GetItemStats = getItemStats,
    GetItemGUID = function(loc)
      local item = itemForLoc(loc)
      return item and item.guid or nil
    end,
    GetItemLink = function(loc)
      local item = itemForLoc(loc)
      return item and item.link or nil
    end,
    GetCurrentItemLevel = function(loc)
      local item = itemForLoc(loc)
      return item and item.ilvl or 0
    end,
    RequestLoadItemData = function(loc)
      local item = itemForLoc(loc)
      if item then item.loaded = true end
    end,
    IsEquippableItem = function(info)
      local id = parseItemID(info)
      local item = id and byID[id]
      return not (item and item.equippable == false)
    end,
    GetItemUniqueness = function(info)
      local id = parseItemID(info)
      local item = id and byID[id]
      if item and item.uniqueKey then return item.uniqueKey, item.uniqueLimit or 1 end
      return nil, nil
    end,
    GetItemUniquenessByID = function(info)
      local id = parseItemID(info)
      local item = id and byID[id]
      local fallback = item and item.uniqueFallback
      if fallback then
        return fallback.isUnique, fallback.categoryName, fallback.categoryCount, fallback.categoryID
      end
      return nil, nil
    end,
    IsBound = function() return false end,
  }

  _G.GetInventoryItemLink = function(_, slot)
    local item = equippedSlot[slot]
    return item and item.link or nil
  end

  _G.GetItemInfoInstant = function(info)
    local id = parseItemID(info)
    local item = id and byID[id]
    if not item or item.loaded == false then return nil end
    return id, nil, nil, item.equipLoc, nil, item.classID, item.subclassID
  end

  _G.GetItemInfo = function(info)
    local id = parseItemID(info)
    local item = id and byID[id]
    if not item then return nil end
    return item.name or ("item-" .. tostring(id)),
        item.link,
        nil,
        item.ilvl,
        item.requiredLevel,
        nil,
        nil,
        nil,
        item.equipLoc,
        nil, nil, nil, nil, nil, nil,
        item.setID
  end

  _G.GetDetailedItemLevelInfo = function(info)
    local id = parseItemID(info)
    local item = id and byID[id]
    return item and item.ilvl or 0
  end

  -- Global GetItemStats, matching Pawn's own GetItemStatsCompat fallback
  -- order (global first, then C_Item.GetItemStats).
  _G.GetItemStats = getItemStats

  _G.InCombatLockdown = function() return false end
  _G.IsInventoryItemLocked = function() return false end

  local cmp = {
    ScoreItem = function(loc, slotID)
      local item = itemForLoc(loc)
      return item and item.scores and item.scores[slotID] or 0
    end,
  }

  return {
    equippedSlot = equippedSlot,
    bagSlots = bagSlots,
    byKey = byKey,
    byID = byID,
    itemForLoc = itemForLoc,
    cmp = cmp,
  }
end

return FakeWorld
