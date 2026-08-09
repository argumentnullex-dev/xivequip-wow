-- tests/specs/assignment_paired_spec.lua
-- Direct unit tests of Assignments/Paired.lua's generic enumerator against
-- small hand-built candidates -- decoupled from XIVWeights/EvaluationContext
-- (a fake `score` function and a minimal `context.policies.assignment`
-- table stand in for them), so these tests isolate the solver's own
-- dedup/uniqueness/policy-veto/enumeration logic.

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
  -- LoadAssignments also loads Policies/Assignment/WeaponHandLegality.lua,
  -- which self-registers via XIVEquip:RegisterPolicy at load time -- so
  -- PublicAPI/Policies.lua must already be loaded, even though these
  -- particular tests only exercise Paired.lua's own generic logic (a
  -- synthetic "test-group" groupId, not the real weapon policy).
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  return addon
end

local function item(physicalID, score, uniqueKey, uniqueLimit)
  return { physicalID = physicalID, testScore = score, uniqueness = { key = uniqueKey, limit = uniqueLimit } }
end

local function fakeScore(candidate) return candidate.testScore or 0 end

-- "Higher score always wins" comparator -- the simplest possible plug-in.
local function byScore(candidate, current)
  return candidate.score > current.score
end

local function baseSpec(addon, overrides)
  local spec = {
    roles = { "first", "second" },
    slots = { first = 11, second = 12 },
    groupId = "test-group",
    context = { policies = { assignment = {} } },
    loadoutState = addon.Assignments.LoadoutState.New(),
    score = fakeScore,
    compare = byScore,
  }
  for k, v in pairs(overrides or {}) do spec[k] = v end
  return spec
end

test("picks the highest-scoring legal pair from the candidate pool", function()
  local addon = newAddon()
  local a, b = item("a", 10), item("b", 20)

  local best = addon.Assignments.Paired.Solve(baseSpec(addon, { candidates = { a, b } }))

  A.truthy(best.picks.first.physicalID == "b" or best.picks.second.physicalID == "b",
    "the higher-scoring item should be placed in one of the two roles")
  A.equal(best.score, 30)
end)

test("the same physical item cannot fill both roles, even as the only candidate", function()
  local addon = newAddon()
  local a = item("dup", 10)

  -- Only one candidate exists, and it can't legally fill both roles at
  -- once -- with `second` allowed to sit empty, the only legal assignment
  -- is (first=a, second=empty), never (first=a, second=a).
  local best, allLegal = addon.Assignments.Paired.Solve(baseSpec(addon, {
    candidates = { a },
    emptyAllowed = { second = true },
  }))

  A.truthy(best, "leaving second empty should be a legal fallback")
  A.equal(best.picks.first.physicalID, "dup")
  A.falsy(best.picks.second, "the same physical item must not also fill the second role")
  for _, assignment in ipairs(allLegal) do
    A.falsy(assignment.picks.first and assignment.picks.second,
      "no legal assignment should have placed the single physical item in both roles")
  end
end)

test("two distinct physical copies with the same itemID may fill both roles when not unique", function()
  local addon = newAddon()
  local a = item("copy-a", 10)
  local b = item("copy-b", 20)
  a.itemID = 9001
  b.itemID = 9001

  local best = addon.Assignments.Paired.Solve(baseSpec(addon, { candidates = { a, b } }))

  A.truthy(best)
  A.truthy(best.picks.first)
  A.truthy(best.picks.second)
  A.equal(best.picks.first.itemID, 9001)
  A.equal(best.picks.second.itemID, 9001)
  A.truthy(best.picks.first.physicalID ~= best.picks.second.physicalID)
end)

test("a candidate with no physicalID or guid still cannot fill both roles", function()
  local addon = newAddon()
  -- CandidateNormalizer.FromLink copies source.guid/source.physicalID
  -- verbatim, and `source` is caller-optional, so a real candidate can
  -- have neither. A dedup check that falls back to `physicalID or guid`
  -- and compares that to nil would treat two such (nil, nil) identities
  -- as equal only by coincidence -- but the actual bug this guards
  -- against is worse: since this is the ONLY candidate, Solve() puts the
  -- very same object into both role pools, so the dangerous case is the
  -- object being compared against ITSELF.
  local noIdentity = { testScore = 10 }

  local best, allLegal = addon.Assignments.Paired.Solve(baseSpec(addon, {
    candidates = { noIdentity },
    emptyAllowed = { second = true },
  }))

  A.truthy(best, "leaving second empty should be a legal fallback")
  A.falsy(best.picks.second, "an identity-less candidate must not also fill the second role")
  for _, assignment in ipairs(allLegal) do
    A.falsy(assignment.picks.first and assignment.picks.second,
      "no legal assignment should place the same identity-less candidate in both roles")
  end
end)

