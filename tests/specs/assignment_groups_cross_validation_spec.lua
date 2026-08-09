-- tests/specs/assignment_groups_cross_validation_spec.lua
-- The strongest correctness proof for Phase 3: reuses the EXISTING
-- weapon-archetype and ring/trinket scenario fixtures (already asserted
-- against the old Weapons.lua/Jewelry.lua planners via ScenarioRunner in
-- weapon_archetype_scenario_spec.lua/paired_slot_scenario_spec.lua) and
-- re-runs each one through the NEW generic Assignments.Groups solver
-- instead, asserting the SAME scenario.expect.
--
-- Not every fixture can be reused: see
-- tests/harness/generic_assignment_runner.lua's header for how Phase 5's
-- slot-aware candidate policy context now lets this harness reproduce the
-- old fake cmp.ScoreItem(loc, slotID) shape. The one remaining paired-slot
-- skip below is not a scoring/eligibility gap -- it asserts production
-- equipment-slot transfer side effects that this direct-final-state harness
-- deliberately does not model.

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local ScenarioRunner = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "scenario_runner.lua")
local GenericAssignmentRunner = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "generic_assignment_runner.lua")

local function loadScenarios(rel)
  local chunk = assert(loadfile(root .. sep .. "tests" .. sep .. "scenarios" .. sep .. rel))
  return chunk(root)
end

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end
local function skip(name, reason)
  tests[#tests + 1] = { name = name, skip = true, reason = reason }
end

local NEEDS_EXECUTION_TRANSFER_MODEL = {
  ["ring pair: slot-sensitive equipped rings -- the better ring moves in, the displaced ring leaves"] = true,
}

local function registerGroup(scenarioList, groupKey)
  for _, scenario in ipairs(scenarioList) do
    if scenario.skip then
      -- Already a placeholder for unrelated reasons (e.g. policy metadata
      -- that doesn't exist yet) -- not this harness's concern.
      skip("[generic solver] " .. scenario.name, scenario.skipReason)
    elseif NEEDS_EXECUTION_TRANSFER_MODEL[scenario.name] then
      skip("[generic solver] " .. scenario.name,
        "asserts production equipment-slot transfer side effects; this generic solver harness applies final state directly")
    else
      test("[generic solver] " .. scenario.name, function()
        local result = GenericAssignmentRunner.Run(root, scenario, groupKey)
        ScenarioRunner.AssertFinal(A, result, scenario)
      end)
    end
  end
end

registerGroup(loadScenarios("weapons" .. sep .. "archetypes.lua"), "Weapons")
registerGroup(loadScenarios("paired_slots" .. sep .. "rings.lua"), "Rings")
registerGroup(loadScenarios("paired_slots" .. sep .. "trinkets.lua"), "Trinkets")

return tests
