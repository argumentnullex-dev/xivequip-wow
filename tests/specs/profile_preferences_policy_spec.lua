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
  _G.XIVEquip_Settings = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)
  return addon
end

local function policyByID(policies, id)
  for _, policy in ipairs(policies or {}) do
    if policy.id == id then return policy end
  end
  error("missing policy " .. tostring(id))
end

local function setAssignment(score, setID, tag)
  local candidate = { itemID = tag, physicalID = tostring(tag), setID = setID }
  local result = {
    tag = tag,
    score = score,
    picks = { slot = candidate },
    scores = { slot = score },
  }
  if setID then result.setCounts = { ["set:" .. tostring(setID)] = 1 } end
  return result
end

local function setGroup(id, slot, frontier)
  return { id = id, slots = { slot }, frontier = frontier }
end

local function setPreferencePolicy(addon)
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  return policyByID(resolved.preference, "XIVEquip.prefer_set_bonuses")
end

local function newSetSearch(policy, groups)
  local prepared = policy.optimizer.prepare(groups, {})
  return policy.optimizer, prepared, policy.optimizer.createState(prepared, {})
end

test("profile preferences are spec-scoped, mutually exclusive, and profile-owned", function()
  local addon = newAddon()
  local Profiles = addon.Profiles.Config
  local profile = Profiles.GetDefault("PALADIN")

  A.truthy(Profiles.SetPreferSetBonuses(profile, true))
  A.truthy(Profiles.SetWishlistItem(profile, 70, 12345, true))
  A.truthy(Profiles.SetAvoidlistItem(profile, 70, 67890, true))
  A.truthy(Profiles.SetAvoidlistItem(profile, 70, 12345, true), "adding to Avoidlist should remove Wishlist entry")

  local retribution = Profiles.GetSpecPreferences(profile, 70)
  A.truthy(retribution.preferSetBonuses)
  A.falsy(retribution.wishlist[12345])
  A.truthy(retribution.avoidlist[12345])
  A.truthy(retribution.avoidlist[67890])

  local protection = Profiles.GetSpecPreferences(profile, 66)
  A.falsy(protection.wishlist[12345], "lists must not leak between specializations")
  A.falsy(protection.avoidlist[67890], "lists must not leak between specializations")
  A.equal(Profiles.SetWishlistItem(profile, 73, 1, true), nil, "a Paladin Profile cannot own a Warrior spec list")
end)

test("planning-relevant profile changes invalidate the preview cache", function()
  local addon = newAddon()
  local invalidations = 0
  addon.UI = {
    ClearPreviewCache = function() invalidations = invalidations + 1 end,
  }
  local Profiles = addon.Profiles.Config
  local profile = Profiles.GetDefault("PALADIN")

  Profiles.AssignCharacter("Tester-Realm", "PALADIN", profile.id)
  Profiles.SetPreferSetBonuses(profile, true)
  Profiles.SetWishlistItem(profile, 70, 444, true)
  Profiles.SetAutomatic(profile, false)
  Profiles.SetManualMode(profile, "default")

  A.equal(invalidations, 5)
end)

test("evaluation context snapshots the active Profile's specialization preferences", function()
  local addon = newAddon()
  local Profiles = addon.Profiles.Config
  local profile = Profiles.GetDefault("PALADIN")
  Profiles.SetPreferSetBonuses(profile, true)
  Profiles.SetWishlistItem(profile, 70, 444, true)

  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, {
    UnitClass = function() return "Paladin", "PALADIN", 2 end,
    UnitName = function() return "Daedric", "Area 52" end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 70, "Retribution" end,
    UnitLevel = function() return 80 end,
    IsDualWielding = function() return false end,
    ResolveWeights = function() return addon.XIVWeights.NewScale({ weights = {} }) end,
  })

  A.truthy(context.profilePreferences.preferSetBonuses)
  A.truthy(context.profilePreferences.wishlist[444])
  A.falsy(context.profilePreferences.avoidlist[444])
