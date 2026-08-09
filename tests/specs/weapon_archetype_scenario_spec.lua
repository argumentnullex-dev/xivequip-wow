-- tests/specs/weapon_archetype_scenario_spec.lua
-- Runs the weapon archetype matrix (doc section 6) plus its skipped
-- weapon-policy-override placeholders through the black-box scenario
-- harness. Layer B (weapons_spec.lua) stays in place and keeps testing the
-- same behavior at the planner/unit level -- this is the whole-addon,
-- final-state view (doc migration Step 3).

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Runner = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "scenario_runner.lua")

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

-- "run" (not "plan") so these actually drive Gear:EquipBest end to end,
-- including displacement/offhand-clearing side effects.
Runner.RegisterAll(test, skip, root, A, loadScenarios("weapons" .. sep .. "archetypes.lua"), "run")
Runner.RegisterAll(test, skip, root, A, loadScenarios("policies" .. sep .. "weapon_overrides.lua"), "run")

return tests
