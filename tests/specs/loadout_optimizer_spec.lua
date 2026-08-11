-- tests/specs/loadout_optimizer_spec.lua
-- Optimization/LoadoutOptimizer.lua: exact whole-loadout combination
-- across multiple groups' dominance-pruned frontiers (doc section 24).

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")
local FakeWorld = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "fake_world.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function newAddon()
  local addon = {}
  -- LoadAssignments also loads Policies/Assignment/WeaponHandLegality.lua,
  -- which self-registers via XIVEquip:RegisterPolicy at load time -- so
  -- PublicAPI/Policies.lua must already be loaded.
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)
  return addon
end

local function candidate(uniqueKey, uniqueLimit)
  return { uniqueness = { key = uniqueKey, limit = uniqueLimit } }
end

local function assignment(score, picks)
  return { score = score, picks = picks or {} }
end

-- Shared test-context builder for the FakeWorld-backed integration tests
-- below (real Groups.*.Frontier + real CandidateEvaluator scoring, not
-- hand-built assignment records). Arms Warrior is two-handed-only with no
-- offhand requirement, which keeps WeaponHandLegality out of the way for
-- tests that aren't specifically exercising weapon-hand rules.
local function weaponsTestContext(addon)
  local scale = addon.XIVWeights.NewScale({
    weights = addon.XIVWeights.Normalizer.Normalize({ strength = 1 }),
  })
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local runtime = {
    UnitClass = function() return "Player", "WARRIOR", 1 end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 71, "Arms" end, -- two-handed only, no offhand
    UnitLevel = function() return 80 end,
    IsDualWielding = function() return false end,
    ResolveWeights = function() return scale end,
  }
  return addon.Evaluation.ContextBuilder.BuildContext(resolved, runtime)
end

