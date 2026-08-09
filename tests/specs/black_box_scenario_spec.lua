-- tests/specs/black_box_scenario_spec.lua
-- Proves the black-box scenario harness (doc migration Step 1): one simple
-- armor, ring, trinket, and weapon scenario, each driven through the stable
-- ScenarioRunner.Plan/Run boundary rather than calling planner modules
-- directly. See tests/harness/ for the shared fake-WoW mocking this reuses.

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Runner = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "scenario_runner.lua")
local Item = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "item_builder.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

test("armor: best legal-type head item wins over a higher-scoring wrong-armor-type trap (Run)", function()
  local scenario = {
    name = "armor naked head slot",
    character = { classFile = "WARRIOR" }, -- plate proficiency
    items = {
      plateHead = Item.armor(1001, "INVTYPE_HEAD", 1, "plate", 100),
      mailHeadTrap = Item.armor(1002, "INVTYPE_HEAD", 1, "mail", 200),
    },
    equipped = {},
    bags = { [0] = { "plateHead", "mailHeadTrap" } },
    expect = { final = { [1] = "plateHead" } },
  }

  local result = Runner.Run(root, scenario)
  Runner.AssertFinal(A, result, scenario)
end)

test("ring pair: bag upgrade replaces the weaker equipped ring, stronger ring is kept (Plan)", function()
  local scenario = {
    name = "ring pair upgrade",
    character = { classFile = "WARRIOR" },
    items = {
      strongRing = Item.ring(2001, 100, 100),
      weakRing = Item.ring(2002, 80, 80),
      upgradeRing = Item.ring(2003, 110, 110),
    },
    equipped = { [11] = "strongRing", [12] = "weakRing" },
    bags = { [0] = { "upgradeRing" } },
    expect = { final = { [12] = "upgradeRing" }, unchanged = { 11 } },
  }

  local result = Runner.Plan(root, scenario)
  Runner.AssertFinal(A, result, scenario)
end)

test("trinket pair: bag upgrade replaces the weaker equipped trinket, stronger trinket is kept (Run)", function()
  local scenario = {
    name = "trinket pair upgrade",
    character = { classFile = "WARRIOR" },
    items = {
      strongTrinket = Item.trinket(3001, 100, 100),
      weakTrinket = Item.trinket(3002, 80, 80),
      upgradeTrinket = Item.trinket(3003, 110, 110),
    },
    equipped = { [13] = "strongTrinket", [14] = "weakTrinket" },
    bags = { [0] = { "upgradeTrinket" } },
    expect = { final = { [14] = "upgradeTrinket" }, unchanged = { 13 } },
  }

  local result = Runner.Run(root, scenario)
  Runner.AssertFinal(A, result, scenario)
end)

test("weapon: Fury Titan's Grip picks the two best distinct 2H weapons from naked (Plan)", function()
  local scenario = {
    name = "Fury naked Titan's Grip",
    character = { classFile = "WARRIOR", specID = 72, specName = "Fury" },
    items = {
      weakAxe = Item.weapon(4001, "INVTYPE_2HWEAPON", 80, 80),
      strongAxe = Item.weapon(4002, "INVTYPE_2HWEAPON", 120, 120),
    },
    equipped = {},
    bags = { [0] = { "weakAxe", "strongAxe" } },
    expect = { final = { [16] = "strongAxe", [17] = "weakAxe" } },
  }

  local result = Runner.Plan(root, scenario)
  Runner.AssertFinal(A, result, scenario)
end)

return tests
