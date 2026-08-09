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
    weapon = { dps = 20, minimumDamage = 30, maximumDamage = 40 },
  }

  local vector = addon.Evaluation.CandidateEvaluator.FeatureVector(candidate)

  A.equal(vector.strength, 10)
  A.equal(vector.weaponDps, 20)
  A.equal(vector.weaponMinDamage, 30)
  A.equal(vector.weaponMaxDamage, 40)
end)

test("Score matches a manual weighted sum against a hand-built scale", function()
  local addon = newAddon()
  local candidate = { stats = { strength = 100, stamina = 40 }, weapon = {} }
  local scale = addon.XIVWeights.NewScale({ weights = { strength = 1.0, stamina = 0.5 } })

  local score = addon.Evaluation.CandidateEvaluator.Score(candidate, { weights = scale })

  A.equal(score, 100 * 1.0 + 40 * 0.5)
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

return tests
