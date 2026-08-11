-- Optimization/LoadoutOptimizer.lua
-- The whole-loadout optimizer (doc section 24): combines multiple groups'
-- dominance-pruned frontiers (Assignments/Frontier.lua) into the single
-- best complete legal combination, via exact depth-first branch-and-bound.
--
-- Cross-group legality mirrors Assignments/LoadoutState.lua's
-- CheckAssignment math, but the DFS keeps branch-local uniqueness state
-- incrementally instead of rebuilding the same count/limit tables from
-- scratch at every node. LoadoutState remains the public API for callers
-- and tests that need standalone assignment checks.
--
-- CRITICAL: `removalSlots` passed to every CheckAssignment call during
-- search must always be the FULL union of every slot any group being
-- optimized governs -- not just the slots of groups already chosen in
-- this branch. CheckAssignment only provisionally removes a slot's
-- ORIGINAL occupant when that slot appears in removalSlots; a slot
-- belonging to a not-yet-visited group would otherwise still count its
-- original occupant against the limit, even though that group is
-- guaranteed to decide its final contents before the branch completes.
-- Concrete failure this avoids: slot 2 currently holds unique category X
-- (limit 1); group A (slot 1) wants another X; group B (slot 2) will
-- replace the equipped X with something non-unique. If A is visited
-- first and removalSlots only contained slot 1, the still-uncounted
-- original X in slot 2 would make A's new X look like a second X and
-- reject a branch that is actually fully legal once B's choice is
-- accounted for. Using the full slot union from the very first call
-- treats every optimized slot's original occupant as already gone,
-- regardless of visitation order -- additions still only accumulate
-- picks from groups actually decided so far, so the check remains exact
-- once every group has been chosen (a leaf's `additions` is then the
-- complete final state) and merely optimistic (never incorrectly
-- restrictive) at intermediate steps.
--
-- The objective is LEXICOGRAPHIC, not pure score maximization: minimize
-- the number of policy-invalid assignments used (Assignments/Frontier.lua's
-- `policyValid` -- e.g. a leftover item that's illegal under a spec
-- change but kept around as a "current state" fallback so a group's
-- frontier is never empty -- see Groups.lua's frontierPaired), and only
-- among combinations tied on that count, maximize total score. A
-- policy-invalid fallback exists purely so the whole optimization doesn't
-- fail when a group has no valid option at all -- it must never be
-- preferred over a valid alternative just for scoring higher, in THIS
-- group or in any other group being optimized alongside it. Frontier.Dominates
-- deliberately does not enforce this locally (a valid assignment may only
-- dominate an invalid one when it's also no worse on uniqueness usage --
-- see that file's header for why: whether a "better" valid replacement is
-- actually usable can depend on what some OTHER group needs), so both can
-- legitimately coexist in the same group's frontier; only the
-- whole-loadout objective can decide, across every group at once, how few
-- invalid fallbacks are actually unavoidable.
local addonName, XIVEquip = ...
XIVEquip.Optimization = XIVEquip.Optimization or {}
local Optimization = XIVEquip.Optimization

local LoadoutOptimizer = {}
Optimization.LoadoutOptimizer = LoadoutOptimizer

local function nonNilPicks(assignment)
  local list = {}
  for _, candidate in pairs(assignment.picks or {}) do
    if candidate then list[#list + 1] = candidate end
  end
  return list
end

local function appendAll(target, source)
  for _, v in ipairs(source) do target[#target + 1] = v end
end

local function invalidCost(assignment)
  if assignment.policyValid == false then return 1 end
  return 0
end

local function filledCount(assignment)
  if type(assignment.filledCount) == "number" then return assignment.filledCount end
  local n = 0
  for _, candidate in pairs(assignment.picks or {}) do
    if candidate then n = n + 1 end
  end
  return n
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

local function summarizeChosen(chosen)
  local summary = { setCounts = {}, targetFlags = {}, requiredFlags = {} }
  for _, assignment in pairs(chosen or {}) do
    mergeNumericMap(summary.setCounts, assignment.setCounts)
    mergeFlags(summary.targetFlags, assignment.targetFlags)
    mergeFlags(summary.requiredFlags, assignment.requiredFlags)
  end
  return summary
end

local function activePolicies(context, phase)
  local resolver = XIVEquip.Policies and XIVEquip.Policies.Resolver
  if resolver and resolver.ActiveForPhase then
    return resolver.ActiveForPhase(context, phase)
  end
  return (context and context.policies and context.policies[phase]) or {}
end

local function accumulate(counts, limits, key, limit)
  counts[key] = (counts[key] or 0) + 1
  limit = tonumber(limit) or 1
  limits[key] = limits[key] and math.min(limits[key], limit) or limit
end

local function buildUniqueSearchState(loadoutState, removalSlots)
  local removalSet = {}
  for _, slotID in ipairs(removalSlots or {}) do removalSet[slotID] = true end

  local state = { counts = {}, limits = {} }
  for slotID, rec in pairs((loadoutState and loadoutState.equippedUniqueBySlot) or {}) do
    if rec.key and not removalSet[slotID] then
      accumulate(state.counts, state.limits, rec.key, rec.limit)
    end
  end
  return state
end

local function pushUniqueness(uniqueState, assignment)
  local changes = {}
  for _, candidate in pairs((assignment and assignment.picks) or {}) do
    local uniqueness = candidate and candidate.uniqueness
    local key = uniqueness and uniqueness.key
    if key then
      changes[#changes + 1] = {
        key = key,
        count = uniqueState.counts[key],
        limit = uniqueState.limits[key],
      }
      accumulate(uniqueState.counts, uniqueState.limits, key, uniqueness.limit)
      if uniqueState.counts[key] > (uniqueState.limits[key] or 1) then
        for i = #changes, 1, -1 do
          local change = changes[i]
          uniqueState.counts[change.key] = change.count
          uniqueState.limits[change.key] = change.limit
        end
        return nil
      end
    end
  end
  return changes
end

local function popUniqueness(uniqueState, changes)
  for i = #(changes or {}), 1, -1 do
    local change = changes[i]
    uniqueState.counts[change.key] = change.count
    uniqueState.limits[change.key] = change.limit
  end
end

local function applyLoadoutPolicies(chosen, additions, score, context, policies)
  policies = policies or activePolicies(context, "loadout")
  if #policies == 0 then return true, score end

  local loadout = {
    assignments = chosen,
    additions = additions,
    score = score,
    summaries = summarizeChosen(chosen),
  }
  local finalScore = score
  for _, policy in ipairs(policies) do
    local result = policy.apply(loadout, context)
    if result == false then return false, finalScore end
    if type(result) == "table" then
      if result.allow == false or result.valid == false then return false, finalScore end
      finalScore = finalScore + (tonumber(result.scoreAdjustment) or 0)
      finalScore = finalScore + (tonumber(result.preferenceAdjustment) or 0)
    end
  end
  return true, finalScore
end

local function applyPreferencePolicies(loadout, score, context, policies)
  policies = policies or activePolicies(context, "preference")
  local finalScore = score
  for _, policy in ipairs(policies) do
    local result = policy.apply(loadout, context)
    if type(result) == "table" then
      finalScore = finalScore + (tonumber(result.scoreAdjustment) or 0)
      finalScore = finalScore + (tonumber(result.preferenceAdjustment) or 0)
    end
  end
  return finalScore
end

-- FindBest(groups, loadoutState, context) -> combination, score
-- groups: array of { id = groupId, slots = {slotID, ...}, frontier = {assignmentRecord, ...} }
-- (assignmentRecord is whatever Assignments/Paired.lua's Evaluate/Solve
-- produces: {groupId, picks, scores, score, policyValid} -- this module
-- only reads .picks, .score, and .policyValid).
-- context: optional EvaluationContext. When present, loadout-phase
-- policies may reject a complete loadout or add loadout-level score (for
-- example a set-threshold bonus), and preference-phase policies may then
-- adjust final ranking. Positive leaf-time adjustments are only known at
-- leaf time, so score-only branch pruning is disabled whenever loadout or
-- preference policies exist; legality and policy-validity pruning remain.
-- Returns combination = {groupId -> assignmentRecord} and the total score
-- of the chosen combination including loadout policy score adjustments
-- (but NOT any combined lexicographic value -- invalid-count only ever
-- exists to CHOOSE between candidates, never to change what "score"
-- means), or nil, nil if no legal combination exists across every group
-- (only possible if some group's frontier is empty -- in practice "keep
-- exactly what's equipped" is always a member of a real Frontier() call's
-- result, so this is a degenerate-input case, not an expected outcome).
function LoadoutOptimizer.FindBest(groups, loadoutState, context)
  local perf = context and context.perf
  -- Copy + sort by frontier size ascending (doc 24.2: "favor groups with
  -- small frontiers") -- restrictive groups fail fast and prune more of
  -- the search tree earlier.
  local ordered = {}
  for i, group in ipairs(groups) do ordered[i] = group end
  table.sort(ordered, function(a, b) return #a.frontier < #b.frontier end)

  -- Sort each frontier policy-valid-first, then best-score-first within
  -- that: the search tries its most promising (cheapest on validity,
  -- then highest-scoring) option per group first, tightening both bounds
  -- below as early as possible.
  local function tieBreakBetter(a, b)
    local aValues, bValues = a.tieBreak or {}, b.tieBreak or {}
    local count = math.max(#aValues, #bValues)
    for i = 1, count do
      local aValue, bValue = tonumber(aValues[i]) or 0, tonumber(bValues[i]) or 0
      if aValue ~= bValue then return aValue > bValue end
    end
    return false
  end

  for _, group in ipairs(ordered) do
    table.sort(group.frontier, function(a, b)
      local aInvalid, bInvalid = invalidCost(a), invalidCost(b)
      if aInvalid ~= bInvalid then return aInvalid < bInvalid end
      if a.score ~= b.score then return a.score > b.score end
      return tieBreakBetter(a, b)
    end)
  end

  local n = #ordered
  local loadoutPolicies = activePolicies(context, "loadout")
  local preferencePolicies = activePolicies(context, "preference")
  local hasLoadoutPolicies = #loadoutPolicies > 0
  local hasPreferencePolicies = #preferencePolicies > 0
  local preferFilledSlots = context and context.preferFilledSlots == true
  local policiesBounded = true
  for _, policy in ipairs(loadoutPolicies) do
    if type(policy.upperBound) ~= "function" then policiesBounded = false end
  end
  for _, policy in ipairs(preferencePolicies) do
    if type(policy.upperBound) ~= "function" then policiesBounded = false end
  end

  local remainingGroupsByIndex
  local function policyUpperBound(index, chosen, additions, score)
    if not policiesBounded then return nil end
    if not hasLoadoutPolicies and not hasPreferencePolicies then return 0 end
    local partial = {
      assignments = chosen,
      additions = additions,
      score = score,
      summaries = summarizeChosen(chosen),
    }
    local bound = 0
    for _, policy in ipairs(loadoutPolicies) do
      bound = bound + (tonumber(policy.upperBound(partial, remainingGroupsByIndex[index], context)) or 0)
    end
    for _, policy in ipairs(preferencePolicies) do
      bound = bound + (tonumber(policy.upperBound(partial, remainingGroupsByIndex[index], context)) or 0)
    end
    return bound
  end

  -- maxRemainingScore[i] = best possible total from group i through the
  -- last group, inclusive, ignoring cross-group legality AND policy
  -- validity (an upper bound on score alone -- legality and a validity
  -- preference can only ever remove or de-prioritize options, never add
  -- score value).
  local maxRemainingScore = {}
  maxRemainingScore[n + 1] = 0
  for i = n, 1, -1 do
    local bestOfGroup = 0
    for _, assignment in ipairs(ordered[i].frontier) do
      if assignment.score > bestOfGroup then bestOfGroup = assignment.score end
    end
    maxRemainingScore[i] = maxRemainingScore[i + 1] + bestOfGroup
  end

  -- minRemainingInvalid[i] = the fewest policy-invalid assignments group i
  -- through the last group could POSSIBLY contribute, ignoring cross-group
  -- legality -- 0 if a group has any policy-valid entry at all (it MIGHT
  -- be satisfiable without any invalid fallback), 1 if literally every
  -- entry in its frontier is invalid (it is GUARANTEED to contribute at
  -- least one, since no valid entry exists to pick even in isolation).
  -- This is an optimistic (never-too-high) lower bound in exactly the
  -- same sense maxRemainingScore is an optimistic upper bound: real
  -- cross-group uniqueness conflicts can only force MORE invalid usage
  -- than this, never less.
  local minRemainingInvalid = {}
  minRemainingInvalid[n + 1] = 0
  for i = n, 1, -1 do
    local groupMinInvalid = 1
    for _, assignment in ipairs(ordered[i].frontier) do
      if invalidCost(assignment) == 0 then
        groupMinInvalid = 0
        break
      end
    end
    minRemainingInvalid[i] = minRemainingInvalid[i + 1] + groupMinInvalid
  end

  local maxRemainingFilled = {}
  if preferFilledSlots then
    maxRemainingFilled[n + 1] = 0
    for i = n, 1, -1 do
      local bestFilled = 0
      for _, assignment in ipairs(ordered[i].frontier) do
        local filled = filledCount(assignment)
        if filled > bestFilled then bestFilled = filled end
      end
      maxRemainingFilled[i] = maxRemainingFilled[i + 1] + bestFilled
    end
  end

  -- See this file's header: the removal set for baseline uniqueness must
  -- be the full union of every optimized group's slots, computed once,
  -- not just the slots of groups already visited in a given branch.
  local allSlots = {}
  for _, group in ipairs(ordered) do appendAll(allSlots, group.slots) end
  local uniqueSearchState = buildUniqueSearchState(loadoutState, allSlots)

  remainingGroupsByIndex = {}
  remainingGroupsByIndex[n + 1] = {}
  for i = n, 1, -1 do
    local suffix = { ordered[i] }
    appendAll(suffix, remainingGroupsByIndex[i + 1])
    remainingGroupsByIndex[i] = suffix
  end

  for _, group in ipairs(ordered) do
    local prepared = {}
    for i, assignment in ipairs(group.frontier) do
      prepared[i] = {
        assignment = assignment,
        additions = nonNilPicks(assignment),
        invalid = invalidCost(assignment),
        filled = filledCount(assignment),
      }
    end
    group.preparedFrontier = prepared
  end

  local bestCombination, bestScore, bestInvalidCount, bestFilledCount = nil, -math.huge, math.huge, -math.huge

  local function search(index, accumulatedAdditions, accumulatedScore, accumulatedInvalid, accumulatedFilled, chosen)
    if perf then perf:Add("optimizer.nodes_visited", 1) end
    -- Branch-and-bound (doc 24.3), lexicographic: a branch that can't
    -- possibly reach as FEW invalid assignments as the current best is
    -- dead regardless of score. One that CAN reach fewer must always be
    -- explored, since any strictly lower invalid count wins outright no
    -- matter the score -- the score bound only applies once tied on the
    -- best-achievable invalid count.
    local bestPossibleInvalid = accumulatedInvalid + (minRemainingInvalid[index] or 0)
    if bestPossibleInvalid > bestInvalidCount then
      if perf then perf:Add("optimizer.invalid_count_prunes", 1) end
      return
    end
    local bestPossibleFilled = preferFilledSlots and (accumulatedFilled + (maxRemainingFilled[index] or 0)) or 0
    if preferFilledSlots and bestPossibleInvalid == bestInvalidCount and bestPossibleFilled < bestFilledCount then
      if perf then perf:Add("optimizer.filled_slot_prunes", 1) end
      return
    end
    local policyBound = policyUpperBound(index, chosen, accumulatedAdditions, accumulatedScore)
    if policiesBounded
        and bestPossibleInvalid == bestInvalidCount
        and (not preferFilledSlots or bestPossibleFilled == bestFilledCount)
        and accumulatedScore + (maxRemainingScore[index] or 0) + (policyBound or 0) <= bestScore then
      if perf then
        if hasLoadoutPolicies or hasPreferencePolicies then
          perf:Add("optimizer.policy_bound_prunes", 1)
        else
          perf:Add("optimizer.score_bound_prunes", 1)
        end
      end
      return
    end

    if index > n then
      if perf then perf:Add("optimizer.complete_leaves", 1) end
      local allowed, finalScore = applyLoadoutPolicies(chosen, accumulatedAdditions, accumulatedScore, context, loadoutPolicies)
      if allowed then
        local loadout = {
          assignments = chosen,
          additions = accumulatedAdditions,
          score = finalScore,
          summaries = summarizeChosen(chosen),
        }
        finalScore = applyPreferencePolicies(loadout, finalScore, context, preferencePolicies)
      end
      if allowed and (accumulatedInvalid < bestInvalidCount
          or (preferFilledSlots and accumulatedInvalid == bestInvalidCount and accumulatedFilled > bestFilledCount)
          or (accumulatedInvalid == bestInvalidCount
            and (not preferFilledSlots or accumulatedFilled == bestFilledCount)
            and finalScore > bestScore)) then
        bestInvalidCount = accumulatedInvalid
        bestFilledCount = accumulatedFilled
        bestScore = finalScore
        bestCombination = {}
        for groupId, assignment in pairs(chosen) do bestCombination[groupId] = assignment end
      end
      return
    end

    local group = ordered[index]
    for _, entry in ipairs(group.preparedFrontier) do
      local assignment = entry.assignment
      local uniqueChanges = pushUniqueness(uniqueSearchState, assignment)
      if uniqueChanges then
        local previousAdditionCount = #accumulatedAdditions
        appendAll(accumulatedAdditions, entry.additions)

        chosen[group.id] = assignment
        search(index + 1, accumulatedAdditions, accumulatedScore + assignment.score,
          accumulatedInvalid + entry.invalid, accumulatedFilled + entry.filled, chosen)
        chosen[group.id] = nil
        for i = #accumulatedAdditions, previousAdditionCount + 1, -1 do
          accumulatedAdditions[i] = nil
        end
        popUniqueness(uniqueSearchState, uniqueChanges)
      elseif perf then
        perf:Add("optimizer.uniqueness_prunes", 1)
      end
    end
  end

  search(1, {}, 0, 0, 0, {})

  if not bestCombination then return nil, nil end
  return bestCombination, bestScore
end
