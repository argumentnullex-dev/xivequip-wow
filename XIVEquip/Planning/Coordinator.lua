-- Planning/Coordinator.lua
-- RecommendationResult coordinator for the 2.0 evaluation pipeline.
-- It does not equip anything; it builds frontiers and asks the whole-loadout
-- optimizer for a desired final slot assignment.
local addonName, XIVEquip = ...
XIVEquip.Planning = XIVEquip.Planning or {}
local Planning = XIVEquip.Planning

local Coordinator = {}
Planning.Coordinator = Coordinator

local SINGLETON_SLOTS = {
  { id = "head", slot = 1 },
  { id = "neck", slot = 2 },
  { id = "shoulder", slot = 3 },
  { id = "chest", slot = 5 },
  { id = "waist", slot = 6 },
  { id = "legs", slot = 7 },
  { id = "feet", slot = 8 },
  { id = "wrist", slot = 9 },
  { id = "hands", slot = 10 },
  { id = "back", slot = 15 },
}

local OPTIMIZED_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

local WEAPON_EQUIPLOCS = {
  INVTYPE_WEAPON = true,
  INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_2HWEAPON = true,
  INVTYPE_RANGED = true,
  INVTYPE_RANGEDRIGHT = true,
  INVTYPE_THROWN = true,
  INVTYPE_HOLDABLE = true,
  INVTYPE_SHIELD = true,
}

