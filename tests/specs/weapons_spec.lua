local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function join(...)
  return table.concat({ ... }, sep)
end

local function loadAddonFile(rel, addon)
  local chunk = assert(loadfile(join(root, "XIVEquip", rel)))
  chunk("XIVEquip", addon)
end

local function itemLink(id)
  return "|Hitem:" .. tostring(id) .. "::::::::::::|h[item-" .. tostring(id) .. "]|h"
end

local function newHarness(config)
  config = config or {}
  local items = config.items or {}
  local equipped = config.equipped or {}
  local bags = config.bags or {}

  local addon = {
    Log = {
      Debug = function() end,
      Info = function() end,
      Warn = function() end,
      Error = function() end,
      Debugf = function() end,
    },
  }

  _G.NUM_BAG_SLOTS = 4
  _G.UnitClass = function() return "Player", config.class or "WARRIOR" end
  _G.UnitLevel = function() return config.level or 80 end
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return config.specID or 72, config.specName or "Fury" end
  _G.IsDualWielding = function() return config.dualWielding == true end

  local function parseItemID(info)
    if type(info) == "number" then return info end
    if type(info) == "string" then return tonumber(info:match("|Hitem:(%d+)") or info:match("item:(%d+)")) end
    return nil
  end

  local function itemForLoc(loc)
    if not loc then return nil end
    if loc.equipmentSlot then return items[equipped[loc.equipmentSlot]] end
    local bag = bags[loc.bagID] or {}
    return items[bag[loc.slotIndex]]
  end

  _G.ItemLocation = {}
  function ItemLocation:CreateFromBagAndSlot(bag, slot)
    return {
      bagID = bag,
      slotIndex = slot,
      GetBagAndSlot = function(self) return self.bagID, self.slotIndex end,
    }
  end
  function ItemLocation:CreateFromEquipmentSlot(slot)
    return {
      equipmentSlot = slot,
      GetEquipmentSlot = function(self) return self.equipmentSlot end,
    }
  end

  _G.C_Container = {
    GetContainerNumSlots = function(bag)
      return #(bags[bag] or {})
    end,
    GetContainerItemInfo = function(bag, slot)
      local id = bags[bag] and bags[bag][slot]
      if not id then return nil end
      local item = items[id]
      return { itemID = id, hyperlink = item and item.link or itemLink(id) }
    end,
    GetContainerItemLink = function(bag, slot)
      local id = bags[bag] and bags[bag][slot]
      local item = id and items[id]
      return item and item.link or (id and itemLink(id)) or nil
    end,
  }

  _G.C_Item = {
    DoesItemExist = function(loc)
      return itemForLoc(loc) ~= nil
    end,
    GetItemGUID = function(loc)
      local item = itemForLoc(loc)
      return item and item.guid or nil
    end,
    GetItemLink = function(loc)
      local item = itemForLoc(loc)
      return item and item.link or nil
    end,
    RequestLoadItemData = function(loc)
      local item = itemForLoc(loc)
      if item then item.requested = true end
    end,
    IsEquippableItem = function(info)
      local id = parseItemID(info)
      local item = id and items[id]
      return not (item and item.equippable == false)
    end,
    GetItemUniqueness = function(info)
      local id = parseItemID(info)
      local item = id and items[id]
      if item and item.uniqueKey then return item.uniqueKey, item.uniqueLimit or 1 end
      return nil, nil
    end,
  }

  _G.GetInventoryItemLink = function(_, slot)
    local item = items[equipped[slot]]
    return item and item.link or nil
  end

  _G.GetItemInfoInstant = function(info)
    local id = parseItemID(info)
    local item = id and items[id]
    if not item or item.loaded == false then return nil end
    return id, nil, nil, item.equipLoc, nil, item.classID or 2, item.subclassID or 0
  end

  _G.GetItemInfo = function(info)
    local id = parseItemID(info)
    local item = id and items[id]
    if not item then return nil end
    return item.name or ("item-" .. tostring(id)),
        item.link,
        nil,
        item.ilvl or 1,
        item.requiredLevel or 1,
        nil,
        nil,
        nil,
        item.equipLoc
  end

  _G.GetDetailedItemLevelInfo = function(info)
    local id = parseItemID(info)
    local item = id and items[id]
    return item and item.ilvl or 0
  end

  _G.ClearCursor = function() end
  _G.PickupInventoryItem = function(slot) config.lastPickup = slot end
  _G.EquipCursorItem = function(slot) config.lastEquip = slot end

  loadAddonFile("Global" .. sep .. "Constants.lua", addon)
  loadAddonFile("Core" .. sep .. "GearCore.lua", addon)
  loadAddonFile("Gear" .. sep .. "Weapons.lua", addon)

  local cmp = {
    ScoreItem = function(loc, slotID)
      local item = itemForLoc(loc)
      return item and item.scores and item.scores[slotID] or item and item.score or 0
    end,
  }

  return addon, cmp, config
