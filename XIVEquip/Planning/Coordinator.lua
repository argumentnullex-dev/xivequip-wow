-- Planning/Coordinator.lua
-- Shadow RecommendationResult coordinator for the 2.0 evaluation pipeline.
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

local function buildGroups(collection, context, loadoutState, allSlots, score)
  local groups = {}
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

  groups[#groups + 1] = {
    id = "rings",
    kind = "paired",
    roles = { first = 11, second = 12 },
    slots = { 11, 12 },
    frontier = XIVEquip.Assignments.Groups.Rings.Frontier(
      candidatesForEquipLoc(collection.candidates, "INVTYPE_FINGER", collection.equippedBySlot[11], collection.equippedBySlot[12]),
      context, loadoutState, collection.equippedBySlot[11], collection.equippedBySlot[12], allSlots, score),
  }
  groups[#groups + 1] = {
    id = "trinkets",
    kind = "paired",
    roles = { first = 13, second = 14 },
    slots = { 13, 14 },
    frontier = XIVEquip.Assignments.Groups.Trinkets.Frontier(
      candidatesForEquipLoc(collection.candidates, "INVTYPE_TRINKET", collection.equippedBySlot[13], collection.equippedBySlot[14]),
      context, loadoutState, collection.equippedBySlot[13], collection.equippedBySlot[14], allSlots, score),
  }
  groups[#groups + 1] = {
    id = "weapons",
    kind = "paired",
    roles = { mh = 16, oh = 17 },
    slots = { 16, 17 },
    frontier = XIVEquip.Assignments.Groups.Weapons.Frontier(
      weaponCandidates(collection.candidates, collection.equippedBySlot[16], collection.equippedBySlot[17]),
      context, loadoutState, collection.equippedBySlot[16], collection.equippedBySlot[17], allSlots, score),
  }

  return groups
end

local function applyAssignments(finalSlots, groups, selected)
  for _, group in ipairs(groups or {}) do
    local assignment = selected and selected[group.id]
    if assignment then
      if group.kind == "singleton" then
        finalSlots[group.slot] = assignment.picks.slot
      else
        for role, slotID in pairs(group.roles or {}) do
          finalSlots[slotID] = assignment.picks[role]
        end
      end
    end
  end
end

local function diagnosticsFor(collection, groups, runtime, context)
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
  return diagnostics
end

function Coordinator.Plan(opts)
  opts = opts or {}
  local runtime = opts.runtime or Planning.Runtime.Live()
  local closed = false
  local function closeRuntime()
    if closed or not (runtime and type(runtime.Close) == "function") then return end
    closed = true
    runtime.Close()
  end

  local ok, result = xpcall(function()
    local context = buildContext({ context = opts.context, resolved = opts.resolved, runtime = runtime })
    local optimizerContext = setmetatable({ preferFilledSlots = true }, { __index = context })
    local collection = opts.collection or XIVEquip.Evaluation.CandidateCollector.Collect({ slots = OPTIMIZED_SLOTS })
    local allSlots = copyArray(OPTIMIZED_SLOTS)
    local loadoutState = XIVEquip.Assignments.LoadoutState.New()
    loadoutState:SeedFromEquipped(collection.equippedBySlot)

    local score = groupScoreFn(opts, runtime)
    local groups = buildGroups(collection, context, loadoutState, allSlots, score)
    local selected, scoreTotal = XIVEquip.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState, optimizerContext)

    local finalSlots = {}
    for _, slotID in ipairs(OPTIMIZED_SLOTS) do
      finalSlots[slotID] = collection.equippedBySlot[slotID]
    end
    applyAssignments(finalSlots, groups, selected)

    return {
      finalSlots = finalSlots,
      equippedBySlot = collection.equippedBySlot,
      optimizedSlots = copyArray(OPTIMIZED_SLOTS),
      pending = collection.pending == true,
      score = scoreTotal or 0,
      diagnostics = diagnosticsFor(collection, groups, runtime, context),
      selectedAssignments = selected or {},
    }
  end, function(err)
    if debug and type(debug.traceback) == "function" then return debug.traceback(tostring(err), 2) end
    return tostring(err)
  end)

  closeRuntime()
  if not ok then error(result, 0) end
  return result
end

Coordinator.OPTIMIZED_SLOTS = OPTIMIZED_SLOTS