end)

test("profile list policy excludes avoided candidates and gives wished candidates a ten-percent score bonus", function()
  local addon = newAddon()
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local listPolicy = policyByID(resolved.candidate, "XIVEquip.profile_item_lists")
  local context = {
    profilePreferences = { wishlist = { [10] = true }, avoidlist = { [20] = true } },
    policies = { candidate = { listPolicy }, preference = {} },
  }

  local wished = addon.Evaluation.CandidateEvaluator.Evaluate({ itemID = 10, stats = {}, weapon = {} }, context, {
    score = function() return 100 end,
  })
  A.truthy(wished.eligible)
  A.equal(wished.scoreAdjustment, 10)
  A.equal(wished.score, 110)
  A.equal(wished.reasons[1], "wishlist")

  local avoided = addon.Evaluation.CandidateEvaluator.Evaluate({ itemID = 20, stats = {}, weapon = {} }, context, {
    score = function() return 1000 end,
  })
  A.falsy(avoided.eligible)
  A.equal(avoided.reasons[1], "avoidlist")
end)

test("an avoided current item remains representable but cannot become a proposed replacement", function()
  local addon = newAddon()
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local listPolicy = policyByID(resolved.candidate, "XIVEquip.profile_item_lists")
  local current = { itemID = 20, stats = {}, weapon = {}, physicalID = "current" }
  local avoidedBagItem = { itemID = 20, stats = {}, weapon = {}, physicalID = "bag" }
  local context = {
    profilePreferences = { wishlist = {}, avoidlist = { [20] = true } },
    policies = { candidate = { listPolicy }, preference = {} },
  }
  local frontier = addon.Assignments.Singleton.Frontier({
    groupId = "head", slot = 1, context = context,
    loadoutState = addon.Assignments.LoadoutState.New(),
    current = current, candidates = { avoidedBagItem },
    score = function() return 100 end,
  })

  A.equal(#frontier, 1)
  A.equal(frontier[1].picks.slot, current)
  A.falsy(frontier[1].policyValid, "the retained current state must remain marked policy-invalid")
end)

test("normalization preserves an item's set ID for candidate policies", function()
  local addon = newAddon()
  _G.XIVEquip = addon
  FakeWorld.Install({
    items = {
      tier = { itemID = 901, equipLoc = "INVTYPE_HEAD", setID = 4242 },
    },
  })

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(901), {})
  A.equal(candidate.setID, 4242)
end)

test("set membership only contributes summary state when an active policy consumes it", function()
  local addon = newAddon()
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local setMembership = policyByID(resolved.candidate, "XIVEquip.set_membership")
  local setPreference = policyByID(resolved.preference, "XIVEquip.prefer_set_bonuses")
  local candidate = { itemID = 901, setID = 77, stats = {}, weapon = {} }

  local disabled = addon.Evaluation.CandidateEvaluator.Evaluate(candidate, {
    profilePreferences = { preferSetBonuses = false },
    policies = { candidate = { setMembership }, assignment = {}, loadout = {}, preference = { setPreference } },
  }, {
    score = function() return 100 end,
  })
  A.same(disabled.setCounts, {}, "inactive set preference should not expand frontier dimensions")

  local enabled = addon.Evaluation.CandidateEvaluator.Evaluate(candidate, {
    profilePreferences = { preferSetBonuses = true },
    caches = { relevantSetIDs = { [77] = true } },
    policies = { candidate = { setMembership }, assignment = {}, loadout = {}, preference = { setPreference } },
  }, {
    score = function() return 100 end,
  })
  A.equal(enabled.setCounts["set:77"], 1)

  local irrelevant = addon.Evaluation.CandidateEvaluator.Evaluate(candidate, {
    profilePreferences = { preferSetBonuses = true },
    caches = { relevantSetIDs = { [88] = true } },
    policies = { candidate = { setMembership }, assignment = {}, loadout = {}, preference = { setPreference } },
  }, {
    score = function() return 100 end,
  })
  A.same(irrelevant.setCounts, {}, "set IDs below the first active threshold should not enlarge frontiers")
end)

