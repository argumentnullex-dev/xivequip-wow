-- tests/specs/planning_coordinator_spec.lua
-- Curated shadow-planner coverage. These assert the new coordinator's
-- desired final loadout, not legacy one-step equip side effects.
local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Runner = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "planning_coordinator_runner.lua")
local Item = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "item_builder.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function armor(id, equipLoc, slotID, kind, score, extra)
  return Item.armor(id, equipLoc, slotID, kind, score, extra)
end
local function ring(id, s11, s12, extra) return Item.ring(id, s11, s12, extra) end
local function trinket(id, s13, s14, extra) return Item.trinket(id, s13, s14, extra) end
local function weapon(id, equipLoc, mh, oh, extra) return Item.weapon(id, equipLoc, mh, oh, extra) end
local function shield(id, score, extra) return weapon(id, "INVTYPE_SHIELD", 0, score, extra) end
local function holdable(id, score, extra) return weapon(id, "INVTYPE_HOLDABLE", 0, score, extra) end

local function loadAddonFile(rel, addon)
  local chunk = assert(loadfile(root .. sep .. "XIVEquip" .. sep .. rel))
  chunk("XIVEquip", addon)
end

local function directItemLevelPlan(scenario)
  local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")
  local FakeWorld = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "fake_world.lua")
  FakeWorld.Install(scenario)

  local addon = {}
  Bootstrap.LoadCore(root, addon)
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)
  Bootstrap.LoadPlanning(root, addon)

  local character = scenario.character or {}
  local scale = addon.XIVWeights.NewScale({ id = "test:ilvl", source = { kind = "ilvl" }, weights = {} })
  for _, policy in ipairs(scenario.policies or {}) do
    addon:RegisterPolicy(policy)
  end
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  return addon.Planning.Coordinator.Plan({
    resolved = resolved,
    runtime = {
      UnitClass = function() return character.classFile or "Player", character.classFile or "WARRIOR", 1 end,
      GetSpecialization = function() return 1 end,
      GetSpecializationInfo = function() return character.specID, character.specName end,
      UnitLevel = function() return character.level or 80 end,
      IsDualWielding = function() return character.dualWielding == true end,
      ResolveWeights = function() return scale end,
      ScoreCandidate = function(candidate) return tonumber(candidate and candidate.itemLevel) or 0 end,
      ScoreSource = function() return "Item Level" end,
    },
  })
end