test("prefers a globally legal combination over two locally-best assignments that conflict", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  -- Group A's best (100) and Group B's best (90) both consume the same
  -- limit-1 "legendary" key -- illegal together. Each group's second
  -- option avoids it. The best LEGAL total is 170 (100+70 or 80+90), not
  -- the naive-but-illegal 190.
  local groups = {
    {
      id = "A", slots = { 1 },
      frontier = {
        assignment(100, { only = candidate("legendary", 1) }),
        assignment(80, {}),
      },
    },
    {
      id = "B", slots = { 2 },
      frontier = {
        assignment(90, { only = candidate("legendary", 1) }),
        assignment(70, {}),
      },
    },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.equal(score, 170)
  A.truthy(combination.A and combination.B)
  A.falsy(combination.A.score == 100 and combination.B.score == 90, "the illegal 100+90 pair must never be chosen")
end)

test("a clearly dominant early group's best is still correctly included in the final combination", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  -- Group A's best (1000) alone already exceeds any combination that
  -- skips it, so the optimistic bound should prune most of the tree --
  -- correctness (not just speed) is what this test actually checks.
  local groups = {
    {
      id = "A", slots = { 1 },
      frontier = {
        assignment(1000, {}),
        assignment(1, {}),
      },
    },
    {
      id = "B", slots = { 2 },
      frontier = {
        assignment(50, {}),
        assignment(40, {}),
      },
    },
    {
      id = "C", slots = { 3 },
      frontier = {
        assignment(30, {}),
        assignment(20, {}),
      },
    },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.equal(score, 1080)
  A.equal(combination.A.score, 1000)
  A.equal(combination.B.score, 50)
  A.equal(combination.C.score, 30)
end)

test("returns nil when a group's frontier is empty -- no complete combination exists", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  local groups = {
    { id = "A", slots = { 1 }, frontier = { assignment(10, {}) } },
    { id = "B", slots = { 2 }, frontier = {} },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.falsy(combination)
  A.falsy(score)
end)

test("prefers a fully policy-valid complete combination over a higher-scoring policy-invalid one", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  local invalid = assignment(200, {})
  invalid.policyValid = false
  local valid = assignment(120, { only = candidate("cat", 1) })

  local groups = {
    { id = "A", slots = { 1 }, frontier = { invalid, valid } },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.equal(combination.A, valid, "a fully valid combination exists, so it must be preferred over raw score")
  A.equal(score, 120)
end)

test("falls back to a policy-invalid assignment when no fully policy-valid complete combination exists", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  local invalidNoUsage = assignment(200, {})
  invalidNoUsage.policyValid = false
  local validUsesX = assignment(120, { only = candidate("X", 1) })

  local groups = {
    { id = "A", slots = { 1 }, frontier = { invalidNoUsage, validUsesX } },
    -- B has no alternative and its fixed use of X collides with A's
    -- valid option, so no fully policy-valid complete combination exists.
    { id = "B", slots = { 2 }, frontier = { assignment(80, { only = candidate("X", 1) }) } },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.equal(combination.A, invalidNoUsage, "the invalid fallback is the only way to reach a complete legal combination")
  A.equal(score, 200 + 80)
end)

-- The finding this covers: once ANY invalid fallback is unavoidable
-- somewhere in the loadout, a naive "fall back to plain score
-- maximization everywhere" objective stops caring about validity
-- entirely -- letting a SEPARATE, otherwise-avoidable invalid fallback in
-- a completely different group win purely on score. The objective has to
-- be truly lexicographic across the WHOLE loadout at once (minimize total
-- invalid-assignment count, then maximize score among ties), not merely
-- "prefer zero invalid, else give up on preferring anything."
test("minimizes the total number of policy-invalid assignments across the whole loadout, not just within one group", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  -- Group A has no valid option at all -- one invalid assignment here is
  -- unavoidable in any complete combination.
  local aOnlyOption = assignment(50, {})
  aOnlyOption.policyValid = false

  -- Group B has both an invalid option that outscores its valid one, and
  -- a valid option -- neither conflicts with anything, so nothing forces
  -- B's invalid option to be used.
  local bInvalid = assignment(200, {})
  bInvalid.policyValid = false
  local bValid = assignment(120, {})

  local groups = {
    { id = "A", slots = { 1 }, frontier = { aOnlyOption } },
    { id = "B", slots = { 2 }, frontier = { bInvalid, bValid } },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.equal(combination.A, aOnlyOption, "A's invalid fallback is unavoidable")
  A.equal(combination.B, bValid,
    "B must NOT also use its invalid option just because a total-score-only search would otherwise prefer it")
  A.equal(score, 50 + 120, "must not be 50 + 200 -- that uses an avoidable second invalid assignment")
end)

test("a unique-equipped slot's occupant can be handed off to another group later in the search order", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()
  -- Slot 2 is currently equipped with a limit-1 "legendary" item.
  loadoutState:SeedFromEquipped({ [2] = candidate("legendary", 1) })

  -- Group A (slot 1, frontier size 1 -- sorted and visited BEFORE B)
  -- wants a NEW copy of "legendary". Group B (slot 2, frontier size 2)
  -- will replace the currently-equipped legendary with something plain.
  -- The complete loadout is legal (the old legendary in slot 2 is gone,
  -- the new one is in slot 1) -- but if the removal set used during A's
  -- prefix check only contained A's own slot (1), the still-uncounted
  -- original legendary in slot 2 would make A's new one look like a
  -- second, illegal copy, and this whole branch would incorrectly die
  -- before B ever gets the chance to give its slot up.
  local groups = {
    { id = "A", slots = { 1 }, frontier = { assignment(50, { only = candidate("legendary", 1) }) } },
    { id = "B", slots = { 2 }, frontier = { assignment(80, {}), assignment(5, {}) } },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.truthy(combination, "the handoff is legal and must be found, not rejected")
  A.equal(score, 130)
  A.equal(combination.A.score, 50)
  A.equal(combination.B.score, 80)
end)

test("a retained occupied slot still consumes uniqueness capacity", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()
  local currentRing = candidate("category:kept", 1)
  local conflictingTrinket = candidate("category:kept", 1)
  loadoutState:SeedFromEquipped({ [11] = currentRing })

  local groups = {
    { id = "rings", slots = { 11, 12 }, frontier = { assignment(10, { first = currentRing }) } },
    {
      id = "trinkets",
      slots = { 13, 14 },
      frontier = {
        assignment(50, { first = conflictingTrinket }),
        assignment(0, {}),
      },
    },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.truthy(combination)
  A.equal(combination.rings.picks.first, currentRing)
  A.equal(combination.trinkets.score, 0, "the conflicting trinket must not fit while the ring remains equipped")
  A.equal(score, 10)
end)

test("optimizer maintains uniqueness incrementally during DFS", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()
  loadoutState:SeedFromEquipped({ [99] = candidate("legendary", 1) })
  loadoutState.CheckAssignment = function()
    error("optimizer DFS should not rebuild uniqueness through CheckAssignment")
  end
  local counters = {}

  local groups = {
    {
      id = "A",
      slots = { 1 },
      frontier = {
        assignment(100, { slot = candidate("legendary", 1) }),
        assignment(80, {}),
      },
    },
    {
      id = "B",
      slots = { 2 },
      frontier = {
        assignment(90, { slot = candidate("plain", 1) }),
      },
    },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState, {
    perf = {
      Add = function(_, key, value)
        counters[key] = (counters[key] or 0) + (value or 1)
      end,
    },
  })

  A.truthy(combination)
  A.equal(combination.A.score, 80)
  A.equal(score, 170)
  A.truthy((counters["optimizer.uniqueness_prunes"] or 0) > 0)
end)

-- Property-style exactness (doc 36.3): a small brute-force reference
-- (full cartesian product) must always agree with LoadoutOptimizer.FindBest.
--
-- CRITICAL: legality is checked exactly ONCE per complete combination, at
-- the leaf, using the full union of every group's slots as the removal
-- set -- never as a growing per-prefix check. LoadoutState:CheckAssignment
-- only provisionally removes a slot's ORIGINAL occupant when that slot is
-- in the removal set; checking a partial combination against only the
-- slots decided so far would under-remove not-yet-visited groups'
-- original occupants and could reject a combination that becomes legal
-- once every group's real final contents are known (this is exactly the
-- non-monotonicity bug this whole test file exists to catch -- an oracle
-- built the same way as the code under test wouldn't be an independent
-- check at all).
local function bruteForceBestScore(groups, loadoutState)
  local n = #groups
  local bestScore = nil

  local allSlots = {}
  for _, group in ipairs(groups) do
    for _, slotID in ipairs(group.slots) do allSlots[#allSlots + 1] = slotID end
  end

  local function nonNilPicks(a)
    local list = {}
    for _, c in pairs(a.picks or {}) do if c then list[#list + 1] = c end end
    return list
  end

  local function recurse(index, additions, score)
    if index > n then
      if loadoutState:CheckAssignment(additions, allSlots) then
        if not bestScore or score > bestScore then bestScore = score end
      end
      return
    end
    for _, a in ipairs(groups[index].frontier) do
      local newAdditions = {}
      for _, v in ipairs(additions) do newAdditions[#newAdditions + 1] = v end
      for _, v in ipairs(nonNilPicks(a)) do newAdditions[#newAdditions + 1] = v end
      recurse(index + 1, newAdditions, score + a.score)
    end
  end

  recurse(1, {}, 0)
  return bestScore
end

local function checkAgainstBruteForce(addon, name, groups)
  test("property: optimizer matches brute force -- " .. name, function()
    local loadoutState = addon.Assignments.LoadoutState.New()
    local expected = bruteForceBestScore(groups, loadoutState)

    local freshState = addon.Assignments.LoadoutState.New()
    local _, actual = addon.Optimization.LoadoutOptimizer.FindBest(groups, freshState)

    A.equal(actual, expected)
  end)
end

do
  local addon = newAddon()

  checkAgainstBruteForce(addon, "three groups, no uniqueness conflicts at all", {
    { id = "A", slots = { 1 }, frontier = { assignment(5, {}), assignment(9, {}), assignment(2, {}) } },
    { id = "B", slots = { 2 }, frontier = { assignment(7, {}), assignment(3, {}) } },
    { id = "C", slots = { 3 }, frontier = { assignment(4, {}), assignment(6, {}), assignment(1, {}) } },
  })

  checkAgainstBruteForce(addon, "two groups sharing a limit-1 category across every option", {
    {
      id = "A", slots = { 1 },
      frontier = {
        assignment(50, { x = candidate("shared", 1) }),
        assignment(20, { x = candidate("shared", 1) }),
        assignment(5, {}),
      },
    },
    {
      id = "B", slots = { 2 },
      frontier = {
        assignment(40, { x = candidate("shared", 1) }),
        assignment(10, {}),
      },
    },
  })

  checkAgainstBruteForce(addon, "three groups with a limit-2 category spread across all of them", {
    {
      id = "A", slots = { 1 },
      frontier = {
        assignment(30, { x = candidate("cat", 2) }),
        assignment(15, {}),
      },
    },
    {
      id = "B", slots = { 2 },
      frontier = {
        assignment(25, { x = candidate("cat", 2) }),
        assignment(12, {}),
      },
    },
    {
      id = "C", slots = { 3 },
      frontier = {
        assignment(20, { x = candidate("cat", 2) }),
        assignment(8, {}),
      },
    },
  })

  checkAgainstBruteForce(addon, "asymmetric frontier sizes with mixed independent categories", {
    {
      id = "A", slots = { 1 },
      frontier = {
        assignment(12, { x = candidate("alpha", 1) }),
        assignment(11, { x = candidate("beta", 1) }),
        assignment(9, {}),
        assignment(3, {}),
      },
    },
    {
      id = "B", slots = { 2 },
      frontier = { assignment(10, { x = candidate("alpha", 1) }), assignment(4, {}) },
    },
    {
      id = "C", slots = { 3 },
      frontier = { assignment(8, { x = candidate("beta", 1) }), assignment(2, {}) },
    },
  })
end

test("property: optimizer matches brute force with loadout policy adjustments and rejections", function()
  local addon = newAddon()
  local groups = {
    {
      id = "A", slots = { 1 },
      frontier = {
        assignment(70, {}),
        assignment(55, {}),
      },
    },
    {
      id = "B", slots = { 2 },
      frontier = {
        assignment(50, {}),
        assignment(45, {}),
      },
    },
    {
      id = "C", slots = { 3 },
      frontier = {
        assignment(40, {}),
        assignment(30, {}),
      },
    },
  }
  groups[1].frontier[2].setCounts = { tier = 1 }
  groups[2].frontier[2].setCounts = { tier = 1 }
  groups[3].frontier[2].requiredFlags = { locked = true }
  groups[3].frontier[2].targetFlags = { wishlist = true }

  local function summarize(assignments)
    local summary = { setCounts = {}, targetFlags = {}, requiredFlags = {} }
    for _, assignment in ipairs(assignments) do
      for key, value in pairs(assignment.setCounts or {}) do
        summary.setCounts[key] = (summary.setCounts[key] or 0) + value
      end
      for key, value in pairs(assignment.targetFlags or {}) do if value then summary.targetFlags[key] = true end end
      for key, value in pairs(assignment.requiredFlags or {}) do if value then summary.requiredFlags[key] = true end end
    end
    return summary
  end

  local expected = -math.huge
  for _, a in ipairs(groups[1].frontier) do
    for _, b in ipairs(groups[2].frontier) do
      for _, c in ipairs(groups[3].frontier) do
        local chosen = { a, b, c }
        local summary = summarize(chosen)
        if summary.requiredFlags.locked then
          local score = a.score + b.score + c.score
          if (summary.setCounts.tier or 0) >= 2 then score = score + 60 end
          if summary.targetFlags.wishlist then score = score + 5 end
          if score > expected then expected = score end
        end
      end
    end
  end

  local context = {
    policies = {
      loadout = {
        {
          id = "Test.require_locked_and_score_tier",
          apply = function(loadout)
            if not loadout.summaries.requiredFlags.locked then return false end
            if (loadout.summaries.setCounts.tier or 0) >= 2 then return { scoreAdjustment = 60 } end
          end,
        },
      },
      preference = {
        {
          id = "Test.wishlist_preference",
          apply = function(loadout)
            if loadout.summaries.targetFlags.wishlist then return { preferenceAdjustment = 5 } end
          end,
        },
      },
    },
  }

  local _, actual = addon.Optimization.LoadoutOptimizer.FindBest(
    groups, addon.Assignments.LoadoutState.New(), context)

  A.equal(actual, expected)
end)

-- A dedicated property case starting from a SEEDED (non-empty) loadout
-- state -- the plain property block above always starts from a fresh
-- LoadoutState.New(), which never exercises the "handing off a
-- unique-equipped slot from one group to another" scenario the dedicated
-- test above targets directly. This generalizes that same shape across
-- several seeded/frontier variations instead of just one hand-picked case.
local function checkAgainstBruteForceSeeded(addon, name, seed, groups)
  test("property: optimizer matches brute force (seeded state) -- " .. name, function()
    local reference = addon.Assignments.LoadoutState.New()
    reference:SeedFromEquipped(seed)
    local expected = bruteForceBestScore(groups, reference)

    local fresh = addon.Assignments.LoadoutState.New()
    fresh:SeedFromEquipped(seed)
    local _, actual = addon.Optimization.LoadoutOptimizer.FindBest(groups, fresh)

    A.equal(actual, expected)
  end)
end

do
  local addon = newAddon()

  checkAgainstBruteForceSeeded(addon, "equipped legendary must move from one group's slot to another's",
    { [2] = candidate("legendary", 1) },
    {
      { id = "A", slots = { 1 }, frontier = { assignment(50, { only = candidate("legendary", 1) }), assignment(5, {}) } },
      { id = "B", slots = { 2 }, frontier = { assignment(80, {}), assignment(5, {}) } },
    })

  checkAgainstBruteForceSeeded(addon, "three groups, seeded occupants scattered across all of them",
    { [1] = candidate("legendary", 1), [3] = candidate("trinketset", 2) },
    {
      {
        id = "A", slots = { 1 },
        frontier = { assignment(40, {}), assignment(20, { x = candidate("legendary", 1) }) },
      },
      {
        id = "B", slots = { 2 },
        frontier = { assignment(30, { x = candidate("legendary", 1) }), assignment(10, {}) },
      },
      {
        id = "C", slots = { 3 },
        frontier = { assignment(25, { x = candidate("trinketset", 2) }), assignment(15, {}) },
      },
    })
end

-- Finding-2-shaped adversarial case at the full Frontier.Prune ->
-- LoadoutOptimizer.FindBest pipeline (not just the isolated Dominates
-- unit tests in assignment_frontier_spec.lua): Group A has a higher-
-- scoring option with a TIGHTER declared limit on a shared key, and a
-- lower-scoring option with a LAXER limit on the same key. Group B's only
-- option needs the laxer limit to fit. If Frontier.Prune discarded
-- Group A's laxer-but-lower-scoring option (treating equal count as
-- equal usage, ignoring the limit difference), the globally best legal
-- combination would be unreachable.
test("Frontier.Prune must not discard a lower-scoring option whose laxer limit is needed elsewhere", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  local groupAOptions = {
    assignment(20, { x = candidate("cat", 1) }), -- higher score, tight limit
    assignment(10, { x = candidate("cat", 2) }), -- lower score, lax limit
  }
  local prunedA = addon.Assignments.Frontier.Prune(groupAOptions)
  A.equal(#prunedA, 2, "neither option safely dominates the other -- both must survive pruning")

  local groups = {
    { id = "A", slots = { 1 }, frontier = prunedA },
    { id = "B", slots = { 2 }, frontier = { assignment(100, { x = candidate("cat", 2) }) } },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.truthy(combination, "A's laxer-limit option plus B must be found as legal")
  A.equal(score, 110)
  A.equal(combination.A.score, 10)
  A.equal(combination.B.score, 100)
end)

-- Integration: real Groups.*.Frontier output (via CandidateNormalizer,
-- same pattern as Phase 3's generic_assignment_runner.lua) combined by the
-- optimizer, with a unique-equipped category spanning a ring and a
-- trinket, forcing a non-locally-optimal ring choice to keep the
-- globally-better trinket.
test("integration: a shared unique category spanning rings and trinkets forces a global tradeoff", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      ringHigh = { itemID = 501, equipLoc = "INVTYPE_FINGER", stats = { ITEM_MOD_STRENGTH_SHORT = 100 } },
      trinketHigh = {
        itemID = 502, equipLoc = "INVTYPE_TRINKET", stats = { ITEM_MOD_STRENGTH_SHORT = 90 },
      },
      ringLow = { itemID = 503, equipLoc = "INVTYPE_FINGER", stats = { ITEM_MOD_STRENGTH_SHORT = 40 } },
      trinketLow = { itemID = 504, equipLoc = "INVTYPE_TRINKET", stats = { ITEM_MOD_STRENGTH_SHORT = 30 } },
    },
    equipped = {},
    bags = { [0] = { "ringHigh", "trinketHigh", "ringLow", "trinketLow" } },
  })
  -- ringHigh and trinketHigh share a limit-1 unique category -- can't both
  -- be equipped.
  _G.C_Item.GetItemUniqueness = function(info)
    local id = tonumber(tostring(info):match("|Hitem:(%d+)"))
    if id == 501 or id == 502 then return 77, 1 end
    return nil, nil
  end

  local scale = addon.XIVWeights.NewScale({
    weights = addon.XIVWeights.Normalizer.Normalize({ strength = 1 }),
  })
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local runtime = {
    UnitClass = function() return "Player", "WARRIOR", 1 end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 71, "Arms" end,
    UnitLevel = function() return 80 end,
    IsDualWielding = function() return false end,
    ResolveWeights = function() return scale end,
  }
  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, runtime)

  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end

  local ringHigh, ringLow = candidateFor(501), candidateFor(503)
  local trinketHigh, trinketLow = candidateFor(502), candidateFor(504)

  trinketHigh.stats.strength = 150
  local loadoutState = addon.Assignments.LoadoutState.New()

  local ringsFrontier = addon.Assignments.Groups.Rings.Frontier({ ringHigh, ringLow }, context, loadoutState, nil, nil)
  local trinketsFrontier = addon.Assignments.Groups.Trinkets.Frontier(
    { trinketHigh, trinketLow }, context, loadoutState, nil, nil)

  local groups = {
    { id = "rings", slots = { 11, 12 }, frontier = ringsFrontier },
    { id = "trinkets", slots = { 13, 14 }, frontier = trinketsFrontier },
  }

  local combination = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  local ringPicks = combination.rings.picks
  local trinketPicks = combination.trinkets.picks
  local function hasCandidate(picks, target)
    for _, c in pairs(picks) do if c == target then return true end end
    return false
  end

  A.truthy(hasCandidate(trinketPicks, trinketHigh), "the globally better trinket should be kept")
  A.falsy(hasCandidate(ringPicks, ringHigh), "ringHigh must be given up -- it conflicts with the better trinket")
end)

-- Integration: this is the case the previous review round's finding #1
-- describes exactly -- a unique category is currently equipped in a
-- TRINKET slot, and the globally correct answer moves it to a RING
-- instead. Unlike the test above (which never seeds anything equipped, so
-- it can't distinguish "checked against this group's own slots" from
-- "checked against the true cross-group union"), this seeds a real
-- LoadoutState via SeedFromEquipped and calls the real
-- Groups.Rings.Frontier/Groups.Trinkets.Frontier -- with the allSlots
-- union both now require -- so a regression back to per-group-only
-- removalSlots would make the ring candidate vanish from its own frontier
-- before the optimizer ever runs, exactly as the review described.
test("integration: a unique item currently equipped in a trinket slot can be legally handed off to a ring", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      trinketEquipped = {
        itemID = 601, equipLoc = "INVTYPE_TRINKET", stats = { ITEM_MOD_STRENGTH_SHORT = 50 },
      },
      ringCandidate = {
        itemID = 602, equipLoc = "INVTYPE_FINGER", stats = { ITEM_MOD_STRENGTH_SHORT = 200 },
      },
      trinketReplacement = {
        itemID = 603, equipLoc = "INVTYPE_TRINKET", stats = { ITEM_MOD_STRENGTH_SHORT = 80 },
      },
    },
    equipped = {},
    bags = { [0] = { "ringCandidate", "trinketReplacement" } },
  })
  -- trinketEquipped and ringCandidate share a limit-1 unique category --
  -- can't both be equipped at once.
  _G.C_Item.GetItemUniqueness = function(info)
    local id = tonumber(tostring(info):match("|Hitem:(%d+)"))
    if id == 601 or id == 602 then return 88, 1 end
    return nil, nil
  end

  local scale = addon.XIVWeights.NewScale({
    weights = addon.XIVWeights.Normalizer.Normalize({ strength = 1 }),
  })
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local runtime = {
    UnitClass = function() return "Player", "WARRIOR", 1 end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 71, "Arms" end,
    UnitLevel = function() return 80 end,
    IsDualWielding = function() return false end,
    ResolveWeights = function() return scale end,
  }
  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, runtime)

  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end

  local trinketEquipped = candidateFor(601)
  local ringCandidate = candidateFor(602)
  local trinketReplacement = candidateFor(603)

  -- Slot 13 (first trinket slot) is currently equipped with the
  -- unique item. Nothing is currently equipped in either ring slot.
  local loadoutState = addon.Assignments.LoadoutState.New()
  loadoutState:SeedFromEquipped({ [13] = trinketEquipped })

  local allSlots = { 11, 12, 13, 14 }
  local ringsFrontier = addon.Assignments.Groups.Rings.Frontier({ ringCandidate }, context, loadoutState, nil, nil, allSlots)
  -- trinketEquipped must be in trinkets' own candidate pool for "keep
  -- what's currently there" to be a representable option at all (Frontier
  -- doesn't invent it from SeedFromEquipped -- see Weapons.Frontier's
  -- doc comment on this same point).
  -- currentA = trinketEquipped: it genuinely occupies the "first" trinket
  -- role (slot 13) right now. Frontier's synthetic empty-both fallback is
  -- gated on both roles already being empty (see frontierPaired's
  -- comment) -- passing nil here instead would be lying about the actual
  -- current state and would wrongly make "strip both trinkets" a legal
  -- synthetic option even though one is equipped.
  local trinketsFrontier = addon.Assignments.Groups.Trinkets.Frontier(
    { trinketEquipped, trinketReplacement }, context, loadoutState, trinketEquipped, nil, allSlots)

  local function hasCandidate(frontier, target)
    for _, a in ipairs(frontier) do
      for _, c in pairs(a.picks) do
        if c == target then return true end
      end
    end
    return false
  end

  A.truthy(hasCandidate(ringsFrontier, ringCandidate),
    "the ring candidate must survive frontier construction -- it only conflicts with the TRINKET's current occupant, " ..
    "not with anything in the rings group's own slots")

  local groups = {
    { id = "rings", slots = { 11, 12 }, frontier = ringsFrontier },
    { id = "trinkets", slots = { 13, 14 }, frontier = trinketsFrontier },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.truthy(combination, "a legal whole-loadout combination must exist")
  local ringPicks = combination.rings.picks
  local trinketPicks = combination.trinkets.picks

  A.truthy(hasCandidate({ combination.rings }, ringCandidate), "the ring must end up with the transferred unique item")
  A.falsy(hasCandidate({ combination.trinkets }, trinketEquipped),
    "the trinket slot must give up the unique item -- it can't keep it AND let the ring have it")
  A.truthy(hasCandidate({ combination.trinkets }, trinketReplacement), "the trinket slot should backfill with the replacement")
  A.equal(score, 200 + 80)
end)

-- Integration counterpart to the finding above: a paired group with
-- nothing currently equipped and no real candidates at all must still
-- produce a usable (synthetic, zero-score) frontier entry, or the whole
-- optimizer has no branch for that group and the ENTIRE loadout fails even
-- though every other group is fine.
test("an empty paired group still contributes a usable frontier entry so the whole loadout doesn't fail", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  local ringsFrontier = addon.Assignments.Groups.Rings.Frontier({}, {}, loadoutState, nil, nil)

  A.equal(#ringsFrontier, 1, "nothing equipped and no candidates leaves exactly one legal option: nothing")
  A.equal(ringsFrontier[1].score, 0)
  A.falsy(next(ringsFrontier[1].picks), "the synthesized option must leave both ring roles empty")

  local groups = {
    { id = "rings", slots = { 11, 12 }, frontier = ringsFrontier },
    { id = "B", slots = { 1 }, frontier = { assignment(50, { only = candidate("thing", 1) }) } },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.truthy(combination, "the whole loadout must still resolve even though the rings group has nothing real to offer")
  A.equal(score, 50)
  A.equal(combination.rings.score, 0)
  A.equal(combination.B.score, 50)
end)

-- The empty-both synthesis above must be scoped to the "genuinely
-- nothing equipped" case only -- when a role is genuinely occupied, the
-- fallback must represent that OCCUPIED state, never quietly launder it
-- into a stripped/empty one just because there's no bag alternative to
-- enumerate it via the ordinary path.
test("an occupied slot with no bag alternative is represented by its own current state, not a stripped one", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      ringEquipped = { itemID = 708, equipLoc = "INVTYPE_FINGER", stats = { ITEM_MOD_STRENGTH_SHORT = 40 } },
    },
    equipped = {},
    bags = {},
  })
  _G.C_Item.GetItemUniqueness = function(info)
    local id = tonumber(tostring(info):match("|Hitem:(%d+)"))
    if id == 708 then return 55, 1 end
    return nil, nil
  end

  local context = weaponsTestContext(addon)
  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end
  local ringEquipped = candidateFor(708)
  local loadoutState = addon.Assignments.LoadoutState.New()
  loadoutState:SeedFromEquipped({ [11] = ringEquipped })

  -- No bag candidates at all, and the currently-equipped ring isn't in
  -- the candidates pool either (Frontier never invents "keep current"
  -- from SeedFromEquipped alone -- see Weapons.Frontier's doc comment),
  -- so ordinary enumeration has nothing to work with (its only producible
  -- combination is both-empty, which is illegal). The current-state
  -- fallback must still surface the ring that's actually there.
  local ringsFrontier = addon.Assignments.Groups.Rings.Frontier({}, context, loadoutState, ringEquipped, nil)

  A.equal(#ringsFrontier, 1, "the only representable state is the ring that's actually equipped")
  A.equal(ringsFrontier[1].picks.first, ringEquipped, "the fallback must preserve the real occupant, not strip it")
  A.equal(ringsFrontier[1].score, 40)
end)

-- Weapons-specific regressions: unlike Rings/Trinkets, mainhand is
-- ordinarily never emptyAllowed (a real weapon is always the intended
-- resulting state) -- but "ordinarily" must not mean "unconditionally,"
-- or a naked character / a character with zero legal weapon candidates
-- makes Groups.Weapons.Frontier empty and fails the ENTIRE whole-loadout
-- optimization, exactly the bug this section regression-tests.
test("integration: an empty mainhand with no legal weapon candidates still yields a usable frontier, and the rest of the loadout still optimizes", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      ringUpgrade = { itemID = 701, equipLoc = "INVTYPE_FINGER", stats = { ITEM_MOD_STRENGTH_SHORT = 100 } },
    },
    equipped = {},
    bags = { [0] = { "ringUpgrade" } },
  })
  _G.C_Item.GetItemUniqueness = function() return nil, nil end

  local context = weaponsTestContext(addon)
  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end
  local ringUpgrade = candidateFor(701)
  local loadoutState = addon.Assignments.LoadoutState.New()
  local allSlots = { 11, 12, 16, 17 }

  -- Nothing currently equipped in either weapon slot, and no weapon
  -- candidates at all -- a genuinely naked mainhand.
  local weaponsFrontier = addon.Assignments.Groups.Weapons.Frontier({}, context, loadoutState, nil, nil, allSlots)

  A.equal(#weaponsFrontier, 1, "an empty mainhand with no legal candidates must yield exactly the synthesized no-op state")
  A.equal(weaponsFrontier[1].score, 0)
  A.falsy(next(weaponsFrontier[1].picks), "the synthesized state must leave both weapon roles empty")

  local ringsFrontier = addon.Assignments.Groups.Rings.Frontier({ ringUpgrade }, context, loadoutState, nil, nil, allSlots)

  local groups = {
    { id = "weapons", slots = { 16, 17 }, frontier = weaponsFrontier },
    { id = "rings", slots = { 11, 12 }, frontier = ringsFrontier },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.truthy(combination, "the whole loadout must still resolve even though weapons has nothing real to offer")
  A.equal(combination.weapons.score, 0)
  A.equal(score, 100, "the rings group's real upgrade must still be found and taken")
end)

test("integration: an empty mainhand preserves both 'equip the weapon' and 'remain empty' when the weapon competes with another group for a unique category", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      weaponCandidate = { itemID = 705, equipLoc = "INVTYPE_2HWEAPON", stats = { ITEM_MOD_STRENGTH_SHORT = 60 } },
      ringCandidate = { itemID = 706, equipLoc = "INVTYPE_FINGER", stats = { ITEM_MOD_STRENGTH_SHORT = 150 } },
    },
    equipped = {},
    bags = { [0] = { "weaponCandidate", "ringCandidate" } },
  })
  -- The weapon and the ring share a limit-1 unique category -- can't both
  -- be equipped.
  _G.C_Item.GetItemUniqueness = function(info)
    local id = tonumber(tostring(info):match("|Hitem:(%d+)"))
    if id == 705 or id == 706 then return 99, 1 end
    return nil, nil
  end

  local context = weaponsTestContext(addon)
  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end
  local weaponCandidate = candidateFor(705)
  local ringCandidate = candidateFor(706)
  local loadoutState = addon.Assignments.LoadoutState.New()
  local allSlots = { 11, 12, 16, 17 }

  local weaponsFrontier = addon.Assignments.Groups.Weapons.Frontier({ weaponCandidate }, context, loadoutState, nil, nil, allSlots)

  local function hasCandidate(frontier, target)
    for _, a in ipairs(frontier) do
      for _, c in pairs(a.picks) do
        if c == target then return true end
      end
    end
    return false
  end
  local function hasEmpty(frontier)
    for _, a in ipairs(frontier) do
      if not next(a.picks) then return true end
    end
    return false
  end

  A.truthy(hasCandidate(weaponsFrontier, weaponCandidate), "equipping the weapon must still be a representable state")
  A.truthy(hasEmpty(weaponsFrontier), "remaining empty must also still be a representable state")

  local ringsFrontier = addon.Assignments.Groups.Rings.Frontier({ ringCandidate }, context, loadoutState, nil, nil, allSlots)

  local groups = {
    { id = "weapons", slots = { 16, 17 }, frontier = weaponsFrontier },
    { id = "rings", slots = { 11, 12 }, frontier = ringsFrontier },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.truthy(combination)
  A.equal(score, 150, "the globally better ring must win the shared category; the weapon slot stays empty")
  A.equal(combination.weapons.score, 0)
  A.falsy(next(combination.weapons.picks), "the weapon group must resolve to its empty state")
  A.truthy(hasCandidate({ combination.rings }, ringCandidate))
end)

test("integration: an occupied mainhand never gets a synthetic unequip option", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      currentWeapon = { itemID = 707, equipLoc = "INVTYPE_2HWEAPON", stats = { ITEM_MOD_STRENGTH_SHORT = 80 } },
    },
    equipped = { [16] = "currentWeapon" },
    bags = {},
  })
  _G.C_Item.GetItemUniqueness = function() return nil, nil end

  local context = weaponsTestContext(addon)
  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end
  local currentWeapon = candidateFor(707)
  local loadoutState = addon.Assignments.LoadoutState.New()
  local allSlots = { 11, 12, 16, 17 }

  -- currentWeapon must be in the candidate pool for "keep what's
  -- equipped" to be representable at all (see Weapons.Frontier's doc
  -- comment) -- same convention as Rings/Trinkets.
  local weaponsFrontier = addon.Assignments.Groups.Weapons.Frontier(
    { currentWeapon }, context, loadoutState, currentWeapon, nil, allSlots)

  A.equal(#weaponsFrontier, 1, "with the mainhand occupied and no other candidates, only 'keep current' is legal")
  for _, a in ipairs(weaponsFrontier) do
    A.truthy(a.picks.mh, "no assignment in the frontier may leave the mainhand empty while it's currently occupied")
  end
end)