test("set preference chooses two set pieces when their five-percent threshold bonus outweighs local scores", function()
  local addon = newAddon()
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local setMembership = policyByID(resolved.candidate, "XIVEquip.set_membership")
  local setPreference = policyByID(resolved.preference, "XIVEquip.prefer_set_bonuses")
  local context = {
    profilePreferences = { preferSetBonuses = true, wishlist = {}, avoidlist = {} },
    policies = { candidate = { setMembership }, assignment = {}, loadout = {}, preference = { setPreference } },
  }
  local state = addon.Assignments.LoadoutState.New()
  local function group(id, slot)
    return {
      id = id, slots = { slot },
      frontier = addon.Assignments.Singleton.Frontier({
        groupId = id, slot = slot, context = context, loadoutState = state,
        candidates = {
          { itemID = slot * 10 + 1, physicalID = "plain-" .. slot, stats = {}, weapon = {} },
          { itemID = slot * 10 + 2, physicalID = "tier-" .. slot, setID = 77, stats = {}, weapon = {} },
        },
        score = function(candidate)
          return candidate.setID and 96 or 100
        end,
      }),
    }
  end

  local selected, score = addon.Optimization.LoadoutOptimizer.FindBest({ group("head", 1), group("shoulders", 3) }, state, context)
  A.equal(selected.head.picks.slot.setID, 77)
  A.equal(selected.shoulders.picks.slot.setID, 77)
  A.equal(score, 201.6)
end)

test("set preference does not award extra value to a fifth set piece", function()
  local addon = newAddon()
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local setPreference = policyByID(resolved.preference, "XIVEquip.prefer_set_bonuses")
  local assignments = {}
  for i = 1, 5 do
    assignments["slot" .. tostring(i)] = {
      picks = { slot = { itemID = 900 + i, setID = 77 } },
      scores = { slot = 100 },
    }
  end

  local result = setPreference.apply({
    assignments = assignments,
    summaries = { setCounts = { ["set:77"] = 5 } },
  }, {
    profilePreferences = { preferSetBonuses = true },
  })

  A.equal(result.preferenceAdjustment, 40)
end)

test("set preference does not make a low-score fifth set piece look better", function()
  local addon = newAddon()
  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local setPreference = policyByID(resolved.preference, "XIVEquip.prefer_set_bonuses")
  local assignments = {}
  for i = 1, 4 do
    assignments["slot" .. tostring(i)] = {
      picks = { slot = { itemID = 900 + i, setID = 77 } },
      scores = { slot = 100 },
    }
  end
  assignments.slot5 = {
    picks = { slot = { itemID = 999, setID = 77 } },
    scores = { slot = 1 },
  }

  local result = setPreference.apply({
    assignments = assignments,
    summaries = { setCounts = { ["set:77"] = 5 } },
  }, {
    profilePreferences = { preferSetBonuses = true },
  })

  A.equal(result.preferenceAdjustment, 40)
end)

test("set optimizer bound is zero when fewer than two pieces are reachable", function()
  local policy = setPreferencePolicy(newAddon())
  local hooks, prepared, state = newSetSearch(policy, {
    setGroup("head", 1, { setAssignment(100, 77, "head") }),
  })

  A.equal(hooks.upperBound(state, 1, prepared, {}), 0)
end)

test("set optimizer bound represents one selected plus one reachable as 2pc", function()
  local policy = setPreferencePolicy(newAddon())
  local selected = setAssignment(100, 77, "head")
  local hooks, prepared, state = newSetSearch(policy, {
    setGroup("head", 1, { selected }),
    setGroup("legs", 2, { setAssignment(90, 77, "legs") }),
  })

  hooks.push(state, selected, 1, prepared, {})
  A.equal(hooks.upperBound(state, 2, prepared, {}), 9.5)
end)

