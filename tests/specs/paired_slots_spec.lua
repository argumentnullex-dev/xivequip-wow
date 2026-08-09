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
    Pawn = config.pawn,
  }

  _G.NUM_BAG_SLOTS = 4
  _G.UnitClass = function() return "Player", "WARRIOR" end
  _G.UnitLevel = function() return config.level or 80 end

  local function parseItemID(info)
    if type(info) == "number" then return info end
    if type(info) == "string" then return tonumber(info:match("|Hitem:(%d+)") or info:match("item:(%d+)")) end
    if type(info) == "table" then return info.itemID or info.id end
    return nil
  end

  local function itemFromEntry(entry)
    local id = parseItemID(entry)
    local base = id and items[id]
    if type(entry) ~= "table" or not base then return base end
    local copy = {}
    for k, v in pairs(base) do copy[k] = v end
    for k, v in pairs(entry) do copy[k] = v end
    copy.itemID = id
    return copy
  end

  local function itemForLoc(loc)
    if not loc then return nil end
    if loc.equipmentSlot then return items[equipped[loc.equipmentSlot]] end
    local bag = bags[loc.bagID] or {}
    return itemFromEntry(bag[loc.slotIndex])
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
      local entry = bags[bag] and bags[bag][slot]
      local id = parseItemID(entry)
      if not id then return nil end
      local item = itemFromEntry(entry)
      return { itemID = id, hyperlink = item and item.link or itemLink(id) }
    end,
    GetContainerItemLink = function(bag, slot)
      local entry = bags[bag] and bags[bag][slot]
      local id = parseItemID(entry)
      local item = itemFromEntry(entry)
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
    GetCurrentItemLevel = function(loc)
      local item = itemForLoc(loc)
      return item and item.ilvl or 0
    end,
    RequestLoadItemData = function(loc)
      local item = itemForLoc(loc)
      if item then item.requested = true end
    end,
    GetItemUniqueness = function(info)
      local id = parseItemID(info)
      local item = id and items[id]
      if item and item.uniqueKey then return item.uniqueKey, item.uniqueLimit or 1 end
      return nil, nil
    end,
    GetItemUniquenessByID = function(info)
      local id = parseItemID(info)
      local item = id and items[id]
      local fallback = item and item.uniqueFallback
      if fallback then
        return fallback.isUnique, fallback.categoryName, fallback.categoryCount, fallback.categoryID
      end
      return nil, nil
    end,
  }

  _G.GetItemStats = config.getItemStats

  _G.GetInventoryItemLink = function(_, slot)
    local item = items[equipped[slot]]
    return item and item.link or nil
  end

  _G.GetItemInfoInstant = function(info)
    local id = parseItemID(info)
    local item = id and items[id]
    if not item or item.loaded == false then return nil end
    return id, nil, nil, item.equipLoc, nil, item.classID or 4, item.subclassID or 0
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
  loadAddonFile("Gear" .. sep .. "Jewelry.lua", addon)

  local cmp = {
    ScoreItem = function(loc, slotID)
      local item = itemForLoc(loc)
      return item and item.scores and item.scores[slotID] or item and item.score or 0
    end,
  }

  return addon, cmp, config
end

local function jewelry(id, equipLoc, slotA, scoreA, slotB, scoreB, extra)
  extra = extra or {}
  extra.link = extra.link or itemLink(id)
  extra.guid = extra.guid or ("guid-" .. tostring(id))
  extra.equipLoc = equipLoc
  extra.scores = { [slotA] = scoreA, [slotB] = scoreB or scoreA }
  extra.ilvl = extra.ilvl or math.max(scoreA or 1, scoreB or scoreA or 1)
  extra.requiredLevel = extra.requiredLevel or 1
  return extra
end

local function ring(id, score11, score12, extra)
  return jewelry(id, "INVTYPE_FINGER", 11, score11, 12, score12, extra)
end

local function trinket(id, score13, score14, extra)
  return jewelry(id, "INVTYPE_TRINKET", 13, score13, 14, score14, extra)
end

local function planFor(config)
  local addon, cmp, raw = newHarness(config)
  local changes, pending, plan = addon.Jewelry:PlanBest(cmp, {}, {})
  return changes, pending, plan, raw, addon
end

local function findPick(plan, slotID)
  for _, pick in ipairs(plan) do
    if pick.targetSlot == slotID then return pick end
  end
  return nil
end

local function pickID(plan, slotID)
  local pick = findPick(plan, slotID)
  return pick and (pick.itemID or tonumber(pick.link:match("|Hitem:(%d+)"))) or nil