-- Elemental Shaman (any SHAMAN spec other than Enhancement, per
-- ClassSpecWeaponCapabilities) allows 1H/2H mainhand AND shield/holdable
-- offhand simultaneously, with no titan grip -- exactly what's needed to
-- exercise "mainhand empty, offhand occupied" without also fighting
-- unrelated hand-legality rules (unlike the two-handed-only Arms Warrior
-- context used above).
local function shieldCapableContext(addon)
  local scale = addon.XIVWeights.NewScale({
    weights = addon.XIVWeights.Normalizer.Normalize({ strength = 1 }),
  })
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local runtime = {
    UnitClass = function() return "Player", "SHAMAN", 1 end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 262, "Elemental" end,
    UnitLevel = function() return 80 end,
    IsDualWielding = function() return false end,
    ResolveWeights = function() return scale end,
  }
  return addon.Evaluation.ContextBuilder.BuildContext(resolved, runtime)
end

-- The finding this covers: WeaponHandLegality unconditionally rejects any
-- assignment with mh=nil (it exists to stop the SOLVER from proposing
-- "unequip the mainhand"), which also erases the literal ALREADY-TRUE
-- state of "mainhand empty, offhand occupied" from the frontier -- not
-- just the fully-naked "both empty" case the previous round fixed.
test("integration: an empty mainhand with an occupied offhand and no legal mainhand candidates still yields the real current state", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      currentShield = { itemID = 709, equipLoc = "INVTYPE_SHIELD", stats = { ITEM_MOD_STRENGTH_SHORT = 30 } },
      ringUpgrade = { itemID = 710, equipLoc = "INVTYPE_FINGER", stats = { ITEM_MOD_STRENGTH_SHORT = 90 } },
    },
    equipped = {},
    bags = { [0] = { "ringUpgrade" } },
  })
  _G.C_Item.GetItemUniqueness = function() return nil, nil end

  local context = shieldCapableContext(addon)
  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end
  local currentShield = candidateFor(709)
  local ringUpgrade = candidateFor(710)
  local loadoutState = addon.Assignments.LoadoutState.New()
  local allSlots = { 11, 12, 16, 17 }

  -- currentShield must be in the candidate pool for "keep what's
  -- equipped" to be representable at all -- same convention as every
  -- other Frontier caller. No mainhand candidates exist at all.
  local weaponsFrontier = addon.Assignments.Groups.Weapons.Frontier(
    { currentShield }, context, loadoutState, nil, currentShield, allSlots)

  A.equal(#weaponsFrontier, 1, "the only representable state is mainhand empty, offhand holding the current shield")
  A.falsy(weaponsFrontier[1].picks.mh, "mainhand must stay empty -- it already is")
  A.equal(weaponsFrontier[1].picks.oh, currentShield, "the offhand's real current occupant must be preserved, not stripped")
  A.equal(weaponsFrontier[1].score, 30)

  local ringsFrontier = addon.Assignments.Groups.Rings.Frontier({ ringUpgrade }, context, loadoutState, nil, nil, allSlots)

  local groups = {
    { id = "weapons", slots = { 16, 17 }, frontier = weaponsFrontier },
    { id = "rings", slots = { 11, 12 }, frontier = ringsFrontier },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.truthy(combination, "the whole loadout must resolve even with weapons stuck in a half-empty current state")
  A.equal(combination.weapons.score, 30)
  A.equal(score, 30 + 90)
end)

-- The uniqueness-tradeoff equivalent: the occupied offhand consumes a
-- constrained category a DIFFERENT group also wants. A legal mainhand
-- weapon exists, but it cannot be combined with the current shield at all
-- (a two-hander with no Titan's Grip on this spec) -- so the only way to
-- free the category for the other group is to give up the shield
-- entirely, not just add something alongside it. This proves the
-- fallback's "current" entry survives pruning as a genuine option and
-- that the optimizer can still correctly choose to abandon it when doing
-- so is globally better.
test("integration: the current empty-mainhand/occupied-offhand state coexists with an alternative that frees a shared unique category", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      currentShield = { itemID = 711, equipLoc = "INVTYPE_SHIELD", stats = { ITEM_MOD_STRENGTH_SHORT = 30 } },
      altWeapon = { itemID = 712, equipLoc = "INVTYPE_2HWEAPON", stats = { ITEM_MOD_STRENGTH_SHORT = 20 } },
      ringUpgrade = { itemID = 713, equipLoc = "INVTYPE_FINGER", stats = { ITEM_MOD_STRENGTH_SHORT = 50 } },
    },
    equipped = {},
    bags = { [0] = { "altWeapon", "ringUpgrade" } },
  })
  -- The shield and the ring share a limit-1 unique category. altWeapon
  -- shares no category with anything -- it's a strictly clean swap, but
  -- taking it means dropping the shield (a two-hander plus any offhand
  -- item requires Titan's Grip, which this spec doesn't have).
  _G.C_Item.GetItemUniqueness = function(info)
    local id = tonumber(tostring(info):match("|Hitem:(%d+)"))
    if id == 711 or id == 713 then return 111, 1 end
    return nil, nil
  end

  local context = shieldCapableContext(addon)
  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end
  local currentShield = candidateFor(711)
  local altWeapon = candidateFor(712)
  local ringUpgrade = candidateFor(713)
  local loadoutState = addon.Assignments.LoadoutState.New()
  local allSlots = { 11, 12, 16, 17 }

  local weaponsFrontier = addon.Assignments.Groups.Weapons.Frontier(
    { currentShield, altWeapon }, context, loadoutState, nil, currentShield, allSlots)

  local function hasState(frontier, mh, oh)
    for _, a in ipairs(frontier) do
      if a.picks.mh == mh and a.picks.oh == oh then return true end
    end
    return false
  end

  A.truthy(hasState(weaponsFrontier, nil, currentShield), "keeping the current shield (mainhand empty) must remain representable")
  A.truthy(hasState(weaponsFrontier, altWeapon, nil), "switching to the alternative weapon (dropping the shield) must also be representable")

  local ringsFrontier = addon.Assignments.Groups.Rings.Frontier({ ringUpgrade }, context, loadoutState, nil, nil, allSlots)

  local groups = {
    { id = "weapons", slots = { 16, 17 }, frontier = weaponsFrontier },
    { id = "rings", slots = { 11, 12 }, frontier = ringsFrontier },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.truthy(combination)
  A.equal(score, 20 + 50, "dropping the shield to free the category for the superior ring must win globally")
  A.equal(combination.weapons.picks.mh, altWeapon)
  A.falsy(combination.weapons.picks.oh, "the shield must be given up entirely, not kept alongside the new weapon")
  A.equal(combination.rings.picks.first, ringUpgrade)
end)

