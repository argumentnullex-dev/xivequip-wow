-- tests/specs/candidate_evaluator_spec.lua
-- The "universal XIVWeights candidate scorer" (doc section 17/35): a
-- manual weighted-sum check, plus a full integration test chaining Phase
-- 1's Pawn Provider through Resolver.Resolve, a normalized candidate, and
-- CandidateEvaluator.Score -- proving Phase 1 and Phase 2 actually connect.

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
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  return addon
end

test("FeatureVector translates candidate.weapon's human-oriented names to the XIVWeights vocabulary", function()
  local addon = newAddon()
  local candidate = {
    stats = { strength = 10 },
    weapon = { dps = 20, minimumDamage = 30, maximumDamage = 40, swingIntervalSeconds = 2.6 },
  }

  local vector = addon.Evaluation.CandidateEvaluator.FeatureVector(candidate)

  A.equal(vector.strength, 10)
  A.equal(vector.weaponDps, 20)
  A.equal(vector.weaponMinDamage, 30)
  A.equal(vector.weaponMaxDamage, 40)
  A.equal(vector.weaponSwingIntervalSeconds, 2.6)
end)

test("Score matches a manual weighted sum against a hand-built scale", function()
  local addon = newAddon()
  local candidate = { stats = { strength = 100, stamina = 40 }, weapon = {} }
  local scale = addon.XIVWeights.NewScale({ weights = { strength = 1.0, stamina = 0.5 } })

  local score = addon.Evaluation.CandidateEvaluator.Score(candidate, { weights = scale })

  A.equal(score, 100 * 1.0 + 40 * 0.5)
end)

test("intrinsic score is calculated once per item per EvaluationContext", function()
  local addon = newAddon()
  local calls = 0
  local original = addon.XIVWeights.Scorer.Score
  addon.XIVWeights.Scorer.Score = function(...)
    calls = calls + 1
    return original(...)
  end
  local candidate = { guid = "guid-score", stats = { strength = 100 }, weapon = {} }
  local scale = addon.XIVWeights.NewScale({ weights = { strength = 1.0 } })
  local context = { weights = scale, caches = {} }

  A.equal(addon.Evaluation.CandidateEvaluator.Score(candidate, context), 100)
  A.equal(addon.Evaluation.CandidateEvaluator.Score(candidate, context), 100)

  A.equal(calls, 1)
end)

test("a new EvaluationContext performs a fresh intrinsic score", function()
  local addon = newAddon()
  local calls = 0
  local original = addon.XIVWeights.Scorer.Score
  addon.XIVWeights.Scorer.Score = function(...)
    calls = calls + 1
    return original(...)
  end
  local candidate = { guid = "guid-score", stats = { strength = 100 }, weapon = {} }
  local scale = addon.XIVWeights.NewScale({ weights = { strength = 1.0 } })

  addon.Evaluation.CandidateEvaluator.Score(candidate, { weights = scale, caches = {} })
  addon.Evaluation.CandidateEvaluator.Score(candidate, { weights = scale, caches = {} })

  A.equal(calls, 2)
end)

test("Evaluate applies candidate eligibility policies before score can make an item attractive", function()
  local addon = newAddon()
  local candidate = { itemID = 42, stats = { strength = 1000 }, weapon = {} }
  local scale = addon.XIVWeights.NewScale({ weights = { strength = 1.0 } })
  local context = {
    weights = scale,
    policies = {
      candidate = {
        {
          id = "Test.exclude",
          groups = { "trinkets" },
          apply = function(c)
            if c.itemID == 42 then return { allow = false, reason = "excluded" } end
          end,
        },
      },
      preference = {},
    },
  }

  local result = addon.Evaluation.CandidateEvaluator.Evaluate(candidate, context, { groupId = "trinkets" })

  A.falsy(result.eligible)
  A.equal(result.baseScore, 1000)
  A.equal(result.score, 1000, "eligibility is separate from raw score")
  A.equal(result.reasons[1], "excluded")
end)