end

test("ring pair keeps stronger equipped ring when one bag upgrade wins", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 100, 100),
      [102] = ring(102, 80, 80),
      [201] = ring(201, 110, 110),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = { 201 } },
  })

  A.equal(#plan, 1)
  A.equal(pickID(plan, 12), 201)
  A.falsy(pickID(plan, 11), "stronger old ring should be retained in ring 1")
end)

test("ring pair chooses two distinct bag upgrades", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 100, 100),
      [102] = ring(102, 80, 80),
      [201] = ring(201, 130, 130),
      [202] = ring(202, 120, 120),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(pickID(plan, 11), 201)
  A.equal(pickID(plan, 12), 202)
end)

test("one physical ring cannot fill both slots", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 100, 100),
      [102] = ring(102, 80, 80),
      [201] = ring(201, 200, 200),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = { 201 } },
  })

  A.equal(#plan, 1)
  A.equal(pickID(plan, 12), 201)
  A.falsy(pickID(plan, 11), "the bag ring should not be planned into both slots")
end)

test("unique-equipped ring category rejects duplicate pair", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 100, 100),
      [102] = ring(102, 90, 90),
      [201] = ring(201, 200, 200, { uniqueKey = 88, uniqueLimit = 1 }),
      [202] = ring(202, 190, 190, { uniqueKey = 88, uniqueLimit = 1 }),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(#plan, 1)
  A.equal(pickID(plan, 12), 201)
  A.falsy(pickID(plan, 11), "the conflicting unique ring should not also be selected")
end)

test("slot-sensitive ring scores choose the best assignment", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 10, 10),
      [102] = ring(102, 10, 10),
      [201] = ring(201, 50, 200),
      [202] = ring(202, 190, 60),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(pickID(plan, 11), 202)
  A.equal(pickID(plan, 12), 201)
end)

test("current ring pair remains when no legal pair is better", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 100, 100),
      [102] = ring(102, 90, 90),
      [201] = ring(201, 80, 80),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = { 201 } },
  })

  A.equal(#plan, 0)
end)

test("slot-sensitive current rings can swap with one safe move", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 10, 100),
      [102] = ring(102, 90, 20),
    },
    equipped = { [11] = 101, [12] = 102 },
  })

  A.equal(#plan, 1)
  A.equal(pickID(plan, 11), 102)
end)