test("a uniqueness-limit violation is rejected via LoadoutState", function()
  local addon = newAddon()
  local a = item("a", 10, "item:1", 1)
  local b = item("b", 20, "item:1", 1)

  -- Neither role may be empty here, and the only two real candidates
  -- share a limit-1 uniqueness key -- there is no legal way to fill both
  -- roles at once, so Solve should report no legal assignment at all.
  local best = addon.Assignments.Paired.Solve(baseSpec(addon, { candidates = { a, b } }))

  A.falsy(best, "two copies of a limit-1 unique item should never both be picked")
end)

test("an assignment-phase policy scoped to this group can veto a combination", function()
  local addon = newAddon()
  local a, b = item("a", 10), item("b", 20)
  local policy = {
    id = "Test.veto_b_in_second",
    groups = { "test-group" },
    apply = function(assignment) return assignment.picks.second ~= b end,
  }

  local best = addon.Assignments.Paired.Solve(baseSpec(addon, {
    candidates = { a, b },
    context = { policies = { assignment = { policy } } },
  }))

  A.falsy(best.picks.second == b, "the policy veto should prevent b from ever landing in the second role")
end)

test("an assignment-phase policy scoped to a different group does not apply here", function()
  local addon = newAddon()
  local a, b = item("a", 10), item("b", 20)
  local policy = {
    id = "Test.veto_everything_else",
    groups = { "some-other-group" },
    apply = function() return false end,
  }

  local best = addon.Assignments.Paired.Solve(baseSpec(addon, {
    candidates = { a, b },
    context = { policies = { assignment = { policy } } },
  }))

  A.truthy(best, "a policy scoped to a different groupId should not veto this group's assignments")
end)

test("candidate eligibility policies exclude proposed picks before score comparison", function()
  local addon = newAddon()
  local highExcluded, lowAllowed = item("excluded", 1000), item("allowed", 10)
  local policy = {
    id = "Test.exclude_high",
    groups = { "test-group" },
    apply = function(candidate)
      if candidate == highExcluded then return { allow = false, reason = "excluded" } end
    end,
  }

  local best = addon.Assignments.Paired.Solve(baseSpec(addon, {
    candidates = { highExcluded, lowAllowed },
    emptyAllowed = { second = true },
    context = { policies = { candidate = { policy }, assignment = {}, preference = {} } },
  }))

  A.truthy(best)
  A.equal(best.picks.first, lowAllowed)
  A.falsy(best.picks.second, "the excluded high-score candidate should not appear in either role")
end)

test("candidate policies adjust paired assignment score and summary state", function()
  local addon = newAddon()
  local a, b = item("a", 10), item("b", 20)
  local policy = {
    id = "Test.prefer_a",
    groups = { "test-group" },
    apply = function(candidate)
      if candidate == a then
        return {
          scoreAdjustment = 50,
          setCounts = { tier = 1 },
          targetFlags = { wanted = true },
          requiredFlags = { locked = true },
        }
      end
    end,
  }

  local assignment = addon.Assignments.Paired.Evaluate({
    roles = { "first", "second" }, slots = { first = 11, second = 12 }, groupId = "test-group",
    context = { policies = { candidate = { policy }, assignment = {}, preference = {} } },
    loadoutState = addon.Assignments.LoadoutState.New(),
    score = fakeScore,
    picks = { first = a, second = b },
  })

  A.equal(assignment.baseScore, 30)
  A.equal(assignment.scoreAdjustment, 50)
  A.equal(assignment.score, 80)
  A.equal(assignment.setCounts.tier, 1)
  A.truthy(assignment.targetFlags.wanted)
  A.truthy(assignment.requiredFlags.locked)
end)