test("placement caching preserves role and slot sensitive policy context", function()
  local addon = newAddon()
  local calls = 0
  local candidate = { guid = "guid-placement", stats = { strength = 10 }, weapon = {} }
  local scale = addon.XIVWeights.NewScale({ weights = { strength = 1.0 } })
  local context = {
    weights = scale,
    caches = {},
    policies = {
      candidate = {
        {
          id = "Test.role_sensitive",
          apply = function(_, _, policyContext)
            calls = calls + 1
            return { targetFlags = { [policyContext.role .. ":" .. tostring(policyContext.slot)] = true } }
          end,
        },
      },
      preference = {},
    },
  }

  local first = addon.Evaluation.CandidateEvaluator.Evaluate(candidate, context, {
    groupId = "rings", role = "first", slot = 11,
  })
  local second = addon.Evaluation.CandidateEvaluator.Evaluate(candidate, context, {
    groupId = "rings", role = "second", slot = 12,
  })
  local firstAgain = addon.Evaluation.CandidateEvaluator.Evaluate(candidate, context, {
    groupId = "rings", role = "first", slot = 11,
  })

  A.equal(calls, 2)
  A.truthy(first.targetFlags["first:11"])
  A.truthy(second.targetFlags["second:12"])
  A.truthy(firstAgain.targetFlags["first:11"])
end)

test("Evaluate applies candidate score adjustments and carries summary state", function()
  local addon = newAddon()
  local candidate = { itemID = 101, stats = { strength = 100 }, weapon = {} }
  local scale = addon.XIVWeights.NewScale({ weights = { strength = 1.0 } })
  local context = {
    weights = scale,
    policies = {
      candidate = {
        {
          id = "Test.set",
          apply = function()
            return {
              scoreAdjustment = 25,
              setCounts = { tier = 1 },
              targetFlags = { wanted = true },
              requiredFlags = { locked = true },
            }
          end,
        },
      },
      preference = {},
    },
  }

  local result = addon.Evaluation.CandidateEvaluator.Evaluate(candidate, context, { groupId = "trinkets" })

  A.truthy(result.eligible)
  A.equal(result.baseScore, 100)
  A.equal(result.scoreAdjustment, 25)
  A.equal(result.score, 125)
  A.equal(result.setCounts.tier, 1)
  A.truthy(result.targetFlags.wanted)
  A.truthy(result.requiredFlags.locked)
end)

test("paired enumeration does not rescore the same candidate for every combination", function()
  local addon = newAddon()
  Bootstrap.LoadAssignments(root, addon)
  local calls = 0
  local original = addon.XIVWeights.Scorer.Score
  addon.XIVWeights.Scorer.Score = function(...)
    calls = calls + 1
    return original(...)
  end
  local scale = addon.XIVWeights.NewScale({ weights = { strength = 1.0 } })
  local context = {
    weights = scale,
    caches = {},
    policies = { candidate = {}, assignment = {}, preference = {} },
  }
  local candidates = {
    { guid = "guid-a", physicalID = "a", stats = { strength = 10 }, weapon = {} },
    { guid = "guid-b", physicalID = "b", stats = { strength = 20 }, weapon = {} },
    { guid = "guid-c", physicalID = "c", stats = { strength = 30 }, weapon = {} },
  }

  addon.Assignments.Paired.Solve({
    roles = { "first", "second" },
    slots = { first = 11, second = 12 },
    candidates = candidates,
    context = context,
    loadoutState = addon.Assignments.LoadoutState.New(),
    groupId = "rings",
    compare = function(candidate, current)
      return (candidate.score or 0) > (current.score or 0)
    end,
  })

  A.equal(calls, 3)
end)