-- WARRIOR Protection: 1H mainhand + shield required, no two-handers.
local function protectionContext(addon)
  local scale = addon.XIVWeights.NewScale({
    weights = addon.XIVWeights.Normalizer.Normalize({ strength = 1 }),
  })
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local runtime = {
    UnitClass = function() return "Player", "WARRIOR", 1 end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 73, "Protection" end,
    UnitLevel = function() return 80 end,
    IsDualWielding = function() return false end,
    ResolveWeights = function() return scale end,
  }
  return addon.Evaluation.ContextBuilder.BuildContext(resolved, runtime)
end

-- The finding this covers: the current-state fallback's isCurrentState
-- bypass previously skipped assignment-phase policy vetoes entirely, so a
-- leftover two-hander that's genuinely illegal after a spec change (not
-- merely a partially-empty state policies have no opinion on) could
-- outscore and dominate a real, policy-valid replacement, deleting the
-- legal option from the frontier entirely. Paired.Evaluate now tags
-- `policyValid` from a REAL policy check, and Frontier.Dominates treats
-- policy validity as an absolute dimension -- a valid assignment always
-- beats an invalid one, regardless of score.
test("integration: a policy-invalid leftover current weapon cannot dominate and erase a policy-valid legal replacement", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      -- Leftover from an Arms (two-handed) loadout -- illegal now that
      -- the character is Protection (no two-handers allowed).
      leftover2H = { itemID = 714, equipLoc = "INVTYPE_2HWEAPON", stats = { ITEM_MOD_STRENGTH_SHORT = 200 } },
      legal1H = { itemID = 715, equipLoc = "INVTYPE_WEAPONMAINHAND", stats = { ITEM_MOD_STRENGTH_SHORT = 70 } },
      legalShield = { itemID = 716, equipLoc = "INVTYPE_SHIELD", stats = { ITEM_MOD_STRENGTH_SHORT = 50 } },
    },
    equipped = {},
    bags = { [0] = { "legal1H", "legalShield" } },
  })
  _G.C_Item.GetItemUniqueness = function() return nil, nil end

  local context = protectionContext(addon)
  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end
  local leftover2H = candidateFor(714)
  local legal1H = candidateFor(715)
  local legalShield = candidateFor(716)
  local loadoutState = addon.Assignments.LoadoutState.New()
  local allSlots = { 11, 12, 16, 17 }

  -- First: with no legal alternative at all, the illegal current state
  -- must still remain representable, or the whole loadout would fail.
  local noAlternativeFrontier = addon.Assignments.Groups.Weapons.Frontier(
    { leftover2H }, context, loadoutState, leftover2H, nil, allSlots)
  A.equal(#noAlternativeFrontier, 1, "with nothing legal to switch to, the illegal current state is the only representable option")
  A.equal(noAlternativeFrontier[1].picks.mh, leftover2H)
  A.equal(noAlternativeFrontier[1].policyValid, false)

  -- Now with a legal replacement available: the illegal 200-score
  -- leftover must NOT survive pruning, even though it outscores the
  -- 120-score legal replacement.
  local weaponsFrontier = addon.Assignments.Groups.Weapons.Frontier(
    { leftover2H, legal1H, legalShield }, context, loadoutState, leftover2H, nil, allSlots)

  local function hasState(frontier, mh, oh)
    for _, a in ipairs(frontier) do
      if a.picks.mh == mh and a.picks.oh == oh then return true end
    end
    return false
  end

  A.falsy(hasState(weaponsFrontier, leftover2H, nil),
    "the policy-invalid leftover two-hander must not survive pruning once a legal replacement exists")
  A.truthy(hasState(weaponsFrontier, legal1H, legalShield), "the legal 1H+shield replacement must survive frontier pruning")

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(
    { { id = "weapons", slots = { 16, 17 }, frontier = weaponsFrontier } }, loadoutState)

  A.truthy(combination)
  A.equal(score, 120, "the optimizer must choose the legal replacement, not the higher-scoring illegal leftover")
  A.equal(combination.weapons.picks.mh, legal1H)
  A.equal(combination.weapons.picks.oh, legalShield)
end)