test("an ineligible literal current state remains representable as policy-invalid", function()
  local addon = newAddon()
  local current = item("current", 100)
  local policy = {
    id = "Test.exclude_current",
    groups = { "test-group" },
    apply = function(candidate)
      if candidate == current then return { allow = false, reason = "currently invalid" } end
    end,
  }

  local assignment = addon.Assignments.Paired.Evaluate({
    roles = { "first", "second" }, slots = { first = 11, second = 12 }, groupId = "test-group",
    context = { policies = { candidate = { policy }, assignment = {}, preference = {} } },
    loadoutState = addon.Assignments.LoadoutState.New(),
    score = fakeScore,
    picks = { first = current, second = nil },
    isCurrentState = true,
  })

  A.truthy(assignment, "frontiers need the literal current state even when a policy now rejects it")
  A.falsy(assignment.policyValid)
  A.equal(assignment.reasons[1], "currently invalid")
end)

test("Groups.Rings.Solve can replace a higher-scoring policy-invalid current item", function()
  local addon = newAddon()
  local current = item("current-invalid", 100)
  local replacement = item("replacement-valid", 90)
  local policy = {
    id = "Test.exclude_current",
    groups = { "rings" },
    apply = function(candidate)
      if candidate == current then return { allow = false, reason = "currently invalid" } end
    end,
  }
  local context = { policies = { candidate = { policy }, assignment = {}, preference = {} } }
  local loadoutState = addon.Assignments.LoadoutState.New()
  addon.Evaluation.CandidateEvaluator.Score = fakeScore

  local best = addon.Assignments.Groups.Rings.Solve({ replacement }, context, loadoutState, current, nil)

  A.truthy(best)
  A.equal(best.picks.first, replacement)
end)

test("a role that disallows empty never receives a nil pick", function()
  local addon = newAddon()
  local a = item("a", 10)

  local best = addon.Assignments.Paired.Solve(baseSpec(addon, {
    candidates = { a },
    emptyAllowed = { second = true }, -- first may NOT be empty
  }))

  A.truthy(best.picks.first, "the role with emptyAllowed unset should never be left empty when a legal candidate exists")
end)

test("both roles empty is never chosen as the best assignment, even when nothing else is legal", function()
  local addon = newAddon()
  -- A policy that vetoes every assignment except (empty, empty). If the
  -- both-empty exclusion didn't run *before* assignment-phase policies
  -- (mirrors Jewelry.lua's findBestLoadout's `not (first.isEmpty and
  -- second.isEmpty)` guard, which is a hard exclusion applied ahead of
  -- everything else), this policy would "approve" it and Solve could
  -- return an assignment that clears both slots for no gain.
  local a, b = item("a", 10), item("b", 20)
  local onlyApproveBothEmpty = {
    id = "Test.only_approve_both_empty",
    groups = { "test-group" },
    apply = function(assignment) return assignment.picks.first == nil and assignment.picks.second == nil end,
  }

  local best = addon.Assignments.Paired.Solve(baseSpec(addon, {
    candidates = { a, b },
    emptyAllowed = { first = true, second = true },
    context = { policies = { assignment = { onlyApproveBothEmpty } } },
  }))

  A.falsy(best, "both-empty must never be chosen, even when it's the only thing a policy would approve")
end)

test("the comparator is pluggable -- a reversed comparator picks the lower score", function()
  local addon = newAddon()
  local a, b = item("a", 10), item("b", 20)

  -- With `second` allowed empty, legal totals include 30 (both filled, in
  -- either order), 20 (b alone), and 10 (a alone) -- giving the reversed
  -- comparator a genuinely lower-scoring option to prefer.
  local lowestWins = function(candidate, current) return candidate.score < current.score end
  local best = addon.Assignments.Paired.Solve(baseSpec(addon, {
    candidates = { a, b },
    emptyAllowed = { second = true },
    compare = lowestWins,
  }))

  A.equal(best.score, 10, "a comparator preferring the lower score should change which assignment wins")
end)

test("Evaluate scores one given picks map directly without searching", function()
  local addon = newAddon()
  local a, b = item("a", 10), item("b", 20)

  local assignment = addon.Assignments.Paired.Evaluate({
    roles = { "first", "second" }, slots = { first = 11, second = 12 }, groupId = "test-group",
    context = { policies = { assignment = {} } }, loadoutState = addon.Assignments.LoadoutState.New(),
    score = fakeScore, picks = { first = a, second = b },
  })

  A.equal(assignment.score, 30)
  A.equal(assignment.scores.first, 10)
  A.equal(assignment.scores.second, 20)
end)

return tests