local function copyArray(source)
  local out = {}
  for _, value in ipairs(source or {}) do out[#out + 1] = value end
  return out
end

local function appendIfMissing(list, candidate)
  if not candidate then return end
  for _, existing in ipairs(list) do
    if existing == candidate then return end
  end
  list[#list + 1] = candidate
end

local function candidateEquipLoc(candidate)
  return candidate and candidate.equip and candidate.equip.equipLoc
end

local function matchesSlot(candidate, slotID)
  local equipLoc = candidateEquipLoc(candidate)
  local Core = XIVEquip.Gear_Core
  if Core and type(Core.equipLocMatchesSlot) == "function" then
    return Core.equipLocMatchesSlot(equipLoc, slotID)
  end
  local allowed = XIVEquip.Const and XIVEquip.Const.SLOT_EQUIPLOCS and XIVEquip.Const.SLOT_EQUIPLOCS[slotID]
  return allowed and allowed[equipLoc] == true
end

local function candidatesForSlot(candidates, slotID, current)
  local out = {}
  for _, candidate in ipairs(candidates or {}) do
    if candidate == current or matchesSlot(candidate, slotID) then out[#out + 1] = candidate end
  end
  appendIfMissing(out, current)
  return out
end

local function candidatesForEquipLoc(candidates, equipLoc, currentA, currentB)
  local out = {}
  for _, candidate in ipairs(candidates or {}) do
    if candidate == currentA or candidate == currentB or candidateEquipLoc(candidate) == equipLoc then
      out[#out + 1] = candidate
    end
  end
  appendIfMissing(out, currentA)
  appendIfMissing(out, currentB)
  return out
end

local function weaponCandidates(candidates, currentMH, currentOH)
  local out = {}
  for _, candidate in ipairs(candidates or {}) do
    if candidate == currentMH or candidate == currentOH or WEAPON_EQUIPLOCS[candidateEquipLoc(candidate)] then
      out[#out + 1] = candidate
    end
  end
  appendIfMissing(out, currentMH)
  appendIfMissing(out, currentOH)
  return out
end

local function buildContext(opts)
  if opts.context then return opts.context end
  local resolved = opts.resolved or (XIVEquip.Policies and XIVEquip.Policies.Resolved)
  assert(resolved, "Planning.Coordinator requires resolved policies")
  local runtime = opts.runtime or Planning.Runtime.Live()
  return XIVEquip.Evaluation.ContextBuilder.BuildContext(resolved, runtime)
end

local function groupScoreFn(opts, runtime)
  if opts.score then return opts.score end
  if runtime and type(runtime.ScoreCandidate) == "function" then
    return function(candidate, context, slot)
      return runtime.ScoreCandidate(candidate, context, slot)
    end
  end
  return nil
end

local function singletonGroup(spec)
  local frontier = XIVEquip.Assignments.Singleton.Frontier({
    groupId = spec.id,
    slot = spec.slot,
    candidates = candidatesForSlot(spec.collection.candidates, spec.slot, spec.collection.equippedBySlot[spec.slot]),
    current = spec.collection.equippedBySlot[spec.slot],
    context = spec.context,
    loadoutState = spec.loadoutState,
    allSlots = spec.allSlots,
    score = spec.score,
  })
  return { id = spec.id, slots = { spec.slot }, frontier = frontier, slot = spec.slot, kind = "singleton" }
end

local function buildGroups(collection, context, loadoutState, allSlots, score, perf)
  local groups = {}
  local singletonToken = perf and perf:Start("  singleton total")
  for _, def in ipairs(SINGLETON_SLOTS) do
    groups[#groups + 1] = singletonGroup({
      id = def.id,
      slot = def.slot,
      collection = collection,
      context = context,
      loadoutState = loadoutState,
      allSlots = allSlots,
      score = score,
    })
  end
  if perf then perf:Stop(singletonToken) end

  local ringCandidates = candidatesForEquipLoc(collection.candidates, "INVTYPE_FINGER", collection.equippedBySlot[11], collection.equippedBySlot[12])
  if perf then perf:Set("rings.candidates", #ringCandidates) end
  local ringToken = perf and perf:Start("  rings")
  groups[#groups + 1] = {
    id = "rings",
    kind = "paired",
    roles = { first = 11, second = 12 },
    slots = { 11, 12 },
    frontier = XIVEquip.Assignments.Groups.Rings.Frontier(
      ringCandidates,
      context, loadoutState, collection.equippedBySlot[11], collection.equippedBySlot[12], allSlots, score, perf),
  }
  if perf then
    perf:Stop(ringToken)
    perf:Set("rings.final_frontier_size", #(groups[#groups].frontier or {}))
  end

  local trinketCandidates = candidatesForEquipLoc(collection.candidates, "INVTYPE_TRINKET", collection.equippedBySlot[13], collection.equippedBySlot[14])
  if perf then perf:Set("trinkets.candidates", #trinketCandidates) end
  local trinketToken = perf and perf:Start("  trinkets")
  groups[#groups + 1] = {
    id = "trinkets",
    kind = "paired",
    roles = { first = 13, second = 14 },
    slots = { 13, 14 },
    frontier = XIVEquip.Assignments.Groups.Trinkets.Frontier(
      trinketCandidates,
      context, loadoutState, collection.equippedBySlot[13], collection.equippedBySlot[14], allSlots, score, perf),
  }
  if perf then
    perf:Stop(trinketToken)
    perf:Set("trinkets.final_frontier_size", #(groups[#groups].frontier or {}))
  end

  local weaponCandidatesList = weaponCandidates(collection.candidates, collection.equippedBySlot[16], collection.equippedBySlot[17])
  if perf then perf:Set("weapons.candidates", #weaponCandidatesList) end
  local weaponToken = perf and perf:Start("  weapons")
  groups[#groups + 1] = {
    id = "weapons",
    kind = "paired",
    roles = { mh = 16, oh = 17 },
    slots = { 16, 17 },
    frontier = XIVEquip.Assignments.Groups.Weapons.Frontier(
      weaponCandidatesList,
      context, loadoutState, collection.equippedBySlot[16], collection.equippedBySlot[17], allSlots, score, perf),
  }
  if perf then
    perf:Stop(weaponToken)
    perf:Set("weapons.final_frontier_size", #(groups[#groups].frontier or {}))
  end

  return groups
end

local function applyAssignments(finalSlots, groups, selected)
  local slotScores = {}
  local groupScores = {}
  for _, group in ipairs(groups or {}) do
    local assignment = selected and selected[group.id]
    if assignment then
      groupScores[group.id] = assignment.score or 0
      if group.kind == "singleton" then
        finalSlots[group.slot] = assignment.picks.slot
        slotScores[group.slot] = assignment.scores and assignment.scores.slot
      else
        for role, slotID in pairs(group.roles or {}) do
          finalSlots[slotID] = assignment.picks[role]
          slotScores[slotID] = assignment.scores and assignment.scores[role]
        end
      end
    end
  end
  return slotScores, groupScores
end

local function currentScores(collection, context, runtime)
  local scores = {}
  local groupScores = {}
  local loadoutState = XIVEquip.Assignments.LoadoutState.New()
  loadoutState:SeedFromEquipped(collection.equippedBySlot)
  local allSlots = copyArray(OPTIMIZED_SLOTS)

  local function scoreFn(candidate, scoreContext, slot, role)
    if runtime and type(runtime.ScoreCandidate) == "function" then
      return runtime.ScoreCandidate(candidate, scoreContext, slot, role)
    end
    return XIVEquip.Evaluation.CandidateEvaluator.Score(candidate, scoreContext)
  end

  for _, def in ipairs(SINGLETON_SLOTS) do
    local current = collection.equippedBySlot and collection.equippedBySlot[def.slot]
    local assignment = XIVEquip.Assignments.Singleton.Evaluate({
      groupId = def.id,
      slot = def.slot,
      pick = current,
      current = current,
      context = context,
      loadoutState = loadoutState,
      allSlots = allSlots,
      score = scoreFn,
    })
    scores[def.slot] = assignment and assignment.scores and assignment.scores.slot or 0
    groupScores[def.id] = assignment and assignment.score or 0
  end

  local function pairedScores(groupId, roles, slots, currentByRole, emptyAllowed, prepareAssignments)
    local currentBySlot = {}
    for _, role in ipairs(roles) do currentBySlot[slots[role]] = currentByRole[role] end
    local assignment = XIVEquip.Assignments.Paired.Evaluate({
      roles = roles,
      slots = slots,
      groupId = groupId,
      context = context,
      loadoutState = loadoutState,
      score = scoreFn,
      picks = currentByRole,
      removalSlots = allSlots,
      currentByRole = currentByRole,
      currentBySlot = currentBySlot,
      emptyAllowed = emptyAllowed,
      isCurrentState = true,
    })
    if assignment and type(prepareAssignments) == "function" then
      prepareAssignments({ assignment }, context)
    end
    for _, role in ipairs(roles) do
      scores[slots[role]] = assignment and assignment.scores and assignment.scores[role] or 0
    end
    groupScores[groupId] = assignment and assignment.score or 0
  end

  pairedScores("rings", { "first", "second" }, { first = 11, second = 12 }, {
    first = collection.equippedBySlot and collection.equippedBySlot[11],
    second = collection.equippedBySlot and collection.equippedBySlot[12],
  }, {
    first = not (collection.equippedBySlot and collection.equippedBySlot[11]),
    second = not (collection.equippedBySlot and collection.equippedBySlot[12]),
  })
  pairedScores("trinkets", { "first", "second" }, { first = 13, second = 14 }, {
    first = collection.equippedBySlot and collection.equippedBySlot[13],
    second = collection.equippedBySlot and collection.equippedBySlot[14],
  }, {
    first = not (collection.equippedBySlot and collection.equippedBySlot[13]),
    second = not (collection.equippedBySlot and collection.equippedBySlot[14]),
  })
  pairedScores("weapons", { "mh", "oh" }, { mh = 16, oh = 17 }, {
    mh = collection.equippedBySlot and collection.equippedBySlot[16],
    oh = collection.equippedBySlot and collection.equippedBySlot[17],
  }, {
    mh = not (collection.equippedBySlot and collection.equippedBySlot[16]),
    oh = true,
  }, XIVEquip.Assignments.Groups.Weapons.PrepareAssignments)

  return scores, groupScores
end

local function diagnosticsFor(collection, groups, runtime, context, perf)
  local diagnostics = {
    unresolved = collection.unresolved,
    groupFrontierSizes = {},
    scoreSource = runtime and runtime.ScoreSource and runtime.ScoreSource(context) or "XIVWeights",
    weaponCandidates = {},
  }
  for _, group in ipairs(groups or {}) do
    diagnostics.groupFrontierSizes[group.id] = #(group.frontier or {})
  end
  for _, candidate in ipairs(collection.candidates or {}) do
    if WEAPON_EQUIPLOCS[candidateEquipLoc(candidate)] then
      diagnostics.weaponCandidates[#diagnostics.weaponCandidates + 1] = {
        itemID = candidate.itemID,
        link = candidate.link,
        equipLoc = candidateEquipLoc(candidate),
        dps = candidate.weapon and candidate.weapon.dps,
        minimumDamage = candidate.weapon and candidate.weapon.minimumDamage,
        maximumDamage = candidate.weapon and candidate.weapon.maximumDamage,
        score = runtime and runtime.ScoreCandidate and runtime.ScoreCandidate(candidate, context, 16)
          or XIVEquip.Evaluation.CandidateEvaluator.Score(candidate, context),
      }
    end
  end
  if perf then diagnostics.performance = perf:Snapshot() end
  return diagnostics
end

function Coordinator.Plan(opts)
  opts = opts or {}
  local perf = opts.perf
  local runtime = opts.runtime or Planning.Runtime.Live()
  local closed = false
  local function closeRuntime()
    if closed or not (runtime and type(runtime.Close) == "function") then return end
    closed = true
    runtime.Close()
  end

  local totalToken = perf and perf:Start("Total Plan")
  local ok, result = xpcall(function()
    local context = perf and perf:Measure("Context build", function()
      return buildContext({ context = opts.context, resolved = opts.resolved, runtime = runtime })
    end) or buildContext({ context = opts.context, resolved = opts.resolved, runtime = runtime })
    local optimizerContext = setmetatable({ preferFilledSlots = true, perf = perf }, { __index = context })
    local collection = opts.collection or (perf and perf:Measure("Inventory enumeration", function()
      return XIVEquip.Evaluation.CandidateCollector.Collect({ slots = OPTIMIZED_SLOTS, perf = perf })
    end) or XIVEquip.Evaluation.CandidateCollector.Collect({ slots = OPTIMIZED_SLOTS }))
    local allSlots = copyArray(OPTIMIZED_SLOTS)
    local loadoutState = XIVEquip.Assignments.LoadoutState.New()
    loadoutState:SeedFromEquipped(collection.equippedBySlot)

    local score = groupScoreFn(opts, runtime)
    local groups = perf and perf:Measure("Group/frontier construction", function()
      return buildGroups(collection, context, loadoutState, allSlots, score, perf)
    end) or buildGroups(collection, context, loadoutState, allSlots, score)
    local selected, scoreTotal
    if perf then
      selected, scoreTotal = perf:Measure("Global optimizer", function()
        return XIVEquip.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState, optimizerContext)
      end)
    else
      selected, scoreTotal = XIVEquip.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState, optimizerContext)
    end

    local finalSlots = {}
    for _, slotID in ipairs(OPTIMIZED_SLOTS) do
      finalSlots[slotID] = collection.equippedBySlot[slotID]
    end
    local finalSlotScores, finalGroupScores = applyAssignments(finalSlots, groups, selected)
    local currentSlotScores, currentGroupScores
    if perf then
      currentSlotScores, currentGroupScores = perf:Measure("Current-loadout scoring", function()
        return currentScores(collection, context, runtime)
      end)
    else
      currentSlotScores, currentGroupScores = currentScores(collection, context, runtime)
    end
    local diagnostics = perf and perf:Measure("Diagnostics", function()
      return diagnosticsFor(collection, groups, runtime, context, perf)
    end) or diagnosticsFor(collection, groups, runtime, context)

    return {
      finalSlots = finalSlots,
      equippedBySlot = collection.equippedBySlot,
      finalSlotScores = finalSlotScores,
      currentSlotScores = currentSlotScores,
      finalGroupScores = finalGroupScores,
      currentGroupScores = currentGroupScores,
      optimizedSlots = copyArray(OPTIMIZED_SLOTS),
      pending = collection.pending == true,
      weights = context.weights,
      score = scoreTotal or 0,
      diagnostics = diagnostics,
      selectedAssignments = selected or {},
    }
  end, function(err)
    if debug and type(debug.traceback) == "function" then return debug.traceback(tostring(err), 2) end
    return tostring(err)
  end)

  if perf then perf:Stop(totalToken) end
  closeRuntime()
  if not ok then error(result, 0) end
  return result
end

Coordinator.OPTIMIZED_SLOTS = OPTIMIZED_SLOTS
