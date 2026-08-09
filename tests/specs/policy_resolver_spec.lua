-- tests/specs/policy_resolver_spec.lua
-- Doc section 15.9's Finalize pipeline: reject duplicate ids, validate
-- requires/provides, detect dependency cycles, resolve deterministic
-- order, partition by phase, freeze.

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function newResolver()
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)
  return addon.Policies.Resolver
end

local function decl(id, phase, opts)
  opts = opts or {}
  return {
    id = id,
    phase = phase,
    requires = opts.requires,
    provides = opts.provides,
    groups = opts.groups,
    apply = opts.apply or function() end,
  }
end

test("rejects duplicate policy ids, even across different phases", function()
  local Resolver = newResolver()
  local pending = {
    decl("Test.dup", "evaluation_context"),
    decl("Test.dup", "candidate"),
  }

  local ok = pcall(function() Resolver.Finalize(pending) end)
  A.falsy(ok, "duplicate ids should raise")
end)

test("raises when a requires token has no provider in this phase or any earlier one", function()
  local Resolver = newResolver()
  local pending = { decl("Test.needs_x", "evaluation_context", { requires = { "x" } }) }

  local ok = pcall(function() Resolver.Finalize(pending) end)
  A.falsy(ok, "an unsatisfied requires token should raise")
end)

test("a policy cannot satisfy its own requires by also providing the same token", function()
  local Resolver = newResolver()
  local pending = {
    decl("Test.self_referential", "evaluation_context", { requires = { "x" }, provides = { "x" } }),
  }

  local ok = pcall(function() Resolver.Finalize(pending) end)
  A.falsy(ok, "no *other* policy provides x, so this should raise, not silently pass")
end)

test("a requires token is satisfied when another same-phase policy also provides it, even if the requiring policy provides it too", function()
  local Resolver = newResolver()
  local pending = {
    decl("Test.also_self_provides", "evaluation_context", { requires = { "x" }, provides = { "x" } }),
    decl("Test.real_provider", "evaluation_context", { provides = { "x" } }),
  }

  local resolved = Resolver.Finalize(pending)

  A.equal(resolved.evaluation_context[1].id, "Test.real_provider")
  A.equal(resolved.evaluation_context[2].id, "Test.also_self_provides")
end)

test("a downstream consumer orders after an overriding re-provider even when registered before it", function()
  -- Mirrors the DualWieldOverride shape: Provider sets x first, Override
  -- requires+re-provides x (like DualWieldOverride's live capability
  -- override), and Consumer only requires x. Consumer is registered
  -- *before* Override on purpose -- if Override didn't declare `provides`,
  -- there would be no edge forcing Consumer after it, and Consumer could
  -- run first and observe the pre-override value purely by accident of
  -- registration order (exactly the bug this test guards against).
  local Resolver = newResolver()
  local pending = {
    decl("Test.consumer", "evaluation_context", { requires = { "x" } }),
    decl("Test.provider", "evaluation_context", { provides = { "x" } }),
    decl("Test.override", "evaluation_context", { requires = { "x" }, provides = { "x" } }),
  }

  local resolved = Resolver.Finalize(pending)

  local order = {}
  for i, p in ipairs(resolved.evaluation_context) do order[p.id] = i end

  A.truthy(order["Test.provider"] < order["Test.override"], "override must run after the initial provider")
  A.truthy(order["Test.override"] < order["Test.consumer"], "consumer must run after the override, not just after the initial provider")
end)

