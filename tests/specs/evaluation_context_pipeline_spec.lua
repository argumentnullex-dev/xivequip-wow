-- tests/specs/evaluation_context_pipeline_spec.lua
-- End-to-end: real XIVEquip:RegisterPolicy calls (the 5 built-ins, loaded at
-- file-load time by Bootstrap.LoadPolicyContext) -> Resolver.Finalize ->
-- ContextBuilder.BuildContext. Doc section 15.9/40: built-in and
-- third-party policies must be indistinguishable to the pipeline once
-- registered -- proven here by registering an extra ad hoc policy through
-- the exact same public API and confirming it participates identically.
--
-- This only proves the registry/resolver/builder pipeline treats any
-- caller holding the `addon` table identically -- it does not exercise
-- how a real third-party addon obtains that table in-game
-- (C_AddOns.GetAddOnLocalTable("XIVEquip"), gated by the
-- `AllowAddOnTableAccess` TOC flag -- see PublicAPI/Policies.lua and
-- XIVEquip.toc), which isn't something a plain-Lua test can exercise.

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function baseRuntime(overrides)
  local runtime = {
    UnitClass = function(unit)
      assert(unit == "player", "UnitClass should be called with the 'player' unit token")
      return "Test", "WARRIOR", 1
    end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 72, "Fury" end,
    UnitLevel = function(unit)
      assert(unit == "player", "UnitLevel should be called with the 'player' unit token")
      return 80
    end,
    IsDualWielding = function() return false end,
  }
  for k, v in pairs(overrides or {}) do runtime[k] = v end
  return runtime
end

test("weights resolution is wired end-to-end through the real RegisterPolicy path", function()
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)

  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local sentinelScale = { id = "sentinel" }
  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, baseRuntime({
    ResolveWeights = function() return sentinelScale end,
  }))

  A.same(context.weights, sentinelScale)
end)

test("phase arrays without optional policy content resolve to arrays, not nil", function()
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)

  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, baseRuntime())

  A.truthy(type(context.policies.candidate) == "table")
  A.equal(#context.policies.assignment, 0)
  A.equal(#context.policies.loadout, 0)
  A.equal(#context.policies.preference, 0)
  A.same(context.caches, {})
end)

test("a policy's behavior is fixed at registration time -- mutating the caller's original declaration after Finalize has no effect", function()
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)

  local calls = {}
  local original = {
    id = "Test.mutable_after_register",
    phase = "evaluation_context",
    apply = function() calls[#calls + 1] = "original" end,
  }
  addon:RegisterPolicy(original)

  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  addon.Policies.DefaultRegistry:Lock()

  -- Swap the behavior on the caller's own table *after* finalization --
  -- this must not be reachable through the already-resolved pipeline.
  original.apply = function() calls[#calls + 1] = "swapped" end

  addon.Evaluation.ContextBuilder.BuildContext(resolved, baseRuntime())

  A.same(calls, { "original" },
    "the resolved pipeline must run the function captured at registration time, not a later mutation of the caller's table")
end)

-- Graph-ordering correctness for the "requires and re-provides the same
-- token" override pattern (which DualWieldOverride uses) is proven
-- independent of registration-order coincidence in
-- policy_resolver_spec.lua's "orders after an overriding re-provider"
-- test. This test instead documents the intended third-party consumption
-- pattern against the *real* built-in DualWieldOverride: a downstream
-- policy that only requires the capability sees the override's final
-- value, not the pre-override class/spec default.
test("a downstream policy that requires the dual-wield capability observes DualWieldOverride's final value", function()
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)

  local observed
  addon:RegisterPolicy({
    id = "SomeAddon.observes_dual_wield",
    phase = "evaluation_context",
    requires = { "capability.XIVEquip.allow_dual_wield" },
    apply = function(builder)
      observed = builder:GetCapability("XIVEquip.allow_dual_wield")
    end,
  })

  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  -- Protection Paladin does not normally allow dual-wield -- only the live
  -- override can make this true, so observing true here proves the
  -- downstream policy saw the override's output, not the class/spec default.
  addon.Evaluation.ContextBuilder.BuildContext(resolved, baseRuntime({
    UnitClass = function(unit)
      assert(unit == "player")
      return "Test", "PALADIN", 2
    end,
    GetSpecializationInfo = function() return 66, "Protection" end,
    IsDualWielding = function() return true end,
  }))

  A.truthy(observed, "the downstream policy should observe the override's final true value")
end)

test("a third-party-style policy registered through the same public API participates in the same pipeline", function()
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)

  addon:RegisterPolicy({
    id = "SomeAddon.extra_capability",
    phase = "evaluation_context",
    requires = { "character.class_file" },
    provides = { "capability.SomeAddon.extra" },
    apply = function(builder)
      if builder:Get("classFile") == "WARRIOR" then
        builder:SetCapability("SomeAddon.extra", true)
      end
    end,
  })

  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, baseRuntime())

  A.truthy(context.capabilities["SomeAddon.extra"], "the extra policy should have run and set its capability")
  A.truthy(context.capabilities["XIVEquip.titan_grip"], "built-in policies should still have run normally")
end)

return tests
