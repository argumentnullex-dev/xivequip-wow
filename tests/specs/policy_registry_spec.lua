-- tests/specs/policy_registry_spec.lua
-- Doc section 15.7: Register() does only enough validation to reject an
-- obviously malformed declaration; duplicate-id detection is Resolver's job
-- (policy_resolver_spec.lua), not Registry's.

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function newRegistry()
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)
  return addon.Policies.Registry.New()
end

local function validDecl(overrides)
  local decl = { id = "Test.policy", phase = "evaluation_context", apply = function() end }
  for k, v in pairs(overrides or {}) do decl[k] = v end
  return decl
end

test("accepts a minimal valid declaration", function()
  local registry = newRegistry()
  local decl = registry:Register(validDecl())

  A.equal(decl.id, "Test.policy")
  A.equal(#registry:Pending(), 1)
end)

test("accepts optional requires/provides arrays of strings", function()
  local registry = newRegistry()
  registry:Register(validDecl({ requires = { "a" }, provides = { "b", "c" } }))

  A.equal(#registry:Pending(), 1)
end)

-- Note: {id = nil} in a Lua table constructor never actually stores the
-- key, so overriding a field to nil needs an explicit deletion, not
-- validDecl's merge-in-overrides helper.
local function validDeclMissing(field)
  local decl = validDecl()
  decl[field] = nil
  return decl
end

test("rejects a declaration with no id", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDeclMissing("id")) end)
  A.falsy(ok, "missing id should raise")
end)

test("rejects a declaration with no phase", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDeclMissing("phase")) end)
  A.falsy(ok, "missing phase should raise")
end)

test("rejects a declaration with no apply function", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDeclMissing("apply")) end)
  A.falsy(ok, "missing apply should raise")
end)

test("rejects a non-string entry in requires", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDecl({ requires = { 123 } })) end)
  A.falsy(ok, "non-string requires entry should raise")
end)

test("rejects a requires table with non-array keys", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDecl({ requires = { foo = "x" } })) end)
  A.falsy(ok, "a hash-shaped table should not pass as a string array")
end)

test("rejects a requires table with a hole (sparse array)", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDecl({ requires = { [1] = "x", [3] = "y" } })) end)
  A.falsy(ok, "a sparse array should not silently pass validation and lose the gap")
end)

test("accepts a valid groups array", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDecl({ groups = { "weapons" } })) end)
  A.truthy(ok, "a clean string array should be a valid groups declaration")
end)

test("rejects a groups field that is a bare string instead of an array", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDecl({ groups = "weapons" })) end)
  A.falsy(ok, "groups='weapons' would break ipairs(policy.groups) at evaluation time")
end)

test("rejects a groups field shaped as a map instead of an array", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDecl({ groups = { weapons = true } })) end)
  A.falsy(ok, "a map would silently iterate zero entries via ipairs instead of failing loudly")
end)

test("rejects a groups table with a hole (sparse array)", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDecl({ groups = { [1] = "weapons", [3] = "rings" } })) end)
  A.falsy(ok, "a sparse array should not silently pass validation and lose the gap")
end)

test("accepts an empty requires/provides array", function()
  local registry = newRegistry()
  local ok = pcall(function() registry:Register(validDecl({ requires = {}, provides = {} })) end)
  A.truthy(ok, "an empty array is a valid (trivial) string array")
end)

test("registration order is preserved in Pending()", function()
  local registry = newRegistry()
  registry:Register(validDecl({ id = "Test.first" }))
  registry:Register(validDecl({ id = "Test.second" }))

  local pending = registry:Pending()
  A.equal(pending[1].id, "Test.first")
  A.equal(pending[2].id, "Test.second")
end)

test("two pending declarations may share an id -- Registry doesn't police that, Resolver does", function()
  local registry = newRegistry()
  registry:Register(validDecl({ id = "Test.dup" }))
  local ok = pcall(function() registry:Register(validDecl({ id = "Test.dup" })) end)

  A.truthy(ok, "Register itself should not reject a duplicate id")
  A.equal(#registry:Pending(), 2)
end)

test("a fresh registry is not locked", function()
  local registry = newRegistry()
  A.falsy(registry:IsLocked())
end)

test("Lock() closes registration -- a later RegisterPolicy call fails loudly rather than being silently accepted", function()
  local registry = newRegistry()
  registry:Register(validDecl({ id = "Test.before_lock" }))

  registry:Lock()
  local ok = pcall(function() registry:Register(validDecl({ id = "Test.after_lock" })) end)

  A.truthy(registry:IsLocked())
  A.falsy(ok, "registering after Lock() should raise, not silently append to a pending list nothing reads again")
  A.equal(#registry:Pending(), 1, "the late registration should not have been appended")
end)

test("Register() stores a copy, not the caller's own table -- mutating the original afterward has no effect", function()
  local registry = newRegistry()
  local original = validDecl()

  registry:Register(original)
  original.id = "mutated"
  original.apply = function() error("should never run") end

  local stored = registry:Pending()[1]
  A.equal(stored.id, "Test.policy", "the stored copy should be unaffected by mutating the original")
  A.truthy(stored.apply ~= original.apply, "the stored apply function should be unaffected by the mutation")
end)

test("Register() returns the stored snapshot, not the caller's original table", function()
  local registry = newRegistry()
  local original = validDecl()

  local returned = registry:Register(original)

  A.truthy(returned ~= original, "the returned value should be a distinct copy")
  A.equal(returned, registry:Pending()[1])
end)

test("the returned/stored declaration snapshot is itself frozen", function()
  local registry = newRegistry()
  local snapshot = registry:Register(validDecl())

  local ok = pcall(function() snapshot.apply = function() end end)
  A.falsy(ok, "mutating the returned snapshot directly should raise")
end)

test("mutating the caller's original requires/provides array afterward does not affect the stored snapshot", function()
  local registry = newRegistry()
  local requires = { "a" }
  local original = validDecl({ requires = requires })

  registry:Register(original)
  requires[1] = "mutated"
  table.insert(requires, "b")

  local stored = registry:Pending()[1]
  A.same(stored.requires, { "a" })
end)

return tests