-- The finding this covers: the previous fix made a policy-valid
-- assignment dominate a policy-invalid one UNCONDITIONALLY -- but whether
-- a "better" valid replacement is actually usable can depend on what some
-- OTHER group needs. Here the legal weapon replacement only survives its
-- OWN uniqueness check because whole-loadout removal provisionally clears
-- every group's current occupant (including the ring's) -- but the ring
-- has no replacement of its own, so combining the legal weapon with the
-- ring's real current state is illegal (both would consume the same
-- limit-1 category). The illegal leftover weapon doesn't touch that
-- category at all, so it's the ONLY thing that can coexist with the
-- ring's current state. Pruning it just because a policy-valid
-- alternative outscores it -- without checking whether that alternative
-- is safe alongside what other groups actually have -- would make the
-- only globally feasible complete loadout unreachable.
test("integration: a resource-cheaper policy-invalid weapon survives pruning when the policy-valid alternative would conflict with another group's fixed state", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      leftover2H = { itemID = 717, equipLoc = "INVTYPE_2HWEAPON", stats = { ITEM_MOD_STRENGTH_SHORT = 200 } },
      legal1H = { itemID = 718, equipLoc = "INVTYPE_WEAPONMAINHAND", stats = { ITEM_MOD_STRENGTH_SHORT = 70 } },
      legalShield = { itemID = 719, equipLoc = "INVTYPE_SHIELD", stats = { ITEM_MOD_STRENGTH_SHORT = 50 } },
      currentRing = { itemID = 720, equipLoc = "INVTYPE_FINGER", stats = { ITEM_MOD_STRENGTH_SHORT = 80 } },
    },
    equipped = {},
    bags = { [0] = { "legal1H", "legalShield" } },
  })
  -- legalShield and currentRing share a limit-1 unique category.
  -- leftover2H touches no category at all.
  _G.C_Item.GetItemUniqueness = function(info)
    local id = tonumber(tostring(info):match("|Hitem:(%d+)"))
    if id == 719 or id == 720 then return 121, 1 end
    return nil, nil
  end

  local context = protectionContext(addon)
  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end
  local leftover2H = candidateFor(717)
  local legal1H = candidateFor(718)
  local legalShield = candidateFor(719)
  local currentRing = candidateFor(720)

  local loadoutState = addon.Assignments.LoadoutState.New()
  loadoutState:SeedFromEquipped({ [16] = leftover2H, [11] = currentRing })
  local allSlots = { 11, 12, 16, 17 }

  local weaponsFrontier = addon.Assignments.Groups.Weapons.Frontier(
    { leftover2H, legal1H, legalShield }, context, loadoutState, leftover2H, nil, allSlots)

  local function hasState(frontier, mh, oh)
    for _, a in ipairs(frontier) do
      if a.picks.mh == mh and a.picks.oh == oh then return true end
    end
    return false
  end

  A.truthy(hasState(weaponsFrontier, leftover2H, nil),
    "the invalid leftover must survive -- the valid replacement isn't safely resource-equivalent")
  A.truthy(hasState(weaponsFrontier, legal1H, legalShield),
    "the valid replacement must also remain representable")

  -- No ring replacement exists -- its frontier is just the current state.
  local ringsFrontier = addon.Assignments.Groups.Rings.Frontier({}, context, loadoutState, currentRing, nil, allSlots)

  local groups = {
    { id = "weapons", slots = { 16, 17 }, frontier = weaponsFrontier },
    { id = "rings", slots = { 11, 12 }, frontier = ringsFrontier },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState)

  A.truthy(combination, "no fully policy-valid complete loadout exists, but the invalid fallback keeps one reachable")
  A.equal(combination.weapons.picks.mh, leftover2H,
    "the optimizer must fall back to the invalid weapon -- the valid one can't coexist with the ring's fixed state")
  A.equal(score, 200 + 80)
