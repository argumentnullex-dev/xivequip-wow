-- tests/harness/scenario_runner.lua
-- The stable black-box boundary described in doc section 3:
--
--   ScenarioRunner.Plan(root, scenario) -> normalized result, no mutation
--   ScenarioRunner.Run(root, scenario)  -> normalized result, fully equips
--
-- `root` is the repo root path threaded through from tests/runner.lua's
-- vararg convention (every spec file already receives it as `local root =
-- ...`). Both hide planner module names, comparer/provider implementation,
-- candidate table shape, plan step shape, and exact move ordering -- callers
-- should only assert on the normalized result.

local ScenarioRunner = {}
local sep = package.config:sub(1, 1)

-- Every slot any planner ever touches. Used (not `pairs(world.equippedSlot)`)
-- so a slot that becomes empty -- and therefore has no table entry at all --
-- still shows up as changed, and so scenarios can assert a slot ends up
-- empty.
local ALL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

local function join(...)
  return table.concat({ ... }, sep)
end

local function loadHarnessModule(root, name)
  return dofile(join(root, "tests", "harness", name))
end

local function newAddon()
  return {
    Log = {
      Debug = function() end,
      Info = function() end,
      Warn = function() end,
      Error = function() end,
      Debugf = function() end,
    },
  }
end

local function recommendation(scenario)
  local scoring = scenario.profile and scenario.profile.scoring or {}
  return {
    providerID = scoring.provider or "test",
    profileID = scoring.profileID,
  }
end

local function snapshotItemIDs(equippedSlot)
  local snapshot = {}
  for _, slotID in ipairs(ALL_SLOTS) do
    local item = equippedSlot[slotID]
    snapshot[slotID] = item and item.itemID or nil
  end
  return snapshot
end

local function changedSlotsBetween(before, after)
  local changed = {}
  for _, slotID in ipairs(ALL_SLOTS) do
    if before[slotID] ~= after[slotID] then changed[#changed + 1] = slotID end
  end
  return changed
end

local function buildResult(world, before, scenario, pending)
  local after = snapshotItemIDs(world.equippedSlot)
  return {
    final = after,
    changedSlots = changedSlotsBetween(before, after),
    pending = pending == true,
    recommendation = recommendation(scenario),
    diagnostics = {},
  }
end

local function loadPlanner(root, addon, world)
  local Bootstrap = loadHarnessModule(root, "addon_bootstrap.lua")
  _G.XIVEquip_Settings = {}
  Bootstrap.LoadCore(root, addon)
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)
  Bootstrap.LoadPlanning(root, addon)
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local runtime = addon.Planning.Runtime.Live()
  runtime.ResolveWeights = function()
    return addon.XIVWeights.NewScale({ id = "scenario", source = { kind = "manual" }, weights = {} })
  end
  runtime.ScoreCandidate = function(candidate, _, slotID)
    local item = candidate and world.byID[candidate.itemID]
    return item and item.scores and item.scores[slotID] or 0
  end
  runtime.ScoreSource = function() return "Scenario" end
  return Bootstrap, runtime, resolved
end

-- Plan: builds production modules + fake world, calls Gear:PlanBest, and
-- reports what *would* change by running each returned pick through the
-- real Core.equipByBasics (backed by FakeWorld's cursor-mechanics globals --
-- PickupInventoryItem/EquipCursorItem/ClearCursor/PickupContainerItem --
-- not a mocked replacement for it) without invoking Gear:EquipBest. Cheaper
-- than Run() when a scenario doesn't need the async execution machinery,
-- and guaranteed to model final state identically to Run() since both call
-- the same production function.
function ScenarioRunner.Plan(root, scenario)
  local FakeWorld = loadHarnessModule(root, "fake_world.lua")

  local world = FakeWorld.Install(scenario)
  local before = snapshotItemIDs(world.equippedSlot)

  local addon = newAddon()
  local Bootstrap, runtime, resolved = loadPlanner(root, addon, world)
  Bootstrap.LoadInterface(root, addon)

  local _, pending, plan = addon.Gear:PlanBest({ planner = { runtime = runtime, resolved = resolved } })
  for _, pick in ipairs(plan or {}) do
    addon.Gear_Core.equipByBasics(pick)
  end

  return buildResult(world, before, scenario, pending)
end

