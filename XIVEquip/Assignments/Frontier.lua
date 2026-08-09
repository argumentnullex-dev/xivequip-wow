-- Assignments/Frontier.lua
-- Safe dominance pruning (doc section 23): an assignment may be discarded
-- when another assignment already in the same group's frontier is no
-- worse in every dimension that can matter to the remaining optimization,
-- with at least one strict improvement.
--
-- Doc section 23 lists four dominance dimensions: score, constrained
-- unique usage, "relevant set counts", and "required/target satisfaction".
-- Phase 4 implemented score/uniqueness/policy-validity. Phase 5 adds the
-- structured set-count and target/required flag dimensions that candidate
-- and preference policies can now attach to assignments.
local addonName, XIVEquip = ...
XIVEquip.Assignments = XIVEquip.Assignments or {}
local Assignments = XIVEquip.Assignments

local Frontier = {}
Assignments.Frontier = Frontier

-- UniqueUsage(assignment) -> {[uniquenessKey] = {count = N, limit = L}}
-- Summarizes, per uniqueness category this assignment's non-empty picks
-- touch, how many units it consumes AND the tightest limit any of its own
-- picks declares for that key (mirroring LoadoutState:CheckAssignment's
-- own per-addition min-limit math). This is ONLY for comparing two
-- assignments against each other during pruning -- the actual legality of
-- any real combination is always decided by LoadoutState:CheckAssignment
-- against the true seeded state, never by this summary.
--
-- Both count AND limit matter for a safe comparison, not just count: two
-- assignments can consume the same single unit of a key while declaring
-- DIFFERENT limits for it (e.g. one candidate's uniqueness.limit is 1,
-- another's is 2 for the "same" key) -- whichever one is kept determines
-- how much room is left for some OTHER group to also use that key later.
function Frontier.UniqueUsage(assignment)
  local usage = {}
  for _, candidate in pairs(assignment.picks or {}) do
    local uniqueness = candidate and candidate.uniqueness
    local key = uniqueness and uniqueness.key
    if key then
      local limit = tonumber(uniqueness.limit) or 1
      local entry = usage[key]
      if entry then
        entry.count = entry.count + 1
        entry.limit = math.min(entry.limit, limit)
      else
        usage[key] = { count = 1, limit = limit }
      end
    end
  end
  return usage
end

local function numericMapNoWorse(aMap, bMap)
  aMap, bMap = aMap or {}, bMap or {}
  local allKeys = {}
  for key in pairs(aMap) do allKeys[key] = true end
  for key in pairs(bMap) do allKeys[key] = true end

  local strict = false
  for key in pairs(allKeys) do
    local aValue, bValue = tonumber(aMap[key]) or 0, tonumber(bMap[key]) or 0
    if aValue < bValue then return false, false end
    if aValue > bValue then strict = true end
  end
  return true, strict
end

local function flagMapNoWorse(aMap, bMap)
  aMap, bMap = aMap or {}, bMap or {}
  local allKeys = {}
  for key in pairs(aMap) do allKeys[key] = true end
  for key in pairs(bMap) do allKeys[key] = true end

  local strict = false
  for key in pairs(allKeys) do
    local aValue, bValue = aMap[key] == true, bMap[key] == true
    if bValue and not aValue then return false, false end
    if aValue and not bValue then strict = true end
  end
  return true, strict
end

local function filledCount(assignment)
  if type(assignment.filledCount) == "number" then return assignment.filledCount end
  return nil
end

-- Dominates(a, b) -> bool
-- `a` dominates `b` when a is at least as good on every dimension that
-- matters and strictly better on at least one:
--   - for every uniqueness key either touches, a consumes no more of it
--     AND a's own declared limit for it is no more restrictive (>=) --
--     checked FIRST and unconditionally, ahead of policy validity or
--     score, because usage is the only dimension that can affect whether
--     some OTHER group's choice remains reachable (see below).
--   - policy validity: given safe usage, a policy-VALID `a` beats an
--     invalid `b` outright, regardless of score -- an invalid `a` never
--     dominates a valid `b` no matter how it compares otherwise.
--   - given equal validity and safe usage: a.score >= b.score
--   - strictly better: a valid `a` vs. an invalid `b`, OR (equal
--     validity) a higher score, OR strictly less usage of some key, OR a
--     strictly less restrictive (higher) limit on some key
-- The limit comparison exists because count alone isn't a safe proxy: if
-- `a` and `b` both consume one unit of key K but `a` declares a tighter
-- limit (say 1) than `b` does (say 2), replacing `b` with `a` can turn an
-- otherwise-legal combination illegal the moment some OTHER group also
-- wants a unit of K -- b's laxer limit would have allowed it, a's
-- wouldn't. A key either side doesn't touch at all counts as
-- {count=0, limit=math.huge} for that side -- not touching a key is never
-- restrictive.
-- Both usage maps' keys must be checked, not just b's: if `a` consumes a
-- category `b` never touches at all, that's a real extra cost `a` carries
-- (it could block some other group's choice that `b` wouldn't have) --
-- only scanning b's keys would miss exactly that case.
--
-- assignment.policyValid is nil for every assignment that never went
-- through Paired.Evaluate's isCurrentState path (i.e. every ordinary
-- solver-proposed assignment, and every hand-built assignment record in
-- tests) -- nil is treated as valid, matching those assignments' actual
-- status (an ordinary Evaluate call already rejects anything policy-
-- invalid outright, so anything that reaches here without the field set
-- necessarily passed). Only Paired.lua's isCurrentState fallback ever
-- sets it to a literal `false`: a current loadout state that a registered
-- assignment-phase policy actively rejects (e.g. leftover gear illegal
-- under a spec change), as opposed to merely a partially-empty state
-- policies happen not to have an opinion on.
--
-- Policy validity must NOT act as an unconditional trump ahead of usage:
-- whether a policy-valid replacement is actually usable can depend on
-- what OTHER groups need. A policy-invalid current weapon that touches no
-- uniqueness category at all, sitting alongside a policy-valid
-- replacement that DOES consume a category some other group's own
-- current state also needs, is a real counterexample -- pruning the
-- invalid one there could make the only globally feasible complete
-- loadout unreachable (the invalid weapon plus that other group's current
-- state), even though a naive "valid beats invalid" rule would have
-- discarded it for scoring lower on validity alone. Gating the validity
-- comparison behind the SAME safe-usage check already used for score
-- means a valid assignment only ever erases an invalid one when doing so
-- can never cost some other group anything -- exactly the same
-- "may only prune when it cannot make some globally feasible solution
-- unreachable" rule this whole module exists to enforce. The
-- whole-loadout optimizer itself is what actually determines feasibility
-- across groups (via LoadoutState:CheckAssignment) -- this function only
-- ever needs to avoid discarding something that might still be needed.
function Frontier.Dominates(a, b)
  local aValid, bValid = a.policyValid ~= false, b.policyValid ~= false
  if not aValid and bValid then return false end

  local aUsage, bUsage = Frontier.UniqueUsage(a), Frontier.UniqueUsage(b)

  local allKeys = {}
  for key in pairs(aUsage) do allKeys[key] = true end
  for key in pairs(bUsage) do allKeys[key] = true end

  local usageStrictlyBetter = false
  for key in pairs(allKeys) do
    local aEntry = aUsage[key] or { count = 0, limit = math.huge }
    local bEntry = bUsage[key] or { count = 0, limit = math.huge }

    if aEntry.count > bEntry.count then return false end
    if aEntry.limit < bEntry.limit then return false end

    if aEntry.count < bEntry.count then usageStrictlyBetter = true end
    if aEntry.limit > bEntry.limit then usageStrictlyBetter = true end
  end

  local setNoWorse, setStrict = numericMapNoWorse(a.setCounts, b.setCounts)
  if not setNoWorse then return false end

  local targetNoWorse, targetStrict = flagMapNoWorse(a.targetFlags, b.targetFlags)
  if not targetNoWorse then return false end

  local requiredNoWorse, requiredStrict = flagMapNoWorse(a.requiredFlags, b.requiredFlags)
  if not requiredNoWorse then return false end

  if aValid and not bValid then return true end

  local aFilled, bFilled = filledCount(a), filledCount(b)
  if aFilled and bFilled and aFilled < bFilled then return false end

  if a.score < b.score then return false end
  return usageStrictlyBetter or setStrict or targetStrict or requiredStrict
      or (aFilled and bFilled and aFilled > bFilled) or a.score > b.score
end

-- Prune(assignments) -> survivors
-- Keeps only assignments not dominated by any other assignment in the
-- list. O(n^2) -- frontiers at this scale (single-digit to low tens of
-- legal pairings per group) make anything more elaborate unnecessary.
function Frontier.Prune(assignments)
  local survivors = {}
  for i, candidate in ipairs(assignments) do
    local dominated = false
    for j, other in ipairs(assignments) do
      if i ~= j and Frontier.Dominates(other, candidate) then
        dominated = true
        break
      end
    end
    if not dominated then survivors[#survivors + 1] = candidate end
  end
  return survivors
end
