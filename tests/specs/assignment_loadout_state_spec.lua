-- tests/specs/assignment_loadout_state_spec.lua
-- Assignments/LoadoutState.lua: ports Core.EnsurePlanContext/
-- Core.UniqueAssignmentOK/Core.MarkPlannedEquip's exact accounting rules
-- (Core/GearCore.lua:60-164) onto normalized candidates.

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function newAddon()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  return addon
end

local function candidate(key, limit)
  return { uniqueness = { key = key, limit = limit } }
end

test("a fresh state has no seeded uniqueness", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()

  A.truthy(state:CheckAssignment({ candidate("item:1", 1) }, { 11 }))
end)

test("an item-specific unique (limit 1) cannot be added twice", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()

  local ok = state:CheckAssignment({ candidate("item:1", 1), candidate("item:1", 1) }, { 11, 12 })

  A.falsy(ok, "two copies of a limit-1 unique item should not both fit")
end)

test("a shared category with limit 2 allows two additions", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()

  local ok = state:CheckAssignment({ candidate("category:5", 2), candidate("category:5", 2) }, { 11, 12 })

  A.truthy(ok, "a limit-2 shared category should allow two members")
end)

test("SeedFromEquipped seeds counts so a new addition sharing the equipped key is rejected", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()
  state:SeedFromEquipped({ [11] = candidate("item:1", 1) })

  local ok = state:CheckAssignment({ candidate("item:1", 1) }, { 12 })

  A.falsy(ok, "the seeded equipped item already occupies the limit-1 slot")
end)

test("CheckAssignment provisionally removes the occupant of a slot being replaced", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()
  state:SeedFromEquipped({ [11] = candidate("item:1", 1) })

  -- Replacing slot 11 itself with the same uniqueKey should be fine --
  -- the slot's own current occupant is subtracted before re-adding.
  local ok = state:CheckAssignment({ candidate("item:1", 1) }, { 11 })

  A.truthy(ok, "replacing a slot with its own uniqueness key should not self-conflict")
end)

test("Commit updates counts so a later check reflects the new occupant", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()
  state:SeedFromEquipped({ [11] = candidate("item:1", 1) })

  state:Commit(11, candidate("item:2", 1))

  A.truthy(state:CheckAssignment({ candidate("item:1", 1) }, { 12 }),
    "item:1 should no longer be occupying anything after slot 11 was committed to item:2")
  A.falsy(state:CheckAssignment({ candidate("item:2", 1) }, { 12 }),
    "item:2 now occupies slot 11, so adding another copy elsewhere should fail")
end)

test("Commit with a nil candidate clears the slot's uniqueness contribution", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()
  state:SeedFromEquipped({ [11] = candidate("item:1", 1) })

  state:Commit(11, nil)

  A.truthy(state:CheckAssignment({ candidate("item:1", 1) }, { 12 }), "clearing the slot should free up its uniqueness key")
end)

test("a removed slot's tighter limit no longer constrains new items sharing its key elsewhere", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()
  -- Slot 13 currently holds a limit-1 copy of key X.
  state:SeedFromEquipped({ [13] = candidate("X", 1) })

  -- The whole-loadout trial removes slot 13 (its old limit-1 item is
  -- gone) and proposes two DIFFERENT limit-2 items sharing key X, one of
  -- which lands in a completely different slot (11). Once the limit-1
  -- occupant is actually leaving, the effective limit for this trial is
  -- 2, not 1 -- count 2 against limit 2 is legal. An aggregate "minimum
  -- limit ever seen for X" that never forgets the removed item's limit-1
  -- would wrongly reject this.
  local ok = state:CheckAssignment({ candidate("X", 2), candidate("X", 2) }, { 13, 11 })

  A.truthy(ok, "removing the limit-1 occupant must free the key up to the new items' own (laxer) limit")
end)

test("a key's limit still comes from slots that are NOT being removed", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()
  -- Slot 11 holds a limit-2 copy of X and stays equipped (not removed);
  -- slot 13's limit-1 copy of X is being removed.
  state:SeedFromEquipped({ [11] = candidate("X", 2), [13] = candidate("X", 1) })

  local ok = state:CheckAssignment({ candidate("X", 2) }, { 13 })

  A.truthy(ok, "slot 11's own limit-2 X plus one new limit-2 X is legal once slot 13's limit-1 X is gone")
end)

test("a candidate with no uniqueness key never conflicts with anything", function()
  local addon = newAddon()
  local state = addon.Assignments.LoadoutState.New()

  local ok = state:CheckAssignment({ { uniqueness = {} }, { uniqueness = {} } }, { 11, 12 })

  A.truthy(ok, "items with no uniqueness key should never be limited")
end)

return tests