test("trinket pair keeps stronger equipped trinket when one bag upgrade wins", function()
  local _, _, plan = planFor({
    items = {
      [101] = trinket(101, 100, 100),
      [102] = trinket(102, 80, 80),
      [201] = trinket(201, 110, 110),
    },
    equipped = { [13] = 101, [14] = 102 },
    bags = { [0] = { 201 } },
  })

  A.equal(#plan, 1)
  A.equal(pickID(plan, 14), 201)
  A.falsy(pickID(plan, 13), "stronger old trinket should be retained in trinket 1")
end)

test("one bag ring can equip when both ring slots are empty", function()
  local _, _, plan = planFor({
    items = {
      [201] = ring(201, 100, 100),
    },
    bags = { [0] = { 201 } },
  })

  A.equal(#plan, 1)
  A.equal(pickID(plan, 11), 201)
end)

test("empty ring slots still equip the best negative-scoring rings", function()
  local _, _, plan = planFor({
    items = {
      [201] = ring(201, -500, -500),
      [202] = ring(202, -100, -100),
      [203] = ring(203, -50, -50),
    },
    bags = { [0] = { 201, 202, 203 } },
  })

  A.equal(#plan, 2)
  A.truthy(pickID(plan, 11) == 203 or pickID(plan, 12) == 203)
  A.truthy(pickID(plan, 11) == 202 or pickID(plan, 12) == 202)
  A.falsy(pickID(plan, 11) == 201 or pickID(plan, 12) == 201,
    "the worst negative-scoring ring should not be selected")
end)

test("empty ring slots ignore deep item-level downgrades when current-tier rings are available", function()
  local _, _, plan = planFor({
    items = {
      [201] = ring(201, 1000, 1000, { ilvl = 192 }),
      [202] = ring(202, 100, 100, { ilvl = 246 }),
      [203] = ring(203, 90, 90, { ilvl = 246 }),
    },
    bags = { [0] = { 201, 202, 203 } },
  })

  A.equal(#plan, 2)
  A.truthy(pickID(plan, 11) == 202 or pickID(plan, 12) == 202)
  A.truthy(pickID(plan, 11) == 203 or pickID(plan, 12) == 203)
  A.falsy(pickID(plan, 11) == 201 or pickID(plan, 12) == 201,
    "a much lower item-level ring should not beat enough current-tier options by score alone")
end)

test("one bag ring fills the empty paired slot without replacing the occupied slot", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 100, 100),
      [201] = ring(201, 90, 90),
    },
    equipped = { [11] = 101 },
    bags = { [0] = { 201 } },
  })

  A.equal(#plan, 1)
  A.equal(pickID(plan, 12), 201)
  A.falsy(pickID(plan, 11), "occupied ring should stay put")
end)

test("empty trinket slots still equip the best negative-scoring trinkets", function()
  local _, _, plan = planFor({
    items = {
      [201] = trinket(201, -700, -700),
      [202] = trinket(202, -200, -200),
      [203] = trinket(203, -20, -20),
    },
    bags = { [0] = { 201, 202, 203 } },
  })

  A.equal(#plan, 2)
  A.truthy(pickID(plan, 13) == 203 or pickID(plan, 14) == 203)
  A.truthy(pickID(plan, 13) == 202 or pickID(plan, 14) == 202)
  A.falsy(pickID(plan, 13) == 201 or pickID(plan, 14) == 201,
    "the worst negative-scoring trinket should not be selected")
end)

test("empty trinket slots ignore deep item-level downgrades when current-tier trinkets are available", function()
  local _, _, plan = planFor({
    items = {
      [201] = trinket(201, 1000, 1000, { ilvl = 192 }),
      [202] = trinket(202, 100, 100, { ilvl = 246 }),
      [203] = trinket(203, 90, 90, { ilvl = 246 }),
    },
    bags = { [0] = { 201, 202, 203 } },
  })

  A.equal(#plan, 2)
  A.truthy(pickID(plan, 13) == 202 or pickID(plan, 14) == 202)
  A.truthy(pickID(plan, 13) == 203 or pickID(plan, 14) == 203)
  A.falsy(pickID(plan, 13) == 201 or pickID(plan, 14) == 201,
    "a much lower item-level trinket should not beat enough current-tier options by score alone")
end)

test("mixed uniqueness APIs normalize the same category", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 10, 10),
      [102] = ring(102, 10, 10),
      [201] = ring(201, 200, 200, { uniqueKey = 88, uniqueLimit = 1 }),
      [202] = ring(202, 190, 190, {
        uniqueFallback = { categoryID = 88, categoryCount = 1 },
      }),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(#plan, 1)
  A.truthy(pickID(plan, 11) == 201 or pickID(plan, 12) == 201)
  A.falsy(pickID(plan, 11) == 202 or pickID(plan, 12) == 202,
    "fallback uniqueness category should conflict with primary API category")
end)

test("different item-specific unique rings may be equipped together", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 10, 10),
      [102] = ring(102, 10, 10),
      [201] = ring(201, 200, 200, { uniqueKey = 0, uniqueLimit = 1 }),
      [202] = ring(202, 190, 190, { uniqueKey = 0, uniqueLimit = 1 }),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(#plan, 2)
  A.truthy(pickID(plan, 11) == 201 or pickID(plan, 12) == 201)
  A.truthy(pickID(plan, 11) == 202 or pickID(plan, 12) == 202)
end)

test("two copies of the same item-specific unique ring are rejected", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 10, 10),
      [102] = ring(102, 10, 10),
      [201] = ring(201, 200, 200, { uniqueKey = 0, uniqueLimit = 1 }),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = {
      { itemID = 201, guid = "guid-201-a" },
      { itemID = 201, guid = "guid-201-b" },
    } },
  })

  A.equal(#plan, 1)
  A.truthy(pickID(plan, 11) == 201 or pickID(plan, 12) == 201)
end)

