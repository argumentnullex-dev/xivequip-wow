-- tests/specs/paired_slot_scenario_spec.lua
-- Runs the ring and trinket pair matrix (doc section 7), plus the trinket
-- policy placeholders, through the black-box scenario harness. Layer B
-- (paired_slots_spec.lua) stays in place for exact-plan-shape/move-order
-- coverage (doc migration Step 2).

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
-- including displacement side effects between paired slots.
Runner.RegisterAll(test, skip, root, A, loadScenarios("paired_slots" .. sep .. "rings.lua"), "run")
Runner.RegisterAll(test, skip, root, A, loadScenarios("paired_slots" .. sep .. "trinkets.lua"), "run")
Runner.RegisterAll(test, skip, root, A, loadScenarios("policies" .. sep .. "trinket_policy.lua"), "run")

return tests