-- Run: same as Plan, but actually drives Gear:EquipBest (autoSave=false) to
-- completion (settling fake timers), so the reported final state is what's
-- really equipped, including any pending-data retries and the real
-- Core.equipByBasics/_runEquipPlan execution path (locks, verify steps,
-- result counting) -- not bypassed.
function ScenarioRunner.Run(root, scenario)
  local FakeWorld = loadHarnessModule(root, "fake_world.lua")
  local FakeTimer = loadHarnessModule(root, "fake_timer.lua")

  local world = FakeWorld.Install(scenario)
  local before = snapshotItemIDs(world.equippedSlot)
  local settle = FakeTimer.Install()

  local addon = newAddon()
  local Bootstrap, runtime, resolved = loadPlanner(root, addon, world)

  -- Gear/Interface.lua captures these as upvalues at load time -- must be
  -- set before Bootstrap.LoadInterface runs. Core.equipByBasics is left as
  -- the real production function; FakeWorld already installed the cursor
  -- globals it calls.
  addon.L = {
    AddonPrefix = "XIVEquip: ",
    NoUpgrades = "No upgrades found.",
    CannotCombat = "Cannot equip while in combat.",
    ReplacedWith = "Replaced %s with %s.",
    SpecAuto_Saved = "Saved equipment set '%s'.",
  }
  addon.Settings = {
    GetMessage = function() return false end,
    GetAutomation = function() return false end,
  }

  Bootstrap.LoadInterface(root, addon)

  local originalPrint = _G.print
  _G.print = function() end
  local ok, err = pcall(function()
    addon.Gear:EquipBest({ autoSave = false, planner = { runtime = runtime, resolved = resolved } })
    settle()
  end)
  _G.print = originalPrint
  if not ok then error(err, 0) end

  local lastResult = addon.Gear:GetLastEquipResult()
  local pending = lastResult ~= nil and lastResult.pending_data == true

  return buildResult(world, before, scenario, pending)
end

-- Resolves a scenario.expect.final entry to the itemID it should compare
-- against: an item key, a raw itemID, or `false` meaning "this slot must end
-- up empty".
local function expectedItemID(scenario, keyOrID)
  if keyOrID == false then return false end
  if type(keyOrID) == "number" then return keyOrID end
  local item = scenario.items[keyOrID]
  return item and item.itemID or error("unknown scenario item key: " .. tostring(keyOrID), 2)
end

-- Shared verifier for the doc section 4 `expect` shape, so individual
-- scenario specs don't each hand-roll the same comparisons.
function ScenarioRunner.AssertFinal(A, result, scenario)
  local expect = scenario.expect or {}

  for slotID, keyOrID in pairs(expect.final or {}) do
    local expectedID = expectedItemID(scenario, keyOrID)
    if expectedID == false then
      A.falsy(result.final[slotID], scenario.name .. ": slot " .. tostring(slotID) .. " should be empty")
    else
      A.equal(result.final[slotID], expectedID, scenario.name .. ": slot " .. tostring(slotID))
    end
  end

  for _, slotID in ipairs(expect.unchanged or {}) do
    local changed = false
    for _, s in ipairs(result.changedSlots) do
      if s == slotID then changed = true end
    end
    A.falsy(changed, scenario.name .. ": slot " .. tostring(slotID) .. " should not have changed")
  end

  if expect.pending ~= nil then
    A.equal(result.pending, expect.pending, scenario.name .. ": pending")
  end
end

-- Registers a whole scenario list (as returned by a tests/scenarios/*.lua
-- data file) against a spec's `test(name, fn)`/`skip(name, reason)`
-- registrars. `mode` is "plan" or "run" and selects which stable boundary
-- drives each scenario by default; an individual scenario can override it
-- with its own `scenario.mode` field. Scenarios with `skip = true` are
-- registered as a genuine skip via the `skip` callback -- not run, not
-- counted as passed.
function ScenarioRunner.RegisterAll(test, skip, root, A, scenarioList, mode)
  for _, scenario in ipairs(scenarioList) do
    if scenario.skip then
      skip(scenario.name, scenario.skipReason)
    else
      test(scenario.name, function()
        local useMode = scenario.mode or mode
        local result = (useMode == "run") and ScenarioRunner.Run(root, scenario) or ScenarioRunner.Plan(root, scenario)
        ScenarioRunner.AssertFinal(A, result, scenario)
      end)
    end
  end
end

return ScenarioRunner
