-- tests/specs/assignment_singleton_spec.lua
local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function newAddon()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  return addon
end

local function candidate(id, score, uniqueKey, uniqueLimit)
  return {
    itemID = id,
    physicalID = "item:" .. tostring(id),
    testScore = score,
    uniqueness = { key = uniqueKey, limit = uniqueLimit },
  }
end

local function context()
  return { policies = { candidate = {}, assignment = {}, loadout = {}, preference = {} } }
end

local function score(c) return c and c.testScore or 0 end

test("frontier represents a single available item when the slot is empty", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()
  local helm = candidate(7301, 25)

  local frontier = addon.Assignments.Singleton.Frontier({
    groupId = "head",
    slot = 1,
    candidates = { helm },
    current = nil,
    context = context(),
    loadoutState = state,
    allSlots = { 1 },
    score = score,
  })

  local sawHelm = false
  for _, assignment in ipairs(frontier) do
    if assignment.picks.slot == helm then sawHelm = true end
  end
  A.truthy(sawHelm, "the filled assignment should be present")
end)

test("frontier keeps the current item as a representable option", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()
  local current = candidate(7302, 30)
  local weaker = candidate(7303, 10)
  state:SeedFromEquipped({ [1] = current })

  local frontier = addon.Assignments.Singleton.Frontier({
    groupId = "head",
    slot = 1,
    candidates = { weaker },
    current = current,
    context = context(),
    loadoutState = state,
    allSlots = { 1 },
    score = score,
  })

  local sawCurrent = false
  for _, assignment in ipairs(frontier) do
    if assignment.picks.slot == current then sawCurrent = true end
  end
  A.truthy(sawCurrent, "the optimizer must be able to keep exactly what is equipped")
end)

test("frontier uses the whole optimized slot set for uniqueness checks", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()
  local existingOtherSlot = candidate(7304, 1, "category:88", 1)
  local replacement = candidate(7305, 50, "category:88", 1)
  state:SeedFromEquipped({ [2] = existingOtherSlot })

  local frontier = addon.Assignments.Singleton.Frontier({
    groupId = "head",
    slot = 1,
    candidates = { replacement },
    current = nil,
    context = context(),
    loadoutState = state,
    allSlots = { 1, 2 },
    score = score,
  })

  local sawReplacement = false
  for _, assignment in ipairs(frontier) do
    if assignment.picks.slot == replacement then sawReplacement = true end
  end
  A.truthy(sawReplacement, "slot 2's current unique item is being replaced within the same whole-loadout pass")
end)

return tests