local scenarios = {
  {
    name = "naked character fills ordinary, paired, and weapon slots",
    character = { classFile = "WARRIOR", specID = 71, specName = "Arms" },
    items = {
      head = armor(101, "INVTYPE_HEAD", 1, "plate", 100),
      mailTrap = armor(102, "INVTYPE_HEAD", 1, "mail", 999),
      neck = Item.jewelry(201, "INVTYPE_NECK", 2, 90, 2, 90),
      ringA = ring(301, 80, 70),
      ringB = ring(302, 60, 90),
      trinketA = trinket(401, 70, 60),
      trinketB = trinket(402, 50, 80),
      twoHand = weapon(501, "INVTYPE_2HWEAPON", 120, 120),
    },
    bags = { [0] = { "head", "mailTrap", "neck", "ringA", "ringB", "trinketA", "trinketB", "twoHand" } },
    expect = { final = { [1] = "head", [2] = "neck", [11] = "ringA", [12] = "ringB", [13] = "trinketA", [14] = "trinketB", [16] = "twoHand" }, unchanged = { 17 } },
  },
  {
    name = "partial upgrade changes only the slot with a better candidate",
    character = { classFile = "WARRIOR", specID = 71, specName = "Arms" },
    items = {
      oldA = trinket(601, 50, 10),
      oldB = trinket(602, 10, 80),
      upgradeA = trinket(603, 90, 5),
    },
    equipped = { [13] = "oldA", [14] = "oldB" },
    bags = { [0] = { "upgradeA" } },
    expect = { final = { [13] = "upgradeA" }, unchanged = { 14 } },
  },
  {
    name = "unique category is enforced across unrelated groups",
    character = { classFile = "WARRIOR", specID = 71 },
    items = {
      head = armor(701, "INVTYPE_HEAD", 1, "plate", 10, { uniqueKey = 88, uniqueLimit = 1 }),
      ringTrap = ring(702, 999, 999, { uniqueKey = 88, uniqueLimit = 1 }),
    },
    equipped = { [1] = "head" },
    bags = { [0] = { "ringTrap" } },
    expect = { unchanged = { 1, 11, 12 } },
  },
  {
    name = "pending data can coexist with a partial recommendation",
    character = { classFile = "WARRIOR", specID = 71 },
    items = {
      readyRing = ring(801, 100, 100),
      pendingHead = armor(802, "INVTYPE_HEAD", 1, "plate", 200, { loaded = false }),
    },
    bags = { [0] = { "readyRing", "pendingHead" } },
    expect = { final = { [11] = "readyRing" }, pending = true },
  },
  {
    name = "no legal upgrade leaves current loadout alone",
    character = { classFile = "WARRIOR", specID = 71 },
    items = {
      goodHead = armor(901, "INVTYPE_HEAD", 1, "plate", 100),
      mailTrap = armor(902, "INVTYPE_HEAD", 1, "mail", 999),
      good2h = weapon(903, "INVTYPE_2HWEAPON", 120, 120),
      oneHandTrap = weapon(904, "INVTYPE_WEAPON", 999, 999),
    },
    equipped = { [1] = "goodHead", [16] = "good2h" },
    bags = { [0] = { "mailTrap", "oneHandTrap" } },
    expect = { unchanged = { 1, 16, 17 }, pending = false },
  },
  {
    name = "weapon archetype Arms uses the best two-handed weapon",
    character = { classFile = "WARRIOR", specID = 71, specName = "Arms" },
    items = { twoHand = weapon(1001, "INVTYPE_2HWEAPON", 100, 100), oneHandTrap = weapon(1002, "INVTYPE_WEAPON", 999, 999) },
    bags = { [0] = { "twoHand", "oneHandTrap" } },
    expect = { final = { [16] = "twoHand" }, unchanged = { 17 } },
  },
  {
    name = "weapon archetype Rogue dual-wields two one-handers",
    character = { classFile = "ROGUE", specID = 260, specName = "Outlaw" },
    items = { mh = weapon(1101, "INVTYPE_WEAPON", 100, 40), oh = weapon(1102, "INVTYPE_WEAPON", 30, 90), twoHandTrap = weapon(1103, "INVTYPE_2HWEAPON", 999, 999) },
    bags = { [0] = { "mh", "oh", "twoHandTrap" } },
    expect = { final = { [16] = "mh", [17] = "oh" } },
  },
  {
    name = "weapon archetype Protection requires one-hand and shield",
    character = { classFile = "WARRIOR", specID = 73, specName = "Protection" },
    items = { mh = weapon(1201, "INVTYPE_WEAPON", 80, 0), shield = shield(1202, 70), twoHandTrap = weapon(1203, "INVTYPE_2HWEAPON", 999, 999) },
    bags = { [0] = { "mh", "shield", "twoHandTrap" } },
    expect = { final = { [16] = "mh", [17] = "shield" } },
  },
  {
    name = "weapon archetype Holy can use one-hand plus holdable",
    character = { classFile = "PALADIN", specID = 65, specName = "Holy" },
    items = { mh = weapon(1301, "INVTYPE_WEAPON", 80, 0), holdable = holdable(1302, 70), shield = shield(1303, 60) },
    bags = { [0] = { "mh", "holdable", "shield" } },
    expect = { final = { [16] = "mh", [17] = "holdable" } },
  },
  {
    name = "weapon archetype Elemental can choose a stronger two-hander",
    character = { classFile = "SHAMAN", specID = 262, specName = "Elemental" },
    items = { staff = weapon(1401, "INVTYPE_2HWEAPON", 150, 150), mh = weapon(1402, "INVTYPE_WEAPON", 70, 0), off = holdable(1403, 60) },
    bags = { [0] = { "staff", "mh", "off" } },
    expect = { final = { [16] = "staff" }, unchanged = { 17 } },
  },
  {
    name = "weapon archetype Mage can prefer one-hand plus holdable",
    character = { classFile = "MAGE", specID = 62, specName = "Arcane" },
    items = { staff = weapon(1501, "INVTYPE_2HWEAPON", 100, 100), mh = weapon(1502, "INVTYPE_WEAPON", 80, 0), off = holdable(1503, 60) },
    bags = { [0] = { "staff", "mh", "off" } },
    expect = { final = { [16] = "mh", [17] = "off" } },
  },
  {
    name = "weapon archetype Frost DK can prefer dual wield",
    character = { classFile = "DEATHKNIGHT", specID = 251, specName = "Frost" },
    items = { twoHand = weapon(1601, "INVTYPE_2HWEAPON", 140, 140), mh = weapon(1602, "INVTYPE_WEAPON", 90, 0), oh = weapon(1603, "INVTYPE_WEAPON", 0, 80) },
    bags = { [0] = { "twoHand", "mh", "oh" } },
    expect = { final = { [16] = "mh", [17] = "oh" } },
  },
  {
    name = "weapon archetype Fury supports Titan's Grip and mixed hands",
    character = { classFile = "WARRIOR", specID = 72, specName = "Fury" },
    items = { twoHand = weapon(1701, "INVTYPE_2HWEAPON", 130, 60), oneHand = weapon(1702, "INVTYPE_WEAPON", 40, 120), other2h = weapon(1703, "INVTYPE_2HWEAPON", 100, 80) },
    bags = { [0] = { "twoHand", "oneHand", "other2h" } },
    expect = { final = { [16] = "twoHand", [17] = "oneHand" } },
  },
  {
    name = "weapon archetype Brewmaster can use one-hand or two-hand without offhand",
    character = { classFile = "MONK", specID = 268, specName = "Brewmaster" },
    items = { oneHand = weapon(1801, "INVTYPE_WEAPON", 90, 0), twoHand = weapon(1802, "INVTYPE_2HWEAPON", 120, 120), offTrap = holdable(1803, 999) },
    bags = { [0] = { "oneHand", "twoHand", "offTrap" } },
    expect = { final = { [16] = "twoHand" }, unchanged = { 17 } },
  },
}