test("set optimizer bound retains an already-selected 2pc with no pieces remaining", function()
  local policy = setPreferencePolicy(newAddon())
  local head = setAssignment(100, 77, "head")
  local legs = setAssignment(90, 77, "legs")
  local hooks, prepared, state = newSetSearch(policy, {
    setGroup("head", 1, { head }),
    setGroup("legs", 2, { legs }),
  })

  hooks.push(state, head, 1, prepared, {})
  hooks.push(state, legs, 2, prepared, {})
  A.equal(hooks.upperBound(state, 3, prepared, {}), 9.5)
end)

test("set optimizer bound upgrades two selected plus two reachable pieces to 4pc", function()
  local policy = setPreferencePolicy(newAddon())
  local head = setAssignment(110, 77, "head")
  local shoulders = setAssignment(100, 77, "shoulders")
  local groups = {
    setGroup("head", 1, { head }),
    setGroup("shoulders", 2, { shoulders }),
    setGroup("chest", 3, { setAssignment(105, 77, "chest") }),
    setGroup("legs", 4, { setAssignment(95, 77, "legs") }),
  }
  local hooks, prepared, state = newSetSearch(policy, groups)

  hooks.push(state, head, 1, prepared, {})
  hooks.push(state, shoulders, 2, prepared, {})
  A.equal(hooks.upperBound(state, 3, prepared, {}), 41)
end)

test("set optimizer bound upgrades three selected plus one reachable piece to 4pc", function()
  local policy = setPreferencePolicy(newAddon())
  local head = setAssignment(110, 77, "head")
  local shoulders = setAssignment(100, 77, "shoulders")
  local chest = setAssignment(105, 77, "chest")
  local groups = {
    setGroup("head", 1, { head }),
    setGroup("shoulders", 2, { shoulders }),
    setGroup("chest", 3, { chest }),
    setGroup("legs", 4, { setAssignment(95, 77, "legs") }),
  }
  local hooks, prepared, state = newSetSearch(policy, groups)

  hooks.push(state, head, 1, prepared, {})
  hooks.push(state, shoulders, 2, prepared, {})
  hooks.push(state, chest, 3, prepared, {})
  A.equal(hooks.upperBound(state, 4, prepared, {}), 41)
end)

test("unrelated sets never combine to reach a set threshold", function()
  local policy = setPreferencePolicy(newAddon())
  local selected = setAssignment(100, 77, "set-a")
  local hooks, prepared, state = newSetSearch(policy, {
    setGroup("head", 1, { selected }),
    setGroup("legs", 2, { setAssignment(100, 88, "set-b") }),
  })

  hooks.push(state, selected, 1, prepared, {})
  A.equal(hooks.upperBound(state, 2, prepared, {}), 0)
end)

test("set optimizer push and pop restore exact state without sibling leakage", function()
  local policy = setPreferencePolicy(newAddon())
  local setA = setAssignment(100, 77, "set-a")
  local setB = setAssignment(90, 88, "set-b")
  local hooks, prepared, state = newSetSearch(policy, {
    setGroup("choice", 1, { setA, setB }),
  })

  local undoA = hooks.push(state, setA, 1, prepared, {})
  A.equal(state.sets["set:77"].count, 1)
  hooks.pop(state, undoA, setA, 1, prepared, {})
  A.same(state.sets, {})

  local undoB = hooks.push(state, setB, 1, prepared, {})
  A.falsy(state.sets["set:77"], "the sibling branch must not observe Set A")
  A.equal(state.sets["set:88"].count, 1)
  A.equal(hooks.upperBound(state, 2, prepared, {}), 0)
  hooks.pop(state, undoB, setB, 1, prepared, {})
  A.same(state.sets, {})
end)

