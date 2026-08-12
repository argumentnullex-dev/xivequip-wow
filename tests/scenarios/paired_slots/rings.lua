-- tests/scenarios/paired_slots/rings.lua
-- Doc section 7's ring-pair contract bullets, ported from the existing
-- existing planner-level paired-slot tests (doc migration
-- Step 2: port behavior, not test implementation). Where the original test
-- accepted either slot for a symmetric-scored item ("truthy(pickID(11)==x
-- or pickID(12)==x)"), scores here are made slot-asymmetric so the
-- black-box final-state assertion (which is necessarily slot-specific) has
-- a single correct answer -- the underlying behavior under test is
-- unchanged. Execution specs cover exact plan shape and move ordering.

local root = ...
local sep = package.config:sub(1, 1)
local Item = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "item_builder.lua")

local function ring(id, s11, s12, extra) return Item.ring(id, s11, s12, extra) end

return {

  {
    name = "ring pair: two distinct bag upgrades replace both equipped rings",
    items = {
      old11 = ring(101, 100, 100),
      old12 = ring(102, 80, 80),
      new11 = ring(201, 130, 130),
      new12 = ring(202, 120, 120),
    },
    equipped = { [11] = "old11", [12] = "old12" },
    bags = { [0] = { "new11", "new12" } },
    expect = { final = { [11] = "new11", [12] = "new12" } },
  },

  {
    name = "ring pair: one physical ring cannot fill both slots",
    items = {
      old11 = ring(101, 100, 100),
      old12 = ring(102, 80, 80),
      upgrade = ring(201, 200, 200),
    },
    equipped = { [11] = "old11", [12] = "old12" },
    bags = { [0] = { "upgrade" } },
    expect = { final = { [12] = "upgrade" }, unchanged = { 11 } },
  },

  {
    name = "ring pair: unique-equipped category rejects a conflicting duplicate",
    items = {
      old11 = ring(101, 100, 100),
      old12 = ring(102, 90, 90),
      keep = ring(201, 200, 200, { uniqueKey = 88, uniqueLimit = 1 }),
      conflict = ring(202, 190, 190, { uniqueKey = 88, uniqueLimit = 1 }),
    },
    equipped = { [11] = "old11", [12] = "old12" },
    bags = { [0] = { "keep", "conflict" } },
    expect = { final = { [12] = "keep" }, unchanged = { 11 } },
  },

  {
    name = "ring pair: slot-sensitive scores choose the globally best assignment",
    items = {
      old11 = ring(101, 10, 10),
      old12 = ring(102, 10, 10),
      favors12 = ring(201, 50, 200),
      favors11 = ring(202, 190, 60),
    },
    equipped = { [11] = "old11", [12] = "old12" },
    bags = { [0] = { "favors12", "favors11" } },
    expect = { final = { [11] = "favors11", [12] = "favors12" } },
  },

  {
    name = "ring pair: current pair remains when no legal pair is better",
    items = {
      old11 = ring(101, 100, 100),
      old12 = ring(102, 90, 90),
      weakBag = ring(201, 80, 80),
    },
    equipped = { [11] = "old11", [12] = "old12" },
    bags = { [0] = { "weakBag" } },
    expect = { unchanged = { 11, 12 } },
  },

  {
    -- Production only records one plan step for this: a single
    -- equipment-slot transfer of ringB from 12 into 11 (see
    -- Core.equipByBasics's GetEquipmentSlot path, PickupInventoryItem +
    -- EquipCursorItem). That's a real client equip action, not an in-place
    -- swap -- the displaced ringA leaves slot 12 (to the player's bags,
    -- which this harness doesn't model further) rather than landing in 12.
    name = "ring pair: slot-sensitive equipped rings -- the better ring moves in, the displaced ring leaves",
    items = {
      ringA = ring(101, 10, 100),
      ringB = ring(102, 90, 20),
    },
    equipped = { [11] = "ringA", [12] = "ringB" },
    expect = { final = { [11] = "ringB", [12] = false } },
  },

  {
    name = "ring pair: one bag ring equips when both slots are empty",
    items = { onlyRing = ring(201, 100, 100) },
    equipped = {},
    bags = { [0] = { "onlyRing" } },
    expect = { final = { [11] = "onlyRing" } },
  },

  {
    name = "ring pair: one bag ring fills the empty slot without disturbing the occupied one",
    items = {
      occupied = ring(101, 100, 100),
      filler = ring(201, 90, 90),
    },
    equipped = { [11] = "occupied" },
    bags = { [0] = { "filler" } },
    expect = { final = { [12] = "filler" }, unchanged = { 11 } },
  },

  {
    name = "ring pair: empty slots still equip the best negative-scoring rings, worst excluded",
    items = {
      worst = ring(201, -500, -500),
      mid = ring(202, -100, -110),
      best = ring(203, -60, -50),
    },
    equipped = {},
    bags = { [0] = { "worst", "mid", "best" } },
    expect = { final = { [11] = "mid", [12] = "best" } },
  },

  {
    name = "ring pair: empty-slot ilvl floor never leaves a slot empty when a legal ring is available",
    items = {
      occupied = ring(101, 100, 100, { itemLevel = 700 }),
      farBelowFloor = ring(201, 50, 50, { itemLevel = 650 }),
    },
    equipped = { [11] = "occupied" },
    bags = { [0] = { "farBelowFloor" } },
    expect = { final = { [12] = "farBelowFloor" }, unchanged = { 11 } },
  },

  {
    name = "ring pair: empty-slot ilvl floor never blocks a legal pair when high-ilvl candidates conflict",
    items = {
      highA = ring(201, 200, 200, { itemLevel = 700, uniqueKey = 88, uniqueLimit = 1 }),
      highB = ring(202, 190, 190, { itemLevel = 690, uniqueKey = 88, uniqueLimit = 1 }),
      lowLegal = ring(203, 100, 100, { itemLevel = 600 }),
    },
    equipped = {},
    bags = { [0] = { "highA", "highB", "lowLegal" } },
    expect = { final = { [11] = "highA", [12] = "lowLegal" } },
  },

  {
    name = "ring pair: paired jewelry preserves the 80 item-level safety floor",
    items = {
      old11 = ring(101, 100, 100, { itemLevel = 500 }),
      old12 = ring(102, 90, 90, { itemLevel = 500 }),
      hugeScoreLowIlvl = ring(201, 1000, 1000, { itemLevel = 419 }),
    },
    equipped = { [11] = "old11", [12] = "old12" },
    bags = { [0] = { "hugeScoreLowIlvl" } },
    expect = { unchanged = { 11, 12 } },
  },

  {
    name = "ring pair: empty ring slots ignore a deep item-level downgrade when current-tier rings are available",
    items = {
      hugeScoreLowIlvl = ring(201, 1000, 1000, { itemLevel = 192 }),
      currentTierA = ring(202, 100, 95, { itemLevel = 246 }),
      currentTierB = ring(203, 90, 105, { itemLevel = 246 }),
    },
    equipped = {},
    bags = { [0] = { "hugeScoreLowIlvl", "currentTierA", "currentTierB" } },
    expect = { final = { [11] = "currentTierA", [12] = "currentTierB" } },
  },

  {
    name = "ring pair: different item-specific unique rings may be equipped together",
    items = {
      old11 = ring(101, 10, 10),
      old12 = ring(102, 10, 10),
      itemUniqueA = ring(201, 200, 190, { uniqueKey = 0, uniqueLimit = 1 }),
      itemUniqueB = ring(202, 180, 195, { uniqueKey = 0, uniqueLimit = 1 }),
    },
    equipped = { [11] = "old11", [12] = "old12" },
    bags = { [0] = { "itemUniqueA", "itemUniqueB" } },
    expect = { final = { [11] = "itemUniqueA", [12] = "itemUniqueB" } },
  },

  {
    name = "ring pair: two physical copies of the same item-specific unique ring are rejected",
    items = {
      old11 = ring(101, 10, 10),
      old12 = ring(102, 10, 10),
      itemUnique = ring(201, 200, 50, { uniqueKey = 0, uniqueLimit = 1 }),
    },
    equipped = { [11] = "old11", [12] = "old12" },
    bags = { [0] = {
      { item = "itemUnique", guid = "guid-201-a" },
      { item = "itemUnique", guid = "guid-201-b" },
    } },
    expect = { final = { [11] = "itemUnique" }, unchanged = { 12 } },
  },

  {
    name = "ring pair: category zero with limit zero is treated as non-unique",
    items = {
      nonUniqueA = ring(201, 200, 150, { uniqueKey = 0, uniqueLimit = 0, itemLevel = 246 }),
      nonUniqueB = ring(202, 140, 190, { uniqueKey = 0, uniqueLimit = 0, itemLevel = 246 }),
    },
    equipped = {},
    bags = { [0] = { "nonUniqueA", "nonUniqueB" } },
    expect = { final = { [11] = "nonUniqueA", [12] = "nonUniqueB" } },
  },

  {
    name = "ring pair: mixed uniqueness APIs normalize to the same conflicting category",
    items = {
      old11 = ring(101, 10, 10),
      old12 = ring(102, 10, 10),
      primaryApi = ring(201, 200, 90, { uniqueKey = 88, uniqueLimit = 1 }),
      fallbackApi = ring(202, 190, 95, { uniqueFallback = { categoryID = 88, categoryCount = 1 } }),
    },
    equipped = { [11] = "old11", [12] = "old12" },
    bags = { [0] = { "primaryApi", "fallbackApi" } },
    expect = { final = { [11] = "primaryApi" }, unchanged = { 12 } },
  },
}
