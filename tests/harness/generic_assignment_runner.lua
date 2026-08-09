-- tests/harness/generic_assignment_runner.lua
-- Cross-validates Assignments/Groups.* (Phase 3's new generic solver)
-- against the SAME scenario fixture data already used to black-box test
-- the old planners (tests/scenarios/weapons/archetypes.lua,
-- tests/scenarios/paired_slots/rings.lua/trinkets.lua) -- re-running each
-- fixture through the new solver instead of Gear:PlanBest and comparing
-- against the same scenario.expect those fixtures already assert against
-- the old planner via ScenarioRunner.
--
-- IMPORTANT LIMITATION -- read before adding new cross-validation cases:
-- the old planners' fake cmp.ScoreItem(loc, slotID) can return a
-- DIFFERENT score for the same item depending on which slot is asked
-- about. tests/harness/item_builder.lua's Item.jewelry deliberately
-- exploits this (see rings.lua's header comment) so a black-box final-state
-- assertion has one unambiguous right answer. Phase 5 candidate policies
-- now receive the target slot, so this runner translates the old fake
-- comparer shape into two pieces:
--   1. a synthetic baseline Strength stat, and
--   2. a test-only candidate policy that adjusts score to the requested
--      slot's fixture score.
-- This keeps cross-validation faithful without making production scoring
-- itself role-asymmetric.
local GenericAssignmentRunner = {}
local sep = package.config:sub(1, 1)

local function join(...) return table.concat({ ... }, sep) end
local function loadHarnessModule(root, name) return dofile(join(root, "tests", "harness", name)) end

local ALL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

local GROUPS = {
  Weapons = { key = "Weapons", roles = { "mh", "oh" }, slots = { 16, 17 } },
  Rings = { key = "Rings", roles = { "first", "second" }, slots = { 11, 12 } },
  Trinkets = { key = "Trinkets", roles = { "first", "second" }, slots = { 13, 14 } },
}
GenericAssignmentRunner.GROUPS = GROUPS

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

-- Run(root, scenario, groupKey) -> result
-- groupKey: one of "Weapons", "Rings", "Trinkets" (see GROUPS above).
-- Result shape matches ScenarioRunner's exactly, so
-- ScenarioRunner.AssertFinal works unchanged against it.
function GenericAssignmentRunner.Run(root, scenario, groupKey)
  local groupInfo = assert(GROUPS[groupKey], "unknown group '" .. tostring(groupKey) .. "'")
  local slotA, slotB = groupInfo.slots[1], groupInfo.slots[2]
  local roleA, roleB = groupInfo.roles[1], groupInfo.roles[2]

  local Bootstrap = loadHarnessModule(root, "addon_bootstrap.lua")
  local FakeWorld = loadHarnessModule(root, "fake_world.lua")

  -- Inject the synthetic single-stat translation (see header) without
  -- mutating the original fixture table, which other specs reuse.
  local items = {}
  for key, def in pairs(scenario.items or {}) do
    local copy = {}
    for k, v in pairs(def) do copy[k] = v end
    local scores = def.scores or {}
    local a, b = scores[slotA] or 0, scores[slotB] or 0
    local effective = a
    if a == 0 then effective = b end
    copy.stats = { ITEM_MOD_STRENGTH_SHORT = effective }
    items[key] = copy
  end
  local installScenario = {}
  for k, v in pairs(scenario) do installScenario[k] = v end
  installScenario.items = items

  local world = FakeWorld.Install(installScenario)
  local before = snapshotItemIDs(world.equippedSlot)

  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)

  local scale = addon.XIVWeights.NewScale({
    weights = addon.XIVWeights.Normalizer.Normalize({ strength = 1 }),
  })
  if groupKey == "Rings" or groupKey == "Trinkets" then
    addon:RegisterPolicy({
      id = "Tests.jewelry_ilvl_floor",
      phase = "candidate",
      groups = { groupInfo.key:lower() },
      apply = function(candidate, _, policyContext)
        local current = policyContext and policyContext.currentCandidate
        if not candidate or not current then return nil end
        local source = candidate.source or {}
        if source.kind ~= "bag" then return nil end

        local ilvl = candidate.itemLevel
        if type(ilvl) == "number" and (ilvl == 1 or ilvl >= ((current.itemLevel or 0) - 80)) then
          return nil
        end
        return { allow = false, reason = "below-current-jewelry-ilvl-floor" }
      end,
    })
  end
  addon:RegisterPolicy({
    id = "Tests.slot_score_adjustment",
    phase = "candidate",
    groups = { groupInfo.key:lower() },
    apply = function(candidate, _, policyContext)
      local slot = policyContext and policyContext.slot
      local scores = candidate and candidate.source and candidate.source.scores
      local slotScore = scores and scores[slot]
      if type(slotScore) ~= "number" then return nil end
      local base = candidate.stats and candidate.stats.strength or 0
      return { scoreAdjustment = slotScore - base }
    end,
  })
  local character = scenario.character or {}
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local runtime = {
    UnitClass = function() return character.className or character.classFile or "Player", character.classFile, 1 end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return character.specID, character.specName end,
    UnitLevel = function() return character.level or 80 end,
    IsDualWielding = function() return character.dualWielding == true end,
    ResolveWeights = function() return scale end,
  }
  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, runtime)

  local function candidateFromRecord(record, source)
    if not record then return nil end
    source.scores = record.scores
    return addon.Evaluation.CandidateNormalizer.FromLink(record.link, source)
  end

  local equippedA = world.equippedSlot[slotA]
  local equippedB = world.equippedSlot[slotB]
  local currentA = candidateFromRecord(equippedA, { kind = "equipped", slot = slotA, guid = equippedA and equippedA.guid })
  local currentB = candidateFromRecord(equippedB, { kind = "equipped", slot = slotB, guid = equippedB and equippedB.guid })

  local candidates = {}
  if currentA then candidates[#candidates + 1] = currentA end
  if currentB then candidates[#candidates + 1] = currentB end
  for bag, bagSlots in pairs(world.bagSlots) do
    for slotIndex, record in pairs(bagSlots) do
      if record then
        candidates[#candidates + 1] = candidateFromRecord(record, {
          kind = "bag", bag = bag, slot = slotIndex, guid = record.guid,
        })
      end
    end
  end

  local loadoutState = addon.Assignments.LoadoutState.New()
  loadoutState:SeedFromEquipped({ [slotA] = currentA, [slotB] = currentB })

  local best
  if groupKey == "Weapons" then
    best = addon.Assignments.Groups.Weapons.Solve(candidates, context, loadoutState, currentA, currentB)
  else
    best = addon.Assignments.Groups[groupKey].Solve(candidates, context, loadoutState, currentA, currentB)
  end

  -- Apply the winning assignment directly to world.equippedSlot -- this
  -- harness only needs final-state comparison, not real equip mechanics
  -- (doc section 11: don't assert move order at this layer). A nil `best`
  -- means "nothing beats what's currently equipped" -- leave the world
  -- untouched in that case, not cleared (Groups.*.Solve already returns
  -- nil for exactly this "no-op" case, same as the old planners returning
  -- an empty plan).
  if best then
    local pickA, pickB = best.picks[roleA], best.picks[roleB]
    if pickA then world.equippedSlot[slotA] = { itemID = pickA.itemID } else world.equippedSlot[slotA] = nil end
    if pickB then world.equippedSlot[slotB] = { itemID = pickB.itemID } else world.equippedSlot[slotB] = nil end
  end

  local after = snapshotItemIDs(world.equippedSlot)
  return {
    final = after,
    changedSlots = changedSlotsBetween(before, after),
    pending = false,
    recommendation = { providerID = "test" },
    diagnostics = {},
  }
end

return GenericAssignmentRunner
