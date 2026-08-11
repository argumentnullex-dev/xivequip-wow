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

return tests