Runner.RegisterAll(test, function() end, root, A, scenarios)

test("planning coordinator: item-level fallback scores a two-hander as filling both hands", function()
  local result = directItemLevelPlan({
    character = { classFile = "SHAMAN", specID = 262, specName = "Elemental" },
    items = {
      staff = weapon(1901, "INVTYPE_2HWEAPON", 0, 0, { itemLevel = 700 }),
      main = weapon(1902, "INVTYPE_WEAPON", 0, 0, { itemLevel = 600 }),
      off = holdable(1903, 0, { itemLevel = 600 }),
    },
    bags = { [0] = { "staff", "main", "off" } },
  })

  A.equal(result.finalSlots[16] and result.finalSlots[16].itemID, 1901)
  A.equal(result.finalSlots[17], nil)
end)

test("planning coordinator: item-level weapon normalization preserves candidate policy score adjustments", function()
  local result = directItemLevelPlan({
    character = { classFile = "SHAMAN", specID = 262, specName = "Elemental" },
    items = {
      staff = weapon(1911, "INVTYPE_2HWEAPON", 0, 0, { itemLevel = 700 }),
      main = weapon(1912, "INVTYPE_WEAPON", 0, 0, { itemLevel = 600 }),
      off = holdable(1913, 0, { itemLevel = 600 }),
    },
    bags = { [0] = { "staff", "main", "off" } },
    policies = {
      {
        id = "Test.weapon_adjustment",
        phase = "candidate",
        groups = { "weapons" },
        apply = function(candidate)
          if candidate and candidate.itemID == 1911 then return { scoreAdjustment = 25 } end
        end,
      },
    },
  })
  local weaponAssignment = result.selectedAssignments.weapons

  A.equal(result.finalSlots[16] and result.finalSlots[16].itemID, 1911)
  A.equal(weaponAssignment.baseScore, 1400)
  A.equal(weaponAssignment.scoreAdjustment, 25)
  A.equal(weaponAssignment.score, 1425)
  A.equal(weaponAssignment.scores.mh, 1425)
  A.equal(weaponAssignment.scores.oh, 0)
end)