test("Evaluate supplies current candidate state to candidate policies", function()
  local addon = newAddon()
  local current = { itemID = 1, itemLevel = 500, stats = {}, weapon = {} }
  local candidate = { itemID = 2, itemLevel = 419, stats = { strength = 1000 }, weapon = {} }
  local scale = addon.XIVWeights.NewScale({ weights = { strength = 1.0 } })
  local context = {
    weights = scale,
    policies = {
      candidate = {
        {
          id = "Test.current_state",
          apply = function(_, _, policyContext)
            A.equal(policyContext.currentCandidate, current)
            A.equal(policyContext.currentByRole.first, current)
            A.equal(policyContext.currentBySlot[11], current)
            return { allow = false, reason = "below-current-floor" }
          end,
        },
      },
      preference = {},
    },
  }

  local result = addon.Evaluation.CandidateEvaluator.Evaluate(candidate, context, {
    groupId = "rings",
    role = "first",
    slot = 11,
    currentCandidate = current,
    currentByRole = { first = current },
    currentBySlot = { [11] = current },
  })

  A.falsy(result.eligible)
  A.equal(result.reasons[1], "below-current-floor")
end)

test("Evaluate does not run preference policies before assignment and loadout phases", function()
  local addon = newAddon()
  local candidate = { itemID = 9, stats = { strength = 10 }, weapon = {} }
  local scale = addon.XIVWeights.NewScale({ weights = { strength = 1.0 } })
  local context = {
    weights = scale,
    policies = {
      candidate = {},
      preference = {
        {
          id = "Test.must_not_run_here",
          apply = function() error("preference policy ran during candidate evaluation") end,
        },
      },
    },
  }

  local result = addon.Evaluation.CandidateEvaluator.Evaluate(candidate, context, { groupId = "trinkets" })

  A.truthy(result.eligible)
  A.equal(result.score, 10)
end)

test("integration: Pawn Provider -> Resolver.Resolve -> normalized candidate -> CandidateEvaluator.Score", function()
  local addon = newAddon()
  _G.XIVEquip = addon

  FakeWorld.Install({
    items = {
      sword = {
        itemID = 7001, equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7,
        stats = { ITEM_MOD_STRENGTH_SHORT = 200, ITEM_MIN_DAMAGE = 50, ITEM_MAX_DAMAGE = 100 },
      },
    },
  })

  local pawnAdapter = {
    ListScales = function() return {} end,
    ResolveValues = function()
      return { Strength = 200, MinDamage = 1.0, MaxDamage = 1.0 }, { key = "test-scale", name = "Test Scale" }
    end,
  }
  local provider = addon.XIVWeights.Providers.Pawn.New(pawnAdapter)
  local providerScale = provider:Resolve(nil, {})
  local effectiveScale = addon.XIVWeights.Resolver.Resolve(providerScale, nil)

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(7001), { kind = "bag", bag = 0, slot = 0 })
  local score = addon.Evaluation.CandidateEvaluator.Score(candidate, { weights = effectiveScale })

  -- Strength is the strongest raw Pawn weight (200) so it normalizes to
  -- 1.0; MinDamage/MaxDamage (1.0 each) normalize to 1.0/200 = 0.005 each.
  local expected = 200 * 1.0 + 50 * (1.0 / 200) + 100 * (1.0 / 200)
  A.equal(score, expected)
end)

test("integration: native Pawn Speed weight reaches the scorer", function()
  local addon = newAddon()
  _G.XIVEquip = addon

  FakeWorld.Install({
    items = {
      fast = { itemID = 7002, equipLoc = "INVTYPE_WEAPON", stats = { Speed = 1.8 } },
      slow = { itemID = 7003, equipLoc = "INVTYPE_WEAPON", stats = { Speed = 3.6 } },
    },
  })

  local pawnAdapter = {
    ListScales = function() return {} end,
    ResolveValues = function()
      return { Speed = 100 }, { key = "speed-scale", name = "Speed Scale" }
    end,
  }
  local provider = addon.XIVWeights.Providers.Pawn.New(pawnAdapter)
  local scale = addon.XIVWeights.Resolver.Resolve(provider:Resolve(nil, {}), nil)

  local fast = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(7002), {})
  local slow = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(7003), {})

  A.equal(addon.Evaluation.CandidateEvaluator.Score(fast, { weights = scale }), 1.8)
  A.equal(addon.Evaluation.CandidateEvaluator.Score(slow, { weights = scale }), 3.6)
end)

return tests
