-- Assignments/Groups.lua
-- The three paired assignment groups (doc section 18.2-18.4): rings
-- (11/12), trinkets (13/14), weapons (16/17). Each Solve function wraps
-- Assignments/Paired.lua with the category-specific tie-break comparator
-- and "is this worth changing" gate that Weapons.lua/Jewelry.lua each
-- hand-roll today -- ported here verbatim, not reinvented.
--
-- No shared slot-pairing table existed in production before this file
-- (Jewelry.lua's PAIRS was a private local; Weapons.lua hardcoded 16/17)
-- -- see the Phase 3 plan's Findings.
--
-- Phase 4 adds a Frontier(...) function alongside each group's Solve(...):
-- Solve is a single-group "is this worth changing" decision (gated against
-- what's currently equipped, and for rings/trinkets, pre-filtered through
-- the empty-slot ilvl floor preference); Frontier is the full set of
-- globally-relevant options for a whole-loadout optimizer to combine
-- across groups (doc section 22 -- keeping only Solve's local winner would
-- make the global optimum unreachable), so it skips both the current-score
-- gate and the ilvl-floor pre-filter (a local preference heuristic, not a
-- whole-loadout legality/dominance concern) and returns every
-- non-dominated legal assignment instead of one pick.
--
-- The frontier invariant every group's Frontier(...) upholds: a frontier
-- represents every relevant LEGAL RESULTING STATE for that group,
-- including the current one. A slot being empty is an ordinary resulting
-- state, not a special case -- it contributes no candidate, no uniqueness
-- usage, and a score of 0. Whether an empty resulting state is available
-- to enumerate for a given role, though, depends on the group's physical
-- semantics: rings/trinkets only allow emptiness when already empty,
-- weapons allow an empty offhand when that is a legal weapon loadout.
-- PlanBuilder decides whether that final empty offhand is already caused
-- by a mainhand equip side effect or requires an explicit offhand cleanup.
local addonName, XIVEquip = ...
XIVEquip.Assignments = XIVEquip.Assignments or {}
local Assignments = XIVEquip.Assignments
local Paired = Assignments.Paired
local Frontier = Assignments.Frontier

local Groups = {}
Assignments.Groups = Groups

local EPS = 1e-6

-- Kept consistent with Assignments/Paired.lua's samePhysical (see that
-- file's comment for why object identity must be checked before falling
-- back to guid/physicalID -- a candidate can legitimately have neither).
local function samePhysical(a, b)
  if not (a and b) then return false end
  if a == b then return true end
  if a.guid and b.guid and a.guid == b.guid then return true end
  if a.physicalID and b.physicalID and a.physicalID == b.physicalID then return true end
  return false
end