test("category zero with limit zero is treated as non-unique for rings", function()
  local _, _, plan = planFor({
    items = {
      [201] = ring(201, 200, 200, { uniqueKey = 0, uniqueLimit = 0, ilvl = 246 }),
      [202] = ring(202, 190, 190, { uniqueKey = 0, uniqueLimit = 0, ilvl = 246 }),
    },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(#plan, 2)
  A.truthy(pickID(plan, 11) == 201 or pickID(plan, 12) == 201)
  A.truthy(pickID(plan, 11) == 202 or pickID(plan, 12) == 202)
end)

test("category zero with limit zero is treated as non-unique for trinkets", function()
  local _, _, plan = planFor({
    items = {
      [201] = trinket(201, 200, 200, { uniqueKey = 0, uniqueLimit = 0, ilvl = 246 }),
      [202] = trinket(202, 190, 190, { uniqueKey = 0, uniqueLimit = 0, ilvl = 246 }),
    },
    bags = { [0] = { 201, 202 } },
  })

  A.equal(#plan, 2)
  A.truthy(pickID(plan, 13) == 201 or pickID(plan, 14) == 201)
  A.truthy(pickID(plan, 13) == 202 or pickID(plan, 14) == 202)
end)

test("loadout-wide unique category already consumed by armor rejects jewelry", function()
  local _, _, plan = planFor({
    items = {
      [301] = jewelry(301, "INVTYPE_HEAD", 1, 10, 1, 10, { uniqueKey = 88, uniqueLimit = 2 }),
      [302] = jewelry(302, "INVTYPE_SHOULDER", 3, 10, 3, 10, { uniqueKey = 88, uniqueLimit = 2 }),
      [201] = ring(201, 200, 200, { uniqueKey = 88, uniqueLimit = 2 }),
    },
    equipped = { [1] = 301, [3] = 302 },
    bags = { [0] = { 201 } },
  })

  A.equal(#plan, 0)
end)

test("paired jewelry preserves the 80 item-level safety floor", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 100, 100, { ilvl = 500 }),
      [102] = ring(102, 90, 90, { ilvl = 500 }),
      [201] = ring(201, 1000, 1000, { ilvl = 419 }),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = { 201 } },
  })

  A.equal(#plan, 0)
end)

test("empty-slot ilvl floor never leaves a slot empty when a legal ring is available", function()
  local _, _, plan = planFor({
    items = {
      [101] = ring(101, 100, 100, { ilvl = 700 }),
      [201] = ring(201, 50, 50, { ilvl = 650 }),
    },
    equipped = { [11] = 101 },
    bags = { [0] = { 201 } },
  })

  A.equal(#plan, 1)
  A.equal(pickID(plan, 12), 201, "the only bag ring should fill the empty slot even though it is far below the floor")
  A.falsy(pickID(plan, 11), "occupied ring should stay put")
end)

test("empty-slot ilvl floor never blocks a legal pair when high-ilvl candidates conflict", function()
  local _, _, plan = planFor({
    items = {
      [201] = ring(201, 200, 200, { ilvl = 700, uniqueKey = 88, uniqueLimit = 1 }),
      [202] = ring(202, 190, 190, { ilvl = 690, uniqueKey = 88, uniqueLimit = 1 }),
      [203] = ring(203, 100, 100, { ilvl = 600 }),
    },
    bags = { [0] = { 201, 202, 203 } },
  })

  A.equal(#plan, 2)
  A.truthy(pickID(plan, 11) == 201 or pickID(plan, 12) == 201, "the higher-ilvl unique ring should be picked")
  A.truthy(pickID(plan, 11) == 203 or pickID(plan, 12) == 203,
    "the lower-ilvl ring is required to complete a legal pair and must not be filtered by the floor")
  A.falsy(pickID(plan, 11) == 202 or pickID(plan, 12) == 202,
    "the conflicting unique-equipped ring should not also be selected")
end)

test("paired jewelry records socket potential for non-upgrade candidates", function()
  local _, _, plan, _, addon = planFor({
    items = {
      [101] = ring(101, 100, 100, { ilvl = 500 }),
      [102] = ring(102, 100, 100, { ilvl = 500 }),
      [201] = ring(201, 95, 95, { ilvl = 500 }),
    },
    equipped = { [11] = 101, [12] = 102 },
    bags = { [0] = { 201 } },
    pawn = {
      GetBestScaleValuesForPlayer = function()
        return { CritRating = 1, HasteRating = 0, MasteryRating = 0, Versatility = 0 }
      end,
      GetSocketAssumptionSecondaryAmount = function() return 10 end,
    },
    getItemStats = function(link)
      if link and link:match("|Hitem:201") then return { EMPTY_SOCKET_PRISMATIC = 1 } end
      return {}
    end,
  })

  A.equal(#plan, 0)
  local potentials = addon.Gear_Core.GetSocketPotential()
  A.equal(#potentials, 1)
  A.equal(potentials[1].slotID, 11)
end)

test("equipped ring move executes as an equipment-slot transfer", function()
  local _, _, plan, raw, addon = planFor({
    items = {
      [101] = ring(101, 10, 100),
      [102] = ring(102, 90, 20),
    },
    equipped = { [11] = 101, [12] = 102 },
  })

  A.equal(#plan, 1)
  addon.Gear_Core.equipByBasics(plan[1])
  A.equal(raw.lastPickup, 12)
  A.equal(raw.lastEquip, 11)
end)

return tests