end)

-- The finding this covers: Frontier.Dominates correctly lets BOTH a
-- policy-invalid current weapon and a resource-costlier policy-valid
-- replacement survive pruning (neither safely dominates the other purely
-- from a single group's perspective) -- but LoadoutOptimizer.FindBest
-- itself only reads .picks and .score, with no concept of policyValid.
-- Left alone, pure score maximization would happily pick the higher-
-- scoring invalid weapon even when a fully policy-valid complete loadout
-- is available and nothing else in the loadout needed the category the
-- valid replacement would have consumed. This is the exact case the
-- previous round's fix (usage-gated dominance) deliberately left
-- unresolved at the frontier level, on the understanding that the
-- optimizer itself would need to prefer full validity over raw score.
test("integration: LoadoutOptimizer prefers a fully policy-valid complete loadout over a higher-scoring invalid fallback", function()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)

  FakeWorld.Install({
    items = {
      leftover2H = { itemID = 721, equipLoc = "INVTYPE_2HWEAPON", stats = { ITEM_MOD_STRENGTH_SHORT = 200 } },
      legal1H = { itemID = 722, equipLoc = "INVTYPE_WEAPONMAINHAND", stats = { ITEM_MOD_STRENGTH_SHORT = 70 } },
      legalShield = { itemID = 723, equipLoc = "INVTYPE_SHIELD", stats = { ITEM_MOD_STRENGTH_SHORT = 50 } },
    },
    equipped = {},
    bags = { [0] = { "legal1H", "legalShield" } },
  })
  -- legalShield uses a unique category, but nothing else anywhere in this
  -- loadout wants it -- there is no conflict to force the fallback.
  _G.C_Item.GetItemUniqueness = function(info)
    local id = tonumber(tostring(info):match("|Hitem:(%d+)"))
    if id == 723 then return 122, 1 end
    return nil, nil
  end

  local context = protectionContext(addon)
  local function candidateFor(itemID)
    return addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(itemID), { guid = "guid-" .. itemID })
  end
  local leftover2H = candidateFor(721)
  local legal1H = candidateFor(722)
  local legalShield = candidateFor(723)

  local loadoutState = addon.Assignments.LoadoutState.New()
  loadoutState:SeedFromEquipped({ [16] = leftover2H })
  local allSlots = { 11, 12, 16, 17 }

  local weaponsFrontier = addon.Assignments.Groups.Weapons.Frontier(
    { leftover2H, legal1H, legalShield }, context, loadoutState, leftover2H, nil, allSlots)

  local function hasState(frontier, mh, oh)
    for _, a in ipairs(frontier) do
      if a.picks.mh == mh and a.picks.oh == oh then return true end
    end
    return false
  end

  A.truthy(hasState(weaponsFrontier, leftover2H, nil), "the invalid current state must still survive Frontier.Prune")
  A.truthy(hasState(weaponsFrontier, legal1H, legalShield), "the valid replacement must also survive Frontier.Prune")

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(
    { { id = "weapons", slots = { 16, 17 }, frontier = weaponsFrontier } }, loadoutState)

  A.truthy(combination)
  A.equal(combination.weapons.picks.mh, legal1H,
    "a fully policy-valid complete loadout exists, so the optimizer must prefer it over the higher-scoring invalid one")
  A.equal(combination.weapons.picks.oh, legalShield)
  A.equal(score, 120)
