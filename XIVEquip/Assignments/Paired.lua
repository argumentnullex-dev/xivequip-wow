-- Assignments/Paired.lua
-- The generic paired-assignment solver (doc section 19): shared
-- enumeration, physical-item dedup, uniqueness accounting, and
-- assignment-phase policy vetoes for any two-slot pairing problem (rings,
-- trinkets, weapon hands). Category-specific legality (e.g. weapon-hand
-- rules) and scoring/tie-break policy live outside this file -- see
-- Groups.lua and Policies/Assignment/WeaponHandLegality.lua.
--
-- Two public entry points:
--   Paired.Evaluate(spec) -> assignment|nil   -- score ONE given picks map
--   Paired.Solve(spec)    -> best, allLegal   -- search every combination
-- Solve is built on Evaluate (same legality path for both), which is also
-- how Groups.lua scores "what's currently equipped" under identical rules
-- to any candidate replacement, without a separate code path.
--
-- Note: the original Weapons.lua/Jewelry.lua both also ran a *pairwise*
-- uniqueCompatible(a,b) check before calling Core.UniqueAssignmentOK.
-- That turns out to be redundant, not an extra rule: UniqueAssignmentOK
-- given BOTH candidates as one `additions` list already fails whenever
-- they share a uniqueKey with a combined limit < 2, which is exactly
-- uniqueCompatible's condition. LoadoutState:CheckAssignment (this file's
-- only uniqueness call) reproduces that same combined-additions math, so
-- there is nothing left for a separate pairwise check to catch.
local addonName, XIVEquip = ...
XIVEquip.Assignments = XIVEquip.Assignments or {}
local Assignments = XIVEquip.Assignments

local Paired = {}
Assignments.Paired = Paired

-- Only Paired.lua's own enumeration ever sees this -- it's converted to
-- nil (a real empty role) before an assignment record is ever returned or
-- handed to a policy/comparator.
local EMPTY = {}

local function isEmptyMarker(value) return value == EMPTY end

-- CandidateNormalizer.FromLink copies source.guid/source.physicalID
-- verbatim, and `source` is caller-optional -- so a perfectly valid
-- candidate can have neither. Falling back to `a.physicalID or a.guid`
-- and comparing that to nil would let two SUCH candidates (both nil)
-- report as "the same physical item" only by accident of both being
-- absent, but worse: since Solve() puts every candidate into both role
-- pools, a single identity-less candidate would pass this check against
-- ITSELF (a IS b), meaning the same physical item could be assigned to
-- both roles and scored twice. Checking object identity first, then each
-- identity field independently (never conflating "both absent" with
-- "equal"), closes that gap regardless of whether identity metadata is
-- present.
local function samePhysical(a, b)
  if not (a and b) then return false end
  if a == b then return true end
  if a.guid and b.guid and a.guid == b.guid then return true end
  if a.physicalID and b.physicalID and a.physicalID == b.physicalID then return true end
  return false
end

local function defaultScore(candidate, context)
  if not candidate then return 0 end
  return XIVEquip.Evaluation.CandidateEvaluator.Score(candidate, context)
end

local EMPTY_EVALUATION = {
  eligible = true,
  score = 0,
  baseScore = 0,
  scoreAdjustment = 0,
  setCounts = {},
  targetFlags = {},
  requiredFlags = {},
  reasons = {},
}

local function scoreFunction(spec, role, slot)
  if spec.score then
    return function(c, context) return spec.score(c, context, slot, role) end
  end
  return defaultScore
end

local function evaluateCandidate(candidate, spec, role, slot, scoreCandidate)
  if not candidate then
    return EMPTY_EVALUATION
  end
  return XIVEquip.Evaluation.CandidateEvaluator.Evaluate(candidate, spec.context, {
    groupId = spec.groupId,
    role = role,
    slot = slot,
    currentCandidate = spec.currentByRole and spec.currentByRole[role],
    currentByRole = spec.currentByRole,
    currentBySlot = spec.currentBySlot,
    score = scoreCandidate or scoreFunction(spec, role, slot),
  })
end

local function mergeNumericMap(target, source)
  if type(source) ~= "table" then return end
  for key, value in pairs(source) do
    if type(value) == "number" then target[key] = (target[key] or 0) + value end
  end