test("2pc and 4pc final set preference scores remain authoritative", function()
  local policy = setPreferencePolicy(newAddon())
  local two = {
    a = setAssignment(110, 77, "a"),
    b = setAssignment(90, 77, "b"),
  }
  local four = {
    a = setAssignment(110, 77, "a"),
    b = setAssignment(100, 77, "b"),
    c = setAssignment(105, 77, "c"),
    d = setAssignment(95, 77, "d"),
  }

  A.equal(policy.apply({ assignments = two, summaries = { setCounts = { ["set:77"] = 2 } } }, {}).preferenceAdjustment, 10)
  A.equal(policy.apply({ assignments = four, summaries = { setCounts = { ["set:77"] = 4 } } }, {}).preferenceAdjustment, 41)
end)

test("optimistic cross-set suffix potential never prunes the exhaustive optimum", function()
  local addon = newAddon()
  local policy = setPreferencePolicy(addon)
  local groups = {
    setGroup("head", 1, { setAssignment(100, 77, "a1"), setAssignment(99, 88, "b1") }),
    setGroup("shoulders", 2, { setAssignment(98, 77, "a2"), setAssignment(97, 88, "b2") }),
    setGroup("chest", 3, { setAssignment(96, 77, "a3"), setAssignment(95, 88, "b3") }),
  }
  local hooks, prepared, state = newSetSearch(policy, groups)
  local optimistic = hooks.upperBound(state, 1, prepared, {})

  local expectedScore, expected = -math.huge, nil
  for _, a in ipairs(groups[1].frontier) do
    for _, b in ipairs(groups[2].frontier) do
      for _, c in ipairs(groups[3].frontier) do
        local chosen = { head = a, shoulders = b, chest = c }
        local counts = {}
        for _, assignment in pairs(chosen) do
          for key, count in pairs(assignment.setCounts or {}) do counts[key] = (counts[key] or 0) + count end
        end
        local result = policy.apply({ assignments = chosen, summaries = { setCounts = counts } }, {})
        local score = a.score + b.score + c.score + (result and result.preferenceAdjustment or 0)
        if score > expectedScore then expectedScore, expected = score, chosen end
      end
    end
  end

  A.truthy(optimistic > 10, "the prepared suffix intentionally overestimates incompatible set choices")
  local context = {
    profilePreferences = { preferSetBonuses = true },
    policies = { loadout = {}, preference = { policy } },
  }
  local selected, score = addon.Optimization.LoadoutOptimizer.FindBest(
    groups, addon.Assignments.LoadoutState.New(), context)
  A.equal(score, expectedScore)
  A.equal(selected.head.tag, expected.head.tag)
  A.equal(selected.shoulders.tag, expected.shoulders.tag)
  A.equal(selected.chest.tag, expected.chest.tag)
end)

test("set preference off creates no optimizer policy state overhead", function()
  local addon = newAddon()
  local policy = setPreferencePolicy(addon)
  local counters = {}
  local context = {
    profilePreferences = { preferSetBonuses = false },
    policies = { loadout = {}, preference = { policy } },
    perf = {
      Add = function(_, key, amount) counters[key] = (counters[key] or 0) + (amount or 1) end,
    },
  }
  local selected, score = addon.Optimization.LoadoutOptimizer.FindBest({
    setGroup("head", 1, { setAssignment(100, nil, "plain-1"), setAssignment(90, 77, "tier-1") }),
    setGroup("legs", 2, { setAssignment(100, nil, "plain-2"), setAssignment(90, 77, "tier-2") }),
  }, addon.Assignments.LoadoutState.New(), context)

  A.equal(score, 200)
  A.equal(selected.head.tag, "plain-1")
  A.equal(counters["optimizer.policy_state_pushes"] or 0, 0)
  A.equal(counters["optimizer.policy_state_pops"] or 0, 0)
  A.equal(counters["set_bonus.bound_calls"] or 0, 0)
end)

return tests