end)

test("loadout policy set bonus can make lower local set pieces globally optimal", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  local highPlain = assignment(100, {})
  local lowerTierA = assignment(90, {})
  lowerTierA.setCounts = { tier = 1 }
  local lowerTierB = assignment(90, {})
  lowerTierB.setCounts = { tier = 1 }

  local frontierA = addon.Assignments.Frontier.Prune({ highPlain, lowerTierA })
  A.equal(#frontierA, 2, "the lower local score must survive because it carries set progress")

  local context = {
    policies = {
      loadout = {
        {
          id = "Test.two_piece",
          apply = function(loadout)
            if (loadout.summaries.setCounts.tier or 0) >= 2 then
              return { scoreAdjustment = 30 }
            end
          end,
        },
      },
    },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest({
    { id = "A", slots = { 1 }, frontier = frontierA },
    { id = "B", slots = { 2 }, frontier = { lowerTierB } },
  }, loadoutState, context)

  A.equal(combination.A, lowerTierA)
  A.equal(combination.B, lowerTierB)
  A.equal(score, 90 + 90 + 30)
end)

test("loadout policies can reject complete combinations using required summary flags", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  local required = assignment(50, {})
  required.requiredFlags = { locked = true }
  local missingRequiredHigherScore = assignment(100, {})

  local context = {
    policies = {
      loadout = {
        {
          id = "Test.require_locked",
          apply = function(loadout)
            return loadout.summaries.requiredFlags.locked == true
          end,
        },
      },
    },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest({
    { id = "A", slots = { 1 }, frontier = { missingRequiredHigherScore, required } },
  }, loadoutState, context)

  A.equal(combination.A, required)
  A.equal(score, 50)
end)

test("preference policies run after loadout policies and adjust final ranking", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()

  local plain = assignment(100, {})
  local preferred = assignment(95, {})
  preferred.targetFlags = { wishlist = true }

  local context = {
    caches = {},
    policies = {
      loadout = {
        {
          id = "Test.loadout_fact",
          provides = { "test.loadout.fact" },
          apply = function(_, ctx)
            ctx.caches.loadoutFact = true
          end,
        },
      },
      preference = {
        {
          id = "Test.preference_after_loadout",
          requires = { "test.loadout.fact" },
          apply = function(loadout, ctx)
            A.truthy(ctx.caches.loadoutFact, "preference must run after loadout policies have executed")
            if loadout.summaries.targetFlags.wishlist then return { preferenceAdjustment = 10 } end
          end,
        },
      },
    },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest({
    { id = "A", slots = { 1 }, frontier = { plain, preferred } },
  }, loadoutState, context)

  A.equal(combination.A, preferred)
  A.equal(score, 95 + 10)
end)

test("inactive preference policies do not run or disable score pruning", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()
  local counters = {}
  local context = {
    policies = {
      loadout = {},
      preference = {
        {
          id = "Test.inactive",
          isActive = function() return false end,
          apply = function() error("inactive policy should not run") end,
        },
      },
    },
    perf = {
      Add = function(_, key, value)
        counters[key] = (counters[key] or 0) + (value or 1)
      end,
    },
  }

  local groups = {
    { id = "A", slots = { 1 }, frontier = { assignment(100, {}), assignment(1, {}) } },
    { id = "B", slots = { 2 }, frontier = { assignment(100, {}), assignment(1, {}) } },
    { id = "C", slots = { 3 }, frontier = { assignment(100, {}), assignment(1, {}) } },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState, context)

  A.truthy(combination)
  A.equal(score, 300)
  A.truthy((counters["optimizer.score_bound_prunes"] or 0) > 0,
    "an inactive preference policy must not force exhaustive score search")
end)

test("active bounded preference policies allow policy-bound score pruning", function()
  local addon = newAddon()
  local loadoutState = addon.Assignments.LoadoutState.New()
  local counters = {}
  local context = {
    policies = {
      loadout = {},
      preference = {
        {
          id = "Test.bounded",
          isActive = function() return true end,
          upperBound = function() return 0 end,
          apply = function() return nil end,
        },
      },
    },
    perf = {
      Add = function(_, key, value)
        counters[key] = (counters[key] or 0) + (value or 1)
      end,
    },
  }

  local groups = {
    { id = "A", slots = { 1 }, frontier = { assignment(100, {}), assignment(1, {}) } },
    { id = "B", slots = { 2 }, frontier = { assignment(100, {}), assignment(1, {}) } },
    { id = "C", slots = { 3 }, frontier = { assignment(100, {}), assignment(1, {}) } },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(groups, loadoutState, context)

  A.truthy(combination)
  A.equal(score, 300)
  A.truthy((counters["optimizer.policy_bound_prunes"] or 0) > 0,
    "a bounded preference policy should keep score pruning available")
end)

test("optimizer-aware policy hooks prepare once and restore branch state after every push", function()
  local addon = newAddon()
  local counters, calls, createdState = {}, { prepare = 0, create = 0, push = 0, pop = 0 }, nil
  local context = {
    policies = {
      loadout = {},
      preference = {
        {
          id = "Test.incremental_bound",
          apply = function() return nil end,
          optimizer = {
            prepare = function(ordered)
              calls.prepare = calls.prepare + 1
              return { groupCount = #ordered }
            end,
            createState = function(prepared)
              calls.create = calls.create + 1
              A.equal(prepared.groupCount, 3)
              createdState = { depth = 0 }
              return createdState
            end,
            push = function(state)
              calls.push = calls.push + 1
              local previous = state.depth
              state.depth = previous + 1
              return previous
            end,
            pop = function(state, previous)
              calls.pop = calls.pop + 1
              state.depth = previous
            end,
            upperBound = function(state, nextIndex, prepared)
              A.equal(state.depth, nextIndex - 1)
              A.equal(prepared.groupCount, 3)
              return 0
            end,
          },
        },
      },
    },
    perf = {
      Add = function(_, key, value) counters[key] = (counters[key] or 0) + (value or 1) end,
    },
  }
  local groups = {
    { id = "A", slots = { 1 }, frontier = { assignment(100, {}), assignment(1, {}) } },
    { id = "B", slots = { 2 }, frontier = { assignment(100, {}), assignment(1, {}) } },
    { id = "C", slots = { 3 }, frontier = { assignment(100, {}), assignment(1, {}) } },
  }

  local combination, score = addon.Optimization.LoadoutOptimizer.FindBest(
    groups, addon.Assignments.LoadoutState.New(), context)

  A.truthy(combination)
  A.equal(score, 300)
  A.equal(calls.prepare, 1)
  A.equal(calls.create, 1)
  A.equal(calls.push, calls.pop)
  A.equal(createdState.depth, 0)
  A.equal(counters["optimizer.policy_state_pushes"], calls.push)
  A.equal(counters["optimizer.policy_state_pops"], calls.pop)
end)

return tests