end

local function weapon(id, equipLoc, mhScore, ohScore, extra)
  extra = extra or {}
  extra.link = extra.link or itemLink(id)
  extra.guid = extra.guid or ("guid-" .. tostring(id))
  extra.equipLoc = equipLoc
  extra.scores = { [16] = mhScore, [17] = ohScore or mhScore }
  extra.ilvl = extra.ilvl or mhScore
  extra.requiredLevel = extra.requiredLevel or 1
  return extra
end

local function planFor(config)
  local addon, cmp = newHarness(config)
  local changes, pending, plan = addon.Weapons:PlanBest(cmp, {}, {})
  return changes, pending, plan
end

local function findPick(plan, slotID)
  for _, pick in ipairs(plan) do
    if pick.targetSlot == slotID then return pick end
  end
  return nil
end

test("Fury 2H plus 2H current loadout is legal", function()
  local _, pending, plan = planFor({
    class = "WARRIOR",
    specID = 72,
    items = {
      [101] = weapon(101, "INVTYPE_2HWEAPON", 100, 100),
      [102] = weapon(102, "INVTYPE_2HWEAPON", 80, 80),
    },
    equipped = { [16] = 101, [17] = 102 },
  })

  A.falsy(pending)
  A.equal(#plan, 0, "legal current Titan's Grip loadout should not force a replacement")
end)

test("Fury chooses best two distinct 2H weapons across equipped and bags", function()
  local _, _, plan = planFor({
    class = "WARRIOR",
    specID = 72,
    items = {
      [101] = weapon(101, "INVTYPE_2HWEAPON", 100, 100),
      [102] = weapon(102, "INVTYPE_2HWEAPON", 80, 80),
      [201] = weapon(201, "INVTYPE_2HWEAPON", 120, 120),
      [202] = weapon(202, "INVTYPE_2HWEAPON", 110, 110),
    },
    equipped = { [16] = 101, [17] = 102 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(findPick(plan, 16).itemID or tonumber(findPick(plan, 16).link:match("|Hitem:(%d+)")), 201)
  A.equal(findPick(plan, 17).itemID or tonumber(findPick(plan, 17).link:match("|Hitem:(%d+)")), 202)
end)

test("Fury can move displaced current 2H main hand to offhand", function()
  local _, _, plan = planFor({
    class = "WARRIOR",
    specID = 72,
    items = {
      [101] = weapon(101, "INVTYPE_2HWEAPON", 100, 100),
      [102] = weapon(102, "INVTYPE_2HWEAPON", 80, 80),
      [201] = weapon(201, "INVTYPE_2HWEAPON", 150, 150),
    },
    equipped = { [16] = 101, [17] = 102 },
    bags = { [0] = { 201 } },
  })

  A.equal(tonumber(plan[1].link:match("|Hitem:(%d+)")), 101, "current main hand should move first")
  A.equal(plan[1].targetSlot, 17)
  A.equal(tonumber(findPick(plan, 16).link:match("|Hitem:(%d+)")), 201)
end)

test("Fury can choose a mixed 2H main hand and 1H offhand loadout", function()
  local _, _, plan = planFor({
    class = "WARRIOR",
    specID = 72,
    items = {
      [101] = weapon(101, "INVTYPE_2HWEAPON", 100, 100),
      [102] = weapon(102, "INVTYPE_2HWEAPON", 80, 80),
      [201] = weapon(201, "INVTYPE_2HWEAPON", 130, 130),
      [202] = weapon(202, "INVTYPE_WEAPON", 120, 120),
    },
    equipped = { [16] = 101, [17] = 102 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(tonumber(findPick(plan, 16).link:match("|Hitem:(%d+)")), 201)
  A.equal(tonumber(findPick(plan, 17).link:match("|Hitem:(%d+)")), 202)
end)

test("Fury can choose a mixed 1H main hand and 2H offhand loadout", function()
  local _, _, plan = planFor({
    class = "WARRIOR",
    specID = 72,
    items = {
      [101] = weapon(101, "INVTYPE_2HWEAPON", 100, 100),
      [102] = weapon(102, "INVTYPE_2HWEAPON", 80, 80),
      [201] = weapon(201, "INVTYPE_WEAPON", 140, 140),
      [202] = weapon(202, "INVTYPE_2HWEAPON", 120, 120),
    },
    equipped = { [16] = 101, [17] = 102 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(tonumber(findPick(plan, 16).link:match("|Hitem:(%d+)")), 201)
  A.equal(tonumber(findPick(plan, 17).link:match("|Hitem:(%d+)")), 202)
end)

test("Arms uses one legal 2H and no offhand", function()
  local _, _, plan = planFor({
    class = "WARRIOR",
    specID = 71,
    items = {
      [101] = weapon(101, "INVTYPE_2HWEAPON", 100, 100),
      [201] = weapon(201, "INVTYPE_2HWEAPON", 120, 120),
      [202] = weapon(202, "INVTYPE_WEAPON", 999, 999),
    },
    equipped = { [16] = 101 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(#plan, 1)
  A.equal(findPick(plan, 16).targetSlot, 16)
  A.falsy(findPick(plan, 17))
end)

test("Protection Warrior requires a shield", function()
  local _, _, plan = planFor({
    class = "WARRIOR",
    specID = 73,
    items = {
      [101] = weapon(101, "INVTYPE_WEAPON", 100, 100),
      [102] = weapon(102, "INVTYPE_SHIELD", 40, 40),
      [201] = weapon(201, "INVTYPE_2HWEAPON", 999, 999),
      [202] = weapon(202, "INVTYPE_WEAPON", 120, 120),
    },
    equipped = { [16] = 101, [17] = 102 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(#plan, 1)
  A.equal(tonumber(findPick(plan, 16).link:match("|Hitem:(%d+)")), 202)
  A.falsy(findPick(plan, 17), "current shield should be retained")
end)

test("Retribution does not accept a lone 1H as final loadout", function()
  local _, _, plan = planFor({
    class = "PALADIN",
    specID = 70,
    items = {
      [101] = weapon(101, "INVTYPE_2HWEAPON", 100, 100),
      [201] = weapon(201, "INVTYPE_WEAPON", 999, 999),
    },
    equipped = { [16] = 101 },
    bags = { [0] = { 201 } },
  })

  A.equal(#plan, 0)
end)

test("dual wield specs can reuse displaced current main hand as offhand", function()
  local _, _, plan = planFor({
    class = "ROGUE",
    specID = 260,
    items = {
      [101] = weapon(101, "INVTYPE_WEAPON", 100, 100),
      [102] = weapon(102, "INVTYPE_WEAPON", 80, 80),
      [201] = weapon(201, "INVTYPE_WEAPON", 110, 110),
    },
    equipped = { [16] = 101, [17] = 102 },
    bags = { [0] = { 201 } },
  })

  A.equal(tonumber(plan[1].link:match("|Hitem:(%d+)")), 101)
  A.equal(plan[1].targetSlot, 17)
  A.equal(tonumber(findPick(plan, 16).link:match("|Hitem:(%d+)")), 201)
end)

test("required level and unusable weapons are excluded", function()
  local _, _, plan = planFor({
    class = "WARRIOR",
    specID = 71,
    level = 70,
    items = {
      [101] = weapon(101, "INVTYPE_2HWEAPON", 100, 100),
      [201] = weapon(201, "INVTYPE_2HWEAPON", 999, 999, { requiredLevel = 80 }),
      [202] = weapon(202, "INVTYPE_2HWEAPON", 998, 998, { equippable = false }),
    },
    equipped = { [16] = 101 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(#plan, 0)
end)

test("unloaded weapon data marks the pass pending", function()
  local _, pending, plan = planFor({
    class = "WARRIOR",
    specID = 71,
    items = {
      [101] = weapon(101, "INVTYPE_2HWEAPON", 100, 100),
      [201] = weapon(201, nil, 999, 999, { loaded = false }),
    },
    equipped = { [16] = 101 },
    bags = { [0] = { 201 } },
  })

  A.truthy(pending)
  A.equal(#plan, 0)
end)

test("unique-equipped weapon pairs are rejected", function()
  local _, _, plan = planFor({
    class = "ROGUE",
    specID = 260,
    items = {
      [101] = weapon(101, "INVTYPE_WEAPON", 100, 100),
      [102] = weapon(102, "INVTYPE_WEAPON", 90, 90),
      [201] = weapon(201, "INVTYPE_WEAPON", 200, 200, { uniqueKey = 77, uniqueLimit = 1 }),
      [202] = weapon(202, "INVTYPE_WEAPON", 190, 190, { uniqueKey = 77, uniqueLimit = 1 }),
    },
    equipped = { [16] = 101, [17] = 102 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(tonumber(findPick(plan, 16).link:match("|Hitem:(%d+)")), 201)
  A.equal(tonumber(findPick(plan, 17).link:match("|Hitem:(%d+)")), 101)
end)

test("equipment-slot ItemLocations can move between hand slots", function()
  local addon, _, config = newHarness({
    items = {
      [101] = weapon(101, "INVTYPE_WEAPON", 100, 100),
    },
    equipped = { [16] = 101 },
  })

  addon.Gear_Core.equipByBasics({
    loc = ItemLocation:CreateFromEquipmentSlot(16),
    link = itemLink(101),
    targetSlot = 17,
  })

  A.equal(config.lastPickup, 16)
  A.equal(config.lastEquip, 17)
end)

return tests
