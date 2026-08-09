-- tests/specs/coordinator_scenario_spec.lua
-- Runs the full coordinator scenarios (doc section 8) and the scoring
-- profile scenarios (doc section 9) through the black-box scenario harness.
-- Coordinator scenarios drive Gear:EquipBest end-to-end since the point is
-- verifying the real cross-planner orchestrator, not an individual planner.

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

Runner.RegisterAll(test, skip, root, A, loadScenarios("coordinator" .. sep .. "scenarios.lua"), "run")
Runner.RegisterAll(test, skip, root, A, loadScenarios("profiles" .. sep .. "scenarios.lua"), "plan")

return tests