test("planning coordinator: current 2H item-level baseline uses the same weapon assignment semantics", function()
  local result = directItemLevelPlan({
    character = { classFile = "SHAMAN", specID = 262, specName = "Elemental" },
    items = {
      current = weapon(1921, "INVTYPE_2HWEAPON", 0, 0, { itemLevel = 600 }),
      upgrade = weapon(1922, "INVTYPE_2HWEAPON", 0, 0, { itemLevel = 610 }),
    },
    equipped = { [16] = "current" },
    bags = { [0] = { "upgrade" } },
  })

  A.equal(result.currentSlotScores[16], 1200)
  A.equal(result.finalSlotScores[16], 1220)
  A.equal(result.finalSlotScores[16] - result.currentSlotScores[16], 20)
  A.equal(result.currentGroupScores.weapons, 1200)
  A.equal(result.finalGroupScores.weapons, 1220)
end)

test("planning coordinator: current slot scores include candidate policy adjustments", function()
  local result = directItemLevelPlan({
    character = { classFile = "SHAMAN", specID = 262, specName = "Elemental" },
    items = {
      current = weapon(1931, "INVTYPE_2HWEAPON", 0, 0, { itemLevel = 600 }),
      upgrade = weapon(1932, "INVTYPE_2HWEAPON", 0, 0, { itemLevel = 610 }),
    },
    equipped = { [16] = "current" },
    bags = { [0] = { "upgrade" } },
    policies = {
      {
        id = "Test.weapon_adjustment_current_and_new",
        phase = "candidate",
        groups = { "weapons" },
        apply = function(candidate)
          if candidate and (candidate.itemID == 1931 or candidate.itemID == 1932) then
            return { scoreAdjustment = 25 }
          end
        end,
      },
    },
  })

  A.equal(result.currentSlotScores[16], 1225)
  A.equal(result.finalSlotScores[16], 1245)
  A.equal(result.finalSlotScores[16] - result.currentSlotScores[16], 20)
end)

test("planning coordinator and plan builder clear a stale Titan's Grip offhand after spec change", function()
  local result = directItemLevelPlan({
    character = { classFile = "WARRIOR", specID = 71, specName = "Arms" },
    items = {
      current = weapon(1941, "INVTYPE_2HWEAPON", 0, 0, { itemLevel = 600 }),
      staleOffhand = weapon(1942, "INVTYPE_2HWEAPON", 0, 0, { itemLevel = 600 }),
    },
    equipped = { [16] = "current", [17] = "staleOffhand" },
  })
  local addon = { Gear_Core = { SLOT_LABEL = { [16] = "Main Hand", [17] = "Off Hand" } } }
  loadAddonFile("Planning" .. sep .. "PlanBuilder.lua", addon)

  local _, _, plan = addon.Planning.PlanBuilder.Build(result)

  A.equal(result.finalSlots[16] and result.finalSlots[16].itemID, 1941)
  A.equal(result.finalSlots[17], nil)
  A.equal(#plan, 1)
  A.equal(plan[1].action, "unequip")
  A.equal(plan[1].targetSlot, 17)
end)

test("planning coordinator closes live runtime when planning throws", function()
  local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")
  local addon = {
    L = { AddonPrefix = "XIVEquip: " },
    Log = {
      Debug = function() end,
      Info = function() end,
      Warn = function() end,
      Error = function() end,
    },
  }

  _G.XIVEquip_Settings = { SelectedComparer = "ilvl" }
  loadAddonFile("Global" .. sep .. "Settings.lua", addon)
  loadAddonFile("Core" .. sep .. "ComparerBootstrapper.lua", addon)
  Bootstrap.LoadCore(root, addon)
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)
  Bootstrap.LoadPlanning(root, addon)

  addon.Comparers:RegisterComparer("ilvl", {
    Label = "Item Level",
    IsAvailable = function() return true end,
  })

  local passStarts, passEnds = 0, 0
  local startPass = addon.Comparers.StartPass
  local endPass = addon.Comparers.EndPass
  addon.Comparers.StartPass = function(self)
    passStarts = passStarts + 1
    return startPass(self)
  end
  addon.Comparers.EndPass = function(self)
    passEnds = passEnds + 1
    return endPass(self)
  end

  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  addon.Evaluation.CandidateCollector.Collect = function()
    error("collector exploded")
  end

  local ok, err = pcall(function()
    addon.Planning.Coordinator.Plan({ resolved = resolved })
  end)

  A.equal(ok, false)
  A.truthy(tostring(err):find("collector exploded", 1, true), "original native planner error should be preserved")
  A.equal(passStarts, 1)
  A.equal(passEnds, 1)
end)

return tests
