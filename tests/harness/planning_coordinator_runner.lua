-- tests/harness/planning_coordinator_runner.lua
local Runner = {}
local sep = package.config:sub(1, 1)

local ALL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

local function join(...) return table.concat({ ... }, sep) end
local function loadHarnessModule(root, name) return dofile(join(root, "tests", "harness", name)) end

local function shallowCopy(source)
  local out = {}
  for k, v in pairs(source or {}) do out[k] = v end
  return out
end

local function itemIDsByKey(items)
  local ids = {}
  for key, def in pairs(items or {}) do ids[key] = def.itemID end
  return ids
end

local function buildScoreByID(items)
  local scores = {}
  for _, def in pairs(items or {}) do scores[def.itemID] = def.scores or {} end
  return scores
end

local function snapshot(world)
  local final = {}
  for _, slotID in ipairs(ALL_SLOTS) do
    local item = world.equippedSlot[slotID]
    final[slotID] = item and item.itemID or nil
  end
  return final
end

local function installScenarioWithStats(scenario)
  local copy = shallowCopy(scenario)
  local items = {}
  for key, def in pairs(scenario.items or {}) do
    local item = shallowCopy(def)
    item.stats = item.stats or { ITEM_MOD_STRENGTH_SHORT = 1 }
    items[key] = item
  end
  copy.items = items
  return copy
end

local function characterRuntime(addon, scenario, scale, scoreByID)
  local character = scenario.character or {}
  return {
    UnitClass = function() return character.className or character.classFile or "Player", character.classFile, 1 end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return character.specID, character.specName end,
    UnitLevel = function() return character.level or 80 end,
    IsDualWielding = function() return character.dualWielding == true end,
    ResolveWeights = function() return scale end,
    ScoreCandidate = function(candidate, _, slot)
      local scores = candidate and scoreByID[candidate.itemID]
      return scores and scores[slot] or 0
    end,
    ScoreSource = function() return "test scores" end,
  }
end

function Runner.Plan(root, scenario)
  local Bootstrap = loadHarnessModule(root, "addon_bootstrap.lua")
  local FakeWorld = loadHarnessModule(root, "fake_world.lua")

  local installScenario = installScenarioWithStats(scenario)
  local world = FakeWorld.Install(installScenario)
  local before = snapshot(world)

  local addon = {}
  Bootstrap.LoadCore(root, addon)
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)
  Bootstrap.LoadPlanning(root, addon)

  local scoreByID = buildScoreByID(scenario.items)
  local scale = addon.XIVWeights.NewScale({ weights = {} })
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local result = addon.Planning.Coordinator.Plan({
    resolved = resolved,
    runtime = characterRuntime(addon, scenario, scale, scoreByID),
  })

  local final = {}
  for _, slotID in ipairs(ALL_SLOTS) do
    local candidate = result.finalSlots[slotID]
    final[slotID] = candidate and candidate.itemID or nil
  end

  local changed = {}
  for _, slotID in ipairs(ALL_SLOTS) do
    if before[slotID] ~= final[slotID] then changed[#changed + 1] = slotID end
  end

  return {
    final = final,
    before = before,
    changedSlots = changed,
    pending = result.pending,
    recommendation = result,
    diagnostics = result.diagnostics,
    idsByKey = itemIDsByKey(scenario.items),
  }
end

function Runner.AssertFinal(A, result, scenario)
  local expect = scenario.expect or {}
  for slotID, key in pairs(expect.final or {}) do
    local expectedID = key == false and nil or result.idsByKey[key]
    A.equal(result.final[slotID], expectedID, scenario.name .. " slot " .. tostring(slotID))
  end
  for _, slotID in ipairs(expect.unchanged or {}) do
    A.equal(result.final[slotID], result.before[slotID], scenario.name .. " unchanged slot " .. tostring(slotID))
  end
  if expect.pending ~= nil then
    A.equal(result.pending, expect.pending, scenario.name .. " pending")
  end
end

function Runner.RegisterAll(test, skip, root, A, scenarios)
  for _, scenario in ipairs(scenarios or {}) do
    if scenario.skip then
      skip(scenario.name, scenario.reason)
    else
      test("planning coordinator: " .. scenario.name, function()
        local result = Runner.Plan(root, scenario)
        Runner.AssertFinal(A, result, scenario)
      end)
    end
  end
end

return Runner

