-- tests/scenarios/coordinator/scenarios.lua
-- Doc section 8's full coordinator scenarios (8.1-8.5) -- the biggest gap
-- called out in the doc: "no test runs the actual coordinator across
-- armor, jewelry, and weapons." These drive addon.Gear:PlanBest/EquipBest
-- (the top-level orchestrator in Gear/Interface.lua), not an individual
-- planner, so they exercise cross-planner uniqueness tracking and the
-- shared `used` context for real.

local root = ...
local sep = package.config:sub(1, 1)
local Item = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "item_builder.lua")

return {

  -- 8.1 Naked to complete equipment
  {
    name = "coordinator: naked character equips the best legal item in every fillable slot",
    character = { classFile = "WARRIOR", specID = 71, specName = "Arms" },
    items = {
      head = Item.armor(101, "INVTYPE_HEAD", 1, "plate", 100),
      headTrap = Item.armor(102, "INVTYPE_HEAD", 1, "mail", 200),
      neck = Item.jewelry(201, "INVTYPE_NECK", 2, 90, 2, 90),
      cloak = Item.jewelry(301, "INVTYPE_CLOAK", 15, 85, 15, 85),
      ring1 = Item.ring(401, 70, 60),
      ring2 = Item.ring(402, 65, 75),
      trinket1 = Item.trinket(501, 55, 45),
      trinket2 = Item.trinket(502, 50, 58),
      weapon = Item.weapon(601, "INVTYPE_2HWEAPON", 120, 120),
      weaponTrap = Item.weapon(602, "INVTYPE_WEAPON", 999, 999),
    },
    equipped = {},
    bags = {
      [0] = {
        "head", "headTrap", "neck", "cloak",
        "ring1", "ring2", "trinket1", "trinket2",
        "weapon", "weaponTrap",
      },
    },
    expect = {
      final = {
        [1] = "head",
        [2] = "neck",
        [15] = "cloak",
        [11] = "ring1",
        [12] = "ring2",
        [13] = "trinket1",
        [14] = "trinket2",
        [16] = "weapon",
      },
      unchanged = { 17 },
      pending = false,
    },
  },

  -- 8.2 Partially equipped upgrade pass
  {
    name = "coordinator: only the slots with a real upgrade change, equal-score slots don't churn",
    character = { classFile = "WARRIOR", specID = 71, specName = "Arms" },
    items = {
      goodHead = Item.armor(101, "INVTYPE_HEAD", 1, "plate", 100),
      worseHeadTrap = Item.armor(102, "INVTYPE_HEAD", 1, "plate", 50),
      goodNeck = Item.jewelry(201, "INVTYPE_NECK", 2, 90, 2, 90),
      worseNeckTrap = Item.jewelry(202, "INVTYPE_NECK", 2, 40, 2, 40),
      ring1 = Item.ring(301, 70, 70),
      ring2 = Item.ring(302, 70, 70),
      weakTrinket1 = Item.trinket(401, 50, 50),
      trinket2 = Item.trinket(402, 80, 80),
      upgradeTrinket1 = Item.trinket(403, 90, 90),
    },
    equipped = {
      [1] = "goodHead",
      [2] = "goodNeck",
      [11] = "ring1",
      [12] = "ring2",
      [13] = "weakTrinket1",
      [14] = "trinket2",
    },
    bags = { [0] = { "worseHeadTrap", "worseNeckTrap", "upgradeTrinket1" } },
    expect = {
      final = { [13] = "upgradeTrinket1" },
      unchanged = { 1, 2, 11, 12, 14 },
    },
  },

  -- 8.3 Shared uniqueness across planners
  {
    name = "coordinator: a unique category already consumed by equipped armor rejects a bag ring",
    character = { classFile = "WARRIOR" },
    items = {
      head = Item.armor(301, "INVTYPE_HEAD", 1, "plate", 10, { uniqueKey = 88, uniqueLimit = 2 }),
      shoulder = Item.armor(302, "INVTYPE_SHOULDER", 3, "plate", 10, { uniqueKey = 88, uniqueLimit = 2 }),
      conflictingRing = Item.ring(201, 200, 200, { uniqueKey = 88, uniqueLimit = 2 }),
    },
    equipped = { [1] = "head", [3] = "shoulder" },
    bags = { [0] = { "conflictingRing" } },
    expect = { unchanged = { 1, 3, 11, 12 } },
  },

  -- 8.4 Pending item data
  {
    name = "coordinator: a pending bag item resolves and equips after a bounded retry",
    character = { classFile = "WARRIOR", specID = 71, specName = "Arms" },
    items = {
      pendingHead = Item.armor(101, "INVTYPE_HEAD", 1, "plate", 100, { loaded = false }),
    },
    equipped = {},
    bags = { [0] = { "pendingHead" } },
    expect = { final = { [1] = "pendingHead" }, pending = false },
  },

  -- 8.5 No legal upgrade
  {
    name = "coordinator: an already-optimal loadout is left unchanged despite higher scores on illegal items",
    character = { classFile = "WARRIOR", specID = 71, specName = "Arms" },
    items = {
      goodHead = Item.armor(101, "INVTYPE_HEAD", 1, "plate", 100),
      illegalHeadTrap = Item.armor(102, "INVTYPE_HEAD", 1, "mail", 999),
      good2h = Item.weapon(201, "INVTYPE_2HWEAPON", 120, 120),
      illegalWeaponTrap = Item.weapon(202, "INVTYPE_WEAPON", 999, 999),
    },
    equipped = { [1] = "goodHead", [16] = "good2h" },
    bags = { [0] = { "illegalHeadTrap", "illegalWeaponTrap" } },
    expect = { unchanged = { 1, 16, 17 }, pending = false },
  },
}