test("two same-phase transformers of the same token raise a clear, specific error -- not a silent cycle or an arbitrary order", function()
  -- Without an explicit order between them, two policies that both
  -- require and provide the same token form an unresolvable 2-node cycle
  -- (each must run after the other's transform). This is a genuine
  -- contract limitation (see DualWieldOverride.lua's comment on the
  -- recommended distinct-output-token pattern for a second transformer),
  -- not a bug -- the test asserts the failure is caught early with a
  -- message naming both policies and the token, not a generic
  -- "dependency cycle detected" message that gives no hint of the cause.
  local Resolver = newResolver()
  local pending = {
    decl("Test.provider", "evaluation_context", { provides = { "x" } }),
    decl("Test.overrideA", "evaluation_context", { requires = { "x" }, provides = { "x" } }),
    decl("Test.overrideB", "evaluation_context", { requires = { "x" }, provides = { "x" } }),
  }

  local ok, err = pcall(function() Resolver.Finalize(pending) end)

  A.falsy(ok, "two transformers of the same token should raise")
  A.truthy(tostring(err):find("overrideA", 1, true) and tostring(err):find("overrideB", 1, true),
    "the error should name both conflicting policies, not just report a generic cycle")
end)

test("a requires token satisfied by an earlier phase needs no intra-phase provider", function()
  local Resolver = newResolver()
  local pending = {
    decl("Test.provides_x", "evaluation_context", { provides = { "x" } }),
    decl("Test.needs_x", "candidate", { requires = { "x" } }),
  }

  local resolved = Resolver.Finalize(pending)

  A.equal(#resolved.evaluation_context, 1)
  A.equal(#resolved.candidate, 1)
end)

test("a requires token satisfied by knownProvides needs no registered provider at all", function()
  local Resolver = newResolver()
  local pending = { decl("Test.needs_bootstrap", "evaluation_context", { requires = { "bootstrap.thing" } }) }

  local resolved = Resolver.Finalize(pending, { "bootstrap.thing" })

  A.equal(#resolved.evaluation_context, 1)
end)

test("accepts a valid groups array on an assignment-phase declaration", function()
  local Resolver = newResolver()
  local pending = { decl("Test.scoped", "assignment", { groups = { "weapons" } }) }

  local resolved = Resolver.Finalize(pending)

  A.equal(#resolved.assignment, 1)
end)

test("Finalize raises when groups is a bare string instead of an array", function()
  local Resolver = newResolver()
  local pending = { decl("Test.bad_groups", "assignment", { groups = "weapons" }) }

  local ok = pcall(function() Resolver.Finalize(pending) end)
  A.falsy(ok, "groups='weapons' would break ipairs(policy.groups) at evaluation time")
end)

test("Finalize raises when groups is shaped as a map instead of an array", function()
  local Resolver = newResolver()
  local pending = { decl("Test.bad_groups", "assignment", { groups = { weapons = true } }) }

  local ok = pcall(function() Resolver.Finalize(pending) end)
  A.falsy(ok, "a map would silently iterate zero entries via ipairs instead of failing loudly")
end)

test("Finalize raises when groups has a hole (sparse array)", function()
  local Resolver = newResolver()
  local pending = { decl("Test.bad_groups", "assignment", { groups = { [1] = "weapons", [3] = "rings" } }) }

  local ok = pcall(function() Resolver.Finalize(pending) end)
  A.falsy(ok, "a sparse array should not silently pass validation and lose the gap")
end)

test("orders same-phase policies so a provider runs before whatever requires its value", function()
  local Resolver = newResolver()
  -- Registered out of dependency order on purpose: the consumer first.
  local pending = {
    decl("Test.consumer", "evaluation_context", { requires = { "a" } }),
    decl("Test.provider", "evaluation_context", { provides = { "a" } }),
  }

  local resolved = Resolver.Finalize(pending)

  A.equal(resolved.evaluation_context[1].id, "Test.provider")
  A.equal(resolved.evaluation_context[2].id, "Test.consumer")
end)

test("detects a dependency cycle within a phase", function()
  local Resolver = newResolver()
  local pending = {
    decl("Test.a", "evaluation_context", { requires = { "b" }, provides = { "a" } }),
    decl("Test.b", "evaluation_context", { requires = { "a" }, provides = { "b" } }),
  }

  local ok = pcall(function() Resolver.Finalize(pending) end)
  A.falsy(ok, "a cycle should raise")
end)

test("ordering is deterministic across repeated Finalize calls with the same input", function()
  local Resolver = newResolver()
  local function samePending()
    return {
      decl("Test.c", "evaluation_context"),
      decl("Test.a", "evaluation_context"),
      decl("Test.b", "evaluation_context"),
    }
  end

  local first = Resolver.Finalize(samePending())
  local second = Resolver.Finalize(samePending())

  A.equal(first.evaluation_context[1].id, second.evaluation_context[1].id)
  A.equal(first.evaluation_context[2].id, second.evaluation_context[2].id)
  A.equal(first.evaluation_context[3].id, second.evaluation_context[3].id)
end)

test("a resolved phase array is frozen -- mutation raises", function()
  local Resolver = newResolver()
  local resolved = Resolver.Finalize({ decl("Test.only", "evaluation_context") })

  local ok = pcall(function() resolved.evaluation_context[2] = decl("Test.injected", "evaluation_context") end)
  A.falsy(ok, "mutating a frozen resolved array should raise")
end)

test("declarations are partitioned into the correct phase array", function()
  local Resolver = newResolver()
  local pending = {
    decl("Test.ctx", "evaluation_context"),
    decl("Test.cand", "candidate"),
    decl("Test.asn", "assignment"),
    decl("Test.load", "loadout"),
    decl("Test.pref", "preference"),
  }

  local resolved = Resolver.Finalize(pending)

  A.equal(resolved.evaluation_context[1].id, "Test.ctx")
  A.equal(resolved.candidate[1].id, "Test.cand")
  A.equal(resolved.assignment[1].id, "Test.asn")
  A.equal(resolved.loadout[1].id, "Test.load")
  A.equal(resolved.preference[1].id, "Test.pref")
end)

return tests