end

local function mergeFlags(target, source)
  if type(source) ~= "table" then return end
  for key, value in pairs(source) do
    if value then target[key] = true end
  end
end

local function appendAll(target, source)
  if type(source) ~= "table" then return end
  for _, value in ipairs(source) do target[#target + 1] = value end
end

local function filledCount(picks)
  local n = 0
  for _, candidate in pairs(picks or {}) do
    if candidate then n = n + 1 end
  end
  return n
end

-- assignment-phase policies scoped to this group: a policy with no
-- `groups` field applies everywhere; one with a `groups` array only
-- applies when groupId is listed in it.
local function assignmentPoliciesFor(context, groupId)
  local resolver = XIVEquip.Policies and XIVEquip.Policies.Resolver
  if resolver and resolver.ActiveForPhase then
    return resolver.ActiveForPhase(context, "assignment", groupId)
  end
  return (context and context.policies and context.policies.assignment) or {}
end

local function policiesAllow(policies, assignment, context)
  for _, policy in ipairs(policies) do
    if policy.apply(assignment, context) == false then return false end
  end
  return true
end

local function assignmentFromEvaluations(spec, roleA, roleB, slotA, slotB, pickA, pickB, evalA, evalB, checker, policies)
  if pickA and pickB and samePhysical(pickA, pickB) then return nil end
  if not spec.isCurrentState and not pickA and not pickB then return nil end

  local candidatesEligible = evalA.eligible ~= false and evalB.eligible ~= false
  if not candidatesEligible and not spec.isCurrentState then return nil end

  if checker then
    local legal
    if pickA and pickB then
      legal = checker:CheckPair(pickA, pickB)
    elseif pickA then
      legal = checker:CheckOne(pickA)
    elseif pickB then
      legal = checker:CheckOne(pickB)
    else
      legal = checker:Check(nil)
    end
    if not legal then return nil end
  else
    local additions
    if pickA and pickB then
      additions = { pickA, pickB }
    elseif pickA then
      additions = { pickA }
    elseif pickB then
      additions = { pickB }
    end
    local removalSlots = spec.removalSlots or { slotA, slotB }
    if not spec.loadoutState:CheckAssignment(additions, removalSlots) then return nil end
  end

  local assignment = {
    groupId = spec.groupId,
    picks = { [roleA] = pickA, [roleB] = pickB },
    currentByRole = spec.currentByRole,
    currentBySlot = spec.currentBySlot,
  }
  -- emptyAllowed is only ever consulted during this policy check (see
  -- this function's doc comment) -- not left on the returned assignment,
  -- which otherwise has the exact same shape regardless of isCurrentState.
  if spec.isCurrentState then assignment.emptyAllowed = spec.emptyAllowed end
  local policyValid = policiesAllow(policies or assignmentPoliciesFor(spec.context, spec.groupId), assignment, spec.context)
  assignment.emptyAllowed = nil
  assignment.currentByRole = nil
  assignment.currentBySlot = nil
  local finalPolicyValid = policyValid and candidatesEligible
  if not finalPolicyValid and not spec.isCurrentState then return nil end
  assignment.policyValid = finalPolicyValid

  local scoreA = evalA.score or 0
  local scoreB = evalB.score or 0
  assignment.scores = { [roleA] = scoreA, [roleB] = scoreB }
  assignment.score = scoreA + scoreB
  assignment.filledCount = filledCount(assignment.picks)
  assignment.baseScore = (evalA.baseScore or 0) + (evalB.baseScore or 0)
  assignment.scoreAdjustment = (evalA.scoreAdjustment or 0) + (evalB.scoreAdjustment or 0)
  assignment.setCounts = {}
  assignment.targetFlags = {}
  assignment.requiredFlags = {}
  assignment.reasons = {}
  mergeNumericMap(assignment.setCounts, evalA.setCounts)
  mergeNumericMap(assignment.setCounts, evalB.setCounts)
  mergeFlags(assignment.targetFlags, evalA.targetFlags)
  mergeFlags(assignment.targetFlags, evalB.targetFlags)
  mergeFlags(assignment.requiredFlags, evalA.requiredFlags)
  mergeFlags(assignment.requiredFlags, evalB.requiredFlags)
  appendAll(assignment.reasons, evalA.reasons)
  appendAll(assignment.reasons, evalB.reasons)
  return assignment
end

-- Evaluate(spec) -> assignment|nil
-- spec = {
--   roles = {roleA, roleB}, slots = {[roleA]=slotID, [roleB]=slotID},
--   groupId, context, loadoutState, score = fn(candidate,context)->number (optional),
--   picks = {[roleA]=candidate|nil, [roleB]=candidate|nil},
--   currentByRole = {[roleA]=currentlyEquippedCandidate|nil, ...} (optional),
--   currentBySlot = {[slotID]=currentlyEquippedCandidate|nil, ...} (optional),
--   removalSlots = {slotID, ...} (optional -- see below),
--   isCurrentState = bool (optional -- see below),
-- }
-- Returns nil if the assignment is illegal: both roles physically the
-- same item, both roles empty (never a legitimate *choice* -- see Solve),
-- a uniqueness-limit violation, or an assignment-phase policy veto.
--
-- removalSlots controls which slots' CURRENT occupants get provisionally
-- removed before checking uniqueness limits (LoadoutState:CheckAssignment's
-- own parameter, passed straight through). Defaults to this group's own
-- two slots -- correct for a standalone single-group decision, where
-- nothing outside this group is being touched. Whole-loadout frontier
-- construction (Groups.lua's Frontier functions) MUST override this with
-- the union of every slot across every group being jointly optimized, or
-- a candidate that only conflicts with another group's CURRENT (and
-- soon-to-be-replaced) occupant gets rejected before the optimizer ever
-- has a chance to see it -- the same non-monotonicity bug
-- Optimization/LoadoutOptimizer.lua's header describes, recreated one
-- layer earlier by defaulting this wrong.
--
-- isCurrentState: set only by Groups.lua's frontierPaired, to evaluate
-- the literal picks that are ALREADY equipped right now -- not a proposed
-- transition. This skips the "both roles empty" rejection, because that
-- rule exists to stop a solver from proposing a change that helps no one
-- -- it says nothing about a state that's already real. It does NOT skip
-- assignment-phase policy vetoes, though: those are checked exactly as
-- normal, and the result is recorded on the returned assignment as
-- `assignment.policyValid` rather than used to reject it. Frontier.lua's
-- Dominates reads `policyValid` as an absolute dimension: any policy-valid
-- assignment dominates any policy-invalid one outright, regardless of
-- score, so an illegal current state can only ever survive pruning when
-- it's the sole representable option for its group, never by outscoring
-- (and thereby erasing) a legal replacement -- e.g. a two-hander left over
-- from a spec that has since changed to one that forbids it (a REGISTERED
-- POLICY, doc section 15.3's stable extension surface, genuinely and
-- correctly rejecting real, non-nil gear) must not be treated as
-- equivalent to a policy-valid result.
--
-- spec.emptyAllowed (optional, only meaningful with isCurrentState): the
-- same per-role map Solve's own pool construction uses, describing which
-- roles are allowed to be an EMPTY resulting state at all. It's attached
-- to the assignment (as `assignment.emptyAllowed`) purely so a policy CAN
-- distinguish "this role is nil because that's an architecturally
-- sanctioned resulting state" from "this role is nil for some other
-- reason" -- WeaponHandLegality specifically uses it to avoid rejecting a
-- currently-empty mainhand purely for being empty (that's a solver-
-- proposal concern already handled by emptyAllowed's role in enumeration,
-- not a real illegality) while still rejecting a REAL item a policy
-- actively objects to (which is never nil, so this hint is irrelevant to
-- it) -- this is deliberately NOT attached for ordinary, non-current-state
-- evaluation, so no existing enumerated-transition behavior changes: only
-- the isCurrentState fallback ever asks a policy to be lenient about an
-- empty role.
--
-- The uniqueness-limit check and the same-physical-item check still run
-- unconditionally either way regardless of isCurrentState -- both are
-- facts about internal consistency, not policy, and a current state that
-- somehow violates them isn't one this function should vouch for at all.
function Paired.Evaluate(spec)
  local roleA, roleB = spec.roles[1], spec.roles[2]
  local slotA, slotB = spec.slots[roleA], spec.slots[roleB]
  local pickA, pickB = spec.picks[roleA], spec.picks[roleB]

  local evalA = evaluateCandidate(pickA, spec, roleA, slotA)
  local evalB = evaluateCandidate(pickB, spec, roleB, slotB)
  return assignmentFromEvaluations(spec, roleA, roleB, slotA, slotB, pickA, pickB, evalA, evalB)
end

-- Solve(spec) -> best, allLegal
-- spec extends Evaluate's shape with:
--   emptyAllowed = {[roleA]=bool, [roleB]=bool} (which roles may be left empty),
--   candidates = array of candidates available to either role,
--   compare = fn(assignment, currentBest) -> bool ("is assignment better?").
-- (spec.removalSlots, if given, is forwarded to every Evaluate call
-- unchanged -- see Evaluate's doc comment.)
-- `best` is the highest-scoring legal assignment per `compare`, or nil if
-- none exist. This does NOT compare against "what's currently equipped" --
-- that decision (and any category-specific retry, like the ring/trinket
-- empty-slot ilvl floor) belongs to the caller (Groups.lua), since it
-- needs the *unconstrained* best to decide things like "did restricting
-- the pool cost us a filled slot" before any current-vs-new comparison.
-- `allLegal` is returned too, even though nothing prunes/uses it yet --
-- it's already computed during enumeration, and Phase 4's frontier work
-- can consume it later without changes here.
function Paired.Solve(spec)
  local allLegal = {}
  local best = nil
  Paired.Enumerate(spec, function(assignment)
    allLegal[#allLegal + 1] = assignment
    if not best or spec.compare(assignment, best) then best = assignment end
  end)

  return best, allLegal
end

function Paired.Enumerate(spec, visit)
  local roleA, roleB = spec.roles[1], spec.roles[2]
  local slotA, slotB = spec.slots[roleA], spec.slots[roleB]
  local emptyAllowed = spec.emptyAllowed or {}
  local candidates = spec.candidates or {}
  local scoreA = scoreFunction(spec, roleA, slotA)
  local scoreB = scoreFunction(spec, roleB, slotB)
  local removalSlots = spec.removalSlots or { slotA, slotB }
  local checker = spec.loadoutState:PrepareAssignmentChecker(removalSlots)
  local policies = assignmentPoliciesFor(spec.context, spec.groupId)

  local poolA, poolB = {}, {}
  for _, c in ipairs(candidates) do
    poolA[#poolA + 1] = {
      pick = c,
      eval = evaluateCandidate(c, spec, roleA, slotA, scoreA),
    }
    poolB[#poolB + 1] = {
      pick = c,
      eval = evaluateCandidate(c, spec, roleB, slotB, scoreB),
    }
  end
  if emptyAllowed[roleA] then poolA[#poolA + 1] = { pick = EMPTY, eval = EMPTY_EVALUATION } end
  if emptyAllowed[roleB] then poolB[#poolB + 1] = { pick = EMPTY, eval = EMPTY_EVALUATION } end

  local perf = spec.perf
  if perf then perf:Add(tostring(spec.groupId or "paired") .. ".raw_pair_combinations", #poolA * #poolB) end
  if perf then perf:Add(tostring(spec.groupId or "paired") .. ".candidate_evaluations_precomputed", #candidates * 2) end
  local legalCount = 0
  for _, entryA in ipairs(poolA) do
    for _, entryB in ipairs(poolB) do
      -- NOT `isEmptyMarker(a) and nil or a` -- that idiom always evaluates
      -- to `a`, because `x and nil` is always nil/false, so the `or`
      -- branch fires unconditionally. An explicit if/else is required
      -- whenever the "true" branch value can itself be nil/false.
      local pickA
      if isEmptyMarker(entryA.pick) then pickA = nil else pickA = entryA.pick end
      local pickB
      if isEmptyMarker(entryB.pick) then pickB = nil else pickB = entryB.pick end
      local assignment = assignmentFromEvaluations(spec, roleA, roleB, slotA, slotB,
        pickA, pickB, entryA.eval, entryB.eval, checker, policies)
      if assignment then
        legalCount = legalCount + 1
        visit(assignment)
      end
    end
  end
  if perf then perf:Add(tostring(spec.groupId or "paired") .. ".legal_assignments", legalCount) end
end