-- Does allLegal already contain the exact (currentA, currentB) tuple?
-- Reference equality, matching the established convention that a group's
-- currently-equipped candidates are the very same objects passed in
-- `candidates` (see e.g. Groups.Weapons.Frontier's doc comment) -- the
-- same precedent samePhysical's own object-identity fast path relies on.
local function alreadyRepresents(allLegal, roleA, roleB, currentA, currentB)
  for _, assignment in ipairs(allLegal) do
    if assignment.picks[roleA] == currentA and assignment.picks[roleB] == currentB then
      return true
    end
  end
  return false
end

-- frontierPaired(spec) -> prunedAssignments
-- The shared body behind every group's Frontier(...) (weapons, rings,
-- trinkets alike): every legal assignment for the given roles/slots (not
-- gated against a "current" score -- that's Solve's job, not Frontier's
-- -- doc section 22), plus -- when ordinary enumeration doesn't already
-- produce it -- the literal current state, pruned via
-- Assignments/Frontier.lua.
--
-- spec = {
--   groupId, slots, roles = {roleA, roleB}, candidates, context,
--   loadoutState, compare,
--   emptyAllowed = {[roleA]=bool, [roleB]=bool} -- per role: is an EMPTY
--     RESULTING state for this role legal to ENUMERATE as a candidate
--     transition? Rings/trinkets allow emptiness only for roles that are
--     already empty; weapons allow an empty offhand as a real resulting
--     state but never manufacture an empty mainhand unless it is already
--     empty. Note this governs ENUMERATED transitions only -- the literal
--     current state is always representable regardless of emptyAllowed,
--     via the fallback below.
--   currentA, currentB -- the candidates presently occupying roleA/roleB
--     (or nil). Used for three things: `compare` (an ordinary tiebreak
--     input, needed only to pick Paired.Solve's own discarded `best`,
--     which this function never returns), and (see below) making sure
--     the literal current state is always a representable frontier
--     member.
--   allSlots (optional) -- the union of every slot across every group
--     being jointly optimized in this whole-loadout pass -- e.g.
--     {11,12,13,14,16,17} if weapons, rings, and trinkets are all being
--     combined. MUST be supplied by whole-loadout callers, or
--     Paired.Evaluate defaults to only this group's own slots and
--     recreates LoadoutOptimizer's non-monotonicity bug one layer
--     earlier: a candidate that only conflicts with some OTHER group's
--     CURRENT (soon-to-be-replaced) unique-equipped occupant would look
--     illegal and never make it into this frontier at all, even though
--     the complete loadout is perfectly legal. Omit it only for a
--     genuinely standalone single-group frontier with no other groups
--     involved (matches Solve's default -- this group's own slots).
-- }
--
-- The frontier invariant (see this file's header) requires the actual
-- current state to always be representable, INCLUDING when it contains
-- an empty role. Two separate mechanisms can each fail to produce it
-- through ordinary enumeration:
--   - emptyAllowed being false for an already-empty role (impossible in
--     practice today -- every caller sets emptyAllowed true whenever the
--     corresponding current* is nil -- but not a safe thing to depend on
--     silently).
--   - An assignment-phase policy rejecting the specific current
--     combination as a proposed TRANSITION, even though it's already
--     true. WeaponHandLegality is the concrete case: it unconditionally
--     rejects any assignment with mh=nil, specifically to stop the solver
--     from ever proposing "unequip the mainhand" -- but that same rule
--     also blocks the literal already-true state of "mainhand empty,
--     offhand equipped" from ever being enumerated, even though nothing
--     is being proposed there at all.
-- Rather than have Frontier reason about which policies are transition-
-- only, it directly asks Paired.Evaluate to score the literal
-- (currentA, currentB) tuple with `isCurrentState = true` whenever
-- ordinary enumeration didn't already produce that exact tuple. This
-- skips the both-empty rejection, but NOT policy vetoes -- Paired.Evaluate
-- runs them for real and records the verdict as `policyValid` on the
-- assignment rather than rejecting on it (see that flag's doc comment in
-- Paired.lua). `spec.emptyAllowed` is forwarded alongside so a policy CAN
-- (as WeaponHandLegality does) tell "this role is nil because that's a
-- legitimate resulting state" apart from "this role has a real item the
-- policy actually objects to" -- e.g. gear left over from a since-changed
-- spec that a registered policy now genuinely rejects must keep reading
-- as invalid, or it could dominate and erase a real, policy-valid
-- replacement in Frontier.Dominates (see Frontier.lua).
--
-- This fallback must NOT run unconditionally, or a group whose current
-- state IS already producible through ordinary enumeration (the
-- overwhelmingly common case) would get a redundant duplicate entry.
-- Uniqueness legality still applies to this fallback (CheckAssignment
-- still runs) regardless of policy validity -- a "current" state that is
-- somehow already internally inconsistent isn't one this function should
-- vouch for at all.
local function frontierPaired(spec)
  local roleA, roleB = spec.roles[1], spec.roles[2]
  local currentByRole = { [roleA] = spec.currentA, [roleB] = spec.currentB }
  local currentBySlot = {
    [spec.slots[roleA]] = spec.currentA,
    [spec.slots[roleB]] = spec.currentB,
  }
  local _, allLegal = Paired.Solve({
    roles = spec.roles, slots = spec.slots, emptyAllowed = spec.emptyAllowed,
      candidates = spec.candidates, context = spec.context, loadoutState = spec.loadoutState,
      groupId = spec.groupId, compare = spec.compare,
      score = spec.score,
      removalSlots = spec.allSlots,
      currentByRole = currentByRole,
      currentBySlot = currentBySlot,
  })

  if not alreadyRepresents(allLegal, roleA, roleB, spec.currentA, spec.currentB) then
    local currentAssignment = Paired.Evaluate({
      roles = spec.roles, slots = spec.slots, groupId = spec.groupId,
      context = spec.context, loadoutState = spec.loadoutState, score = spec.score,
      picks = { [roleA] = spec.currentA, [roleB] = spec.currentB },
      removalSlots = spec.allSlots,
      emptyAllowed = spec.emptyAllowed,
      currentByRole = currentByRole,
      currentBySlot = currentBySlot,
      isCurrentState = true,
    })
    if currentAssignment then allLegal[#allLegal + 1] = currentAssignment end
  end

  if type(spec.prepareAssignments) == "function" then
    spec.prepareAssignments(allLegal, spec.context)
  end

  if type(spec.decorateAssignments) == "function" then
    spec.decorateAssignments(allLegal)
  end

  return Frontier.Prune(allLegal)
end

-------------------------------------------------------------------------
-- Weapons (slots 16/17)
-------------------------------------------------------------------------

Groups.Weapons = { id = "weapons", slots = { mh = 16, oh = 17 } }

-- Ports Weapons.lua's loadoutBetter verbatim (lines 273-285): total score,
-- then mh score, then oh score.
local function weaponsCompare(candidate, current)
  if not current then return true end
  if candidate.score ~= current.score then return candidate.score > current.score end

  local candidateMH, currentMH = candidate.scores.mh or 0, current.scores.mh or 0
  if candidateMH ~= currentMH then return candidateMH > currentMH end

  local candidateOH, currentOH = candidate.scores.oh or 0, current.scores.oh or 0
  return candidateOH > currentOH
end

local function is2H(equipLoc)
  return equipLoc == "INVTYPE_2HWEAPON"
      or equipLoc == "INVTYPE_RANGED"
      or equipLoc == "INVTYPE_RANGEDRIGHT"
      or equipLoc == "INVTYPE_THROWN"
end

local function annotateWeaponFilledCount(frontier)
  for _, assignment in ipairs(frontier or {}) do
    local mh = assignment.picks and assignment.picks.mh
    local oh = assignment.picks and assignment.picks.oh
    local mhEquipLoc = mh and mh.equip and mh.equip.equipLoc
    if mh and is2H(mhEquipLoc) then
      assignment.filledCount = 2
    else
      local n = 0
      if mh then n = n + 1 end
      if oh then n = n + 1 end
      assignment.filledCount = n
    end
  end
  return frontier
end

local function prepareWeaponAssignments(frontier, context)
  annotateWeaponFilledCount(frontier)
  local isItemLevel = context and context.weights and context.weights.source and context.weights.source.kind == "ilvl"
  if not isItemLevel then return frontier end
  for _, assignment in ipairs(frontier or {}) do
    local mh = assignment.picks and assignment.picks.mh
    local oh = assignment.picks and assignment.picks.oh
    local mhLevel = tonumber(mh and mh.itemLevel) or 0
    local ohLevel = tonumber(oh and oh.itemLevel) or 0
    local mhEquipLoc = mh and mh.equip and mh.equip.equipLoc
    local mhAdjustment = (tonumber(assignment.scores and assignment.scores.mh) or 0) - mhLevel
    local ohAdjustment = (tonumber(assignment.scores and assignment.scores.oh) or 0) - ohLevel
    if mh and is2H(mhEquipLoc) and not oh then
      assignment.baseScore = mhLevel * 2
      assignment.scoreAdjustment = mhAdjustment
      assignment.scores.mh = assignment.baseScore + mhAdjustment
      assignment.scores.oh = 0
      assignment.score = assignment.baseScore + assignment.scoreAdjustment
    else
      assignment.baseScore = mhLevel + ohLevel
      assignment.scoreAdjustment = mhAdjustment + ohAdjustment
      assignment.scores.mh = mhLevel + mhAdjustment
      assignment.scores.oh = ohLevel + ohAdjustment
      assignment.score = assignment.baseScore + assignment.scoreAdjustment
    end
  end
  return frontier
end

Groups.Weapons.PrepareAssignments = prepareWeaponAssignments

-- Solve(candidates, context, loadoutState, currentMH, currentOH) -> best|nil
-- currentMH/currentOH: the candidates presently equipped in 16/17 (or nil).
function Groups.Weapons.Solve(candidates, context, loadoutState, currentMH, currentOH)
  local weaponsSpec = {
    roles = { "mh", "oh" },
    slots = Groups.Weapons.slots,
    groupId = Groups.Weapons.id,
    context = context,
    loadoutState = loadoutState,
  }

  -- Mirrors PlanBest's currentScore computation (Weapons.lua:319-328): try
  -- the full current pair first; if that's no longer legal (e.g. a spec
  -- change made the equipped combination illegal), fall back to scoring
  -- the mainhand alone rather than treating "current" as unconditionally
  -- illegal.
  local currentScore
  local currentFull = Paired.Evaluate({
    roles = weaponsSpec.roles, slots = weaponsSpec.slots, groupId = weaponsSpec.groupId,
    context = context, loadoutState = loadoutState, picks = { mh = currentMH, oh = currentOH },
    currentByRole = { mh = currentMH, oh = currentOH },
    currentBySlot = { [16] = currentMH, [17] = currentOH },
  })
  if currentFull then
    currentScore = currentFull.score
  else
    local currentMHOnly = Paired.Evaluate({
      roles = weaponsSpec.roles, slots = weaponsSpec.slots, groupId = weaponsSpec.groupId,
      context = context, loadoutState = loadoutState, picks = { mh = currentMH, oh = nil },
      currentByRole = { mh = currentMH, oh = currentOH },
      currentBySlot = { [16] = currentMH, [17] = currentOH },
    })
    currentScore = currentMHOnly and currentMHOnly.score
  end
  currentScore = currentScore or -math.huge

  local best = Paired.Solve({
    roles = weaponsSpec.roles,
    slots = weaponsSpec.slots,
    emptyAllowed = { oh = true },
    candidates = candidates,
    context = context,
    loadoutState = loadoutState,
    groupId = weaponsSpec.groupId,
    compare = weaponsCompare,
    currentByRole = { mh = currentMH, oh = currentOH },
    currentBySlot = { [16] = currentMH, [17] = currentOH },
  })

  if not best or best.score <= currentScore + EPS then return nil end
  return best
end

-- Frontier(candidates, context, loadoutState, currentMH, currentOH, allSlots) -> prunedAssignments
-- Every legal MH/OH resulting state (including "keep exactly what's
-- equipped," since currentMH/currentOH are expected to already be part of
-- `candidates` the same way Solve's own candidate pool works), pruned via
-- Assignments/Frontier.lua -- not gated against a "current" score, since a
-- whole-loadout optimizer needs to compare this group's options against
-- what OTHER groups could do, not just against its own status quo.
--
-- currentMH/currentOH: see frontierPaired's doc comment for their role --
-- here they ALSO decide whether an empty mainhand is a legal resulting
-- state to ENUMERATE as a candidate transition. Offhand is always
-- emptyAllowed: a 1H weapon with no offhand, or a 2H weapon, are both
-- ordinary legal states no matter what's currently there
-- (WeaponHandLegality's assignment-phase policy vetoes illegal hand
-- combinations, not this function). Mainhand is emptyAllowed ONLY when
-- currentMH is nil, so this never manufactures a new "unequip my
-- mainhand" option that Paired.Evaluate's own contract forbids inventing
-- out of nothing.
--
-- Separately, frontierPaired's current-state fallback guarantees the
-- literal (currentMH, currentOH) pair is always representable even when
-- neither of the above lets ordinary enumeration produce it -- e.g.
-- mainhand already empty with a real item in the offhand:
-- WeaponHandLegality rejects every assignment with mh=nil outright (it
-- exists to stop the solver from ever PROPOSING that transition), which
-- would otherwise silently erase the group's actual current state from
-- its own frontier. Without that fallback, a naked character, one with
-- no legal mainhand candidate, or exactly this half-empty case would give
-- LoadoutOptimizer no branch for this group at all, failing the entire
-- loadout even when other groups have valid upgrades.
--
-- `allSlots` (optional): see frontierPaired's doc comment.
function Groups.Weapons.Frontier(candidates, context, loadoutState, currentMH, currentOH, allSlots, score)
  return frontierPaired({
    groupId = Groups.Weapons.id,
    slots = Groups.Weapons.slots,
    roles = { "mh", "oh" },
    candidates = candidates,
    context = context,
    loadoutState = loadoutState,
    compare = weaponsCompare,
    emptyAllowed = { mh = currentMH == nil, oh = true },
    currentA = currentMH,
    currentB = currentOH,
    allSlots = allSlots,
    score = score,
    prepareAssignments = prepareWeaponAssignments,
    decorateAssignments = function(assignments)
      for _, assignment in ipairs(assignments) do
        assignment.tieBreak = {
          tonumber(assignment.scores and assignment.scores.mh) or 0,
        }
      end
    end,
  })
end

-------------------------------------------------------------------------
-- Rings (11/12) and Trinkets (13/14) -- identical shape, parameterized.
-------------------------------------------------------------------------

local EMPTY_SLOT_ILVL_WINDOW = 40

local function missingCount(currentA, currentB)
  local n = 0
  if not currentA then n = n + 1 end
  if not currentB then n = n + 1 end
  return n
end

-- Ports Jewelry.lua's emptySlotIlvlFloor verbatim (lines 179-192): only
-- kicks in when at least one paired slot is currently empty, and is a
-- preference among equally-filled options, never a hard blocker on fill
-- count (see the retry-without-floor logic in the two Solve functions below).
local function emptySlotIlvlFloor(candidates, currentA, currentB)
  local missing = missingCount(currentA, currentB)
  if missing <= 0 then return nil end

  local levels = {}
  for _, c in ipairs(candidates) do
    local ilvl = c and tonumber(c.itemLevel)
    if ilvl and ilvl > 1 then levels[#levels + 1] = ilvl end
  end
  if #levels <= missing then return nil end

  table.sort(levels, function(a, b) return a > b end)
  return levels[missing] - EMPTY_SLOT_ILVL_WINDOW
end

local function filterByFloor(candidates, floor)
  if not floor then return candidates end
  local filtered = {}
  for _, c in ipairs(candidates) do
    local ilvl = tonumber(c.itemLevel)
    if not ilvl or ilvl == 1 or ilvl >= floor then filtered[#filtered + 1] = c end
  end
  return filtered
end

local function filledCountOf(assignment, roleA, roleB)
  local n = 0
  if assignment.picks[roleA] then n = n + 1 end
  if assignment.picks[roleB] then n = n + 1 end
  return n
end

-- Ports Jewelry.lua's betterLoadout verbatim (lines 207-221): filled-slot
-- count, then score, then fewest physical changes vs. what's currently
-- equipped, then (as a final tiebreak) the first role's own score.
local function pairedCompare(roleA, roleB, currentA, currentB)
  return function(candidate, current)
    if not current then return true end

    local candidateFilled, currentFilled = filledCountOf(candidate, roleA, roleB), filledCountOf(current, roleA, roleB)
    if candidateFilled ~= currentFilled then return candidateFilled > currentFilled end
    if candidate.score ~= current.score then return candidate.score > current.score end

    local function changedCount(assignment)
      local n = 0
      if not ((assignment.picks[roleA] == nil and currentA == nil) or samePhysical(assignment.picks[roleA], currentA)) then
        n = n + 1
      end
      if not ((assignment.picks[roleB] == nil and currentB == nil) or samePhysical(assignment.picks[roleB], currentB)) then
        n = n + 1
      end
      return n
    end

    local candidateChanges, currentChanges = changedCount(candidate), changedCount(current)
    if candidateChanges ~= currentChanges then return candidateChanges < currentChanges end

    return (candidate.scores[roleA] or 0) > (current.scores[roleA] or 0)
  end
end


local function pairedChangeCount(assignment, roleA, roleB, currentA, currentB)
  local n = 0
  if not ((assignment.picks[roleA] == nil and currentA == nil) or samePhysical(assignment.picks[roleA], currentA)) then
    n = n + 1
  end
  if not ((assignment.picks[roleB] == nil and currentB == nil) or samePhysical(assignment.picks[roleB], currentB)) then
    n = n + 1
  end
  return n
end

local function jewelryFrontier(groupId, slots, candidates, context, loadoutState, currentA, currentB, allSlots, score)
  local floor = emptySlotIlvlFloor(candidates, currentA, currentB)
  local function build(pool)
    return frontierPaired({
      groupId = groupId,
      slots = slots,
      roles = { "first", "second" },
      candidates = pool,
      context = context,
      loadoutState = loadoutState,
      compare = pairedCompare("first", "second", currentA, currentB),
      emptyAllowed = { first = currentA == nil, second = currentB == nil },
      currentA = currentA,
      currentB = currentB,
      allSlots = allSlots,
      score = score,
      decorateAssignments = function(assignments)
        for _, assignment in ipairs(assignments) do
          assignment.tieBreak = {
            -pairedChangeCount(assignment, "first", "second", currentA, currentB),
            tonumber(assignment.scores and assignment.scores.first) or 0,
          }
        end
      end,
    })
  end

  local preferred = build(filterByFloor(candidates, floor))
  if not floor then return preferred end

  local unrestricted = build(candidates)
  local function maxFilled(assignments)
    local best = 0
    for _, assignment in ipairs(assignments) do
      best = math.max(best, filledCountOf(assignment, "first", "second"))
    end
    return best
  end

  if maxFilled(unrestricted) > maxFilled(preferred) then return unrestricted end
  return preferred
end

-- solvePaired: the shared body behind Groups.Rings.Solve/Groups.Trinkets.Solve
-- -- ports Jewelry.lua's solvePair orchestration (lines 313-354) around
-- the one shared Paired.Solve call: current-score computation, the
-- ilvl-floor-then-unrestricted-retry (Jewelry.lua:328-340), and the final
-- "worth changing" gate.
local function solvePaired(groupId, slots, candidates, context, loadoutState, currentA, currentB)
  local roleA, roleB = "first", "second"
  local roles = { roleA, roleB }

  local emptyAllowed = { [roleA] = currentA == nil, [roleB] = currentB == nil }
  local currentAssignment = Paired.Evaluate({
    roles = roles, slots = slots, groupId = groupId, context = context, loadoutState = loadoutState,
    picks = { [roleA] = currentA, [roleB] = currentB },
    currentByRole = { [roleA] = currentA, [roleB] = currentB },
    currentBySlot = { [slots[roleA]] = currentA, [slots[roleB]] = currentB },
    isCurrentState = true,
    emptyAllowed = emptyAllowed,
  })

  local compare = pairedCompare(roleA, roleB, currentA, currentB)
  local floor = emptySlotIlvlFloor(candidates, currentA, currentB)

  local function attempt(pool)
    return Paired.Solve({
      roles = roles, slots = slots, emptyAllowed = emptyAllowed,
      candidates = pool, context = context, loadoutState = loadoutState, groupId = groupId, compare = compare,
      currentByRole = { [roleA] = currentA, [roleB] = currentB },
      currentBySlot = { [slots[roleA]] = currentA, [slots[roleB]] = currentB },
    })
  end

  local best = attempt(filterByFloor(candidates, floor))
  if floor then
    local unrestricted = attempt(candidates)
    if unrestricted and (not best or filledCountOf(unrestricted, roleA, roleB) > filledCountOf(best, roleA, roleB)) then
      best = unrestricted
    end
  end

  if not best then return nil end
  if currentAssignment and currentAssignment.policyValid ~= false and not compare(best, currentAssignment) then
    return nil
  end
  return best
end

Groups.Rings = { id = "rings", slots = { first = 11, second = 12 } }
function Groups.Rings.Solve(candidates, context, loadoutState, currentA, currentB)
  return solvePaired(Groups.Rings.id, Groups.Rings.slots, candidates, context, loadoutState, currentA, currentB)
end
function Groups.Rings.Frontier(candidates, context, loadoutState, currentA, currentB, allSlots, score)
  return jewelryFrontier(Groups.Rings.id, Groups.Rings.slots, candidates, context, loadoutState,
    currentA, currentB, allSlots, score)
end

Groups.Trinkets = { id = "trinkets", slots = { first = 13, second = 14 } }
function Groups.Trinkets.Solve(candidates, context, loadoutState, currentA, currentB)
  return solvePaired(Groups.Trinkets.id, Groups.Trinkets.slots, candidates, context, loadoutState, currentA, currentB)
end
function Groups.Trinkets.Frontier(candidates, context, loadoutState, currentA, currentB, allSlots, score)
  return jewelryFrontier(Groups.Trinkets.id, Groups.Trinkets.slots, candidates, context, loadoutState,
    currentA, currentB, allSlots, score)
end
