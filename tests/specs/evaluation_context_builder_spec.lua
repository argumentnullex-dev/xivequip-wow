-- tests/specs/evaluation_context_builder_spec.lua
-- ContextBuilder's staging Set/Get + SetCapability/GetCapability roundtrips,
-- Build() shape, and BuildContext's immutability (doc section 5.1: "context
-- is immutable from this point forward").

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
  Bootstrap.LoadPolicyContext(root, addon)
  return addon
end

test("Set/Get roundtrips a plain context field", function()
  local addon = newAddon()
  local builder = addon.Evaluation.ContextBuilder.New({})

  builder:Set("classID", 1)

  A.equal(builder:Get("classID"), 1)
end)

test("SetCapability/GetCapability roundtrips a capability", function()
  local addon = newAddon()
  local builder = addon.Evaluation.ContextBuilder.New({})

  builder:SetCapability("XIVEquip.titan_grip", true)

  A.truthy(builder:GetCapability("XIVEquip.titan_grip"))
end)

test("Build() produces a context table with staged fields and a capabilities sub-table", function()
  local addon = newAddon()
  local builder = addon.Evaluation.ContextBuilder.New({})
  builder:Set("classID", 1)
  builder:SetCapability("XIVEquip.shields", false)

  local context = builder:Build()

  A.equal(context.classID, 1)
  A.equal(context.capabilities["XIVEquip.shields"], false)
end)

test("BuildContext runs every evaluation_context policy in resolved order and attaches the other phase arrays", function()
  local addon = newAddon()
  local calls = {}
  local resolved = {
    evaluation_context = {
      { id = "a", apply = function(builder) calls[#calls + 1] = "a"; builder:Set("fromA", 1) end },
      { id = "b", apply = function(builder) calls[#calls + 1] = "b"; builder:Set("fromB", 2) end },
    },
    candidate = { "candidate-marker" },
    assignment = { "assignment-marker" },
    loadout = { "loadout-marker" },
    preference = { "preference-marker" },
  }

  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, {})

  A.same(calls, { "a", "b" })
  A.equal(context.fromA, 1)
  A.equal(context.fromB, 2)
  A.equal(context.policies.candidate[1], "candidate-marker")
  A.equal(context.policies.assignment[1], "assignment-marker")
  A.equal(context.policies.loadout[1], "loadout-marker")
  A.equal(context.policies.preference[1], "preference-marker")
end)

test("the built context is frozen -- assigning a new top-level field raises", function()
  local addon = newAddon()
  local resolved = { evaluation_context = {}, candidate = {}, assignment = {}, loadout = {}, preference = {} }

  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, {})
  local ok = pcall(function() context.someNewField = 1 end)

  A.falsy(ok, "assigning to a frozen context should raise")
end)

test("the built context blocks overwriting an existing field, not just adding new ones", function()
  local addon = newAddon()
  local resolved = {
    evaluation_context = { { id = "a", apply = function(builder) builder:Set("classID", 1) end } },
    candidate = {}, assignment = {}, loadout = {}, preference = {},
  }

  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, {})
  local ok = pcall(function() context.classID = 999 end)

  A.falsy(ok, "overwriting an existing frozen field should raise")
  A.equal(context.classID, 1, "the original value should be unaffected by the failed write")
end)

test("context.capabilities is frozen, not just the outer context table", function()
  local addon = newAddon()
  local resolved = {
    evaluation_context = { { id = "a", apply = function(builder) builder:SetCapability("XIVEquip.titan_grip", true) end } },
    candidate = {}, assignment = {}, loadout = {}, preference = {},
  }

  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, {})

  local okNew = pcall(function() context.capabilities["XIVEquip.some_new_thing"] = true end)
  local okOverwrite = pcall(function() context.capabilities["XIVEquip.titan_grip"] = false end)

  A.falsy(okNew, "adding a new capability after context construction should raise")
  A.falsy(okOverwrite, "overwriting an existing capability after context construction should raise")
  A.truthy(context.capabilities["XIVEquip.titan_grip"], "the original capability value should be unaffected")
end)

test("context.policies is frozen, not just the outer context table -- a whole phase array can't be swapped out", function()
  local addon = newAddon()
  local resolved = {
    evaluation_context = {},
    candidate = { "candidate-marker" }, assignment = {}, loadout = {}, preference = {},
  }

  local context = addon.Evaluation.ContextBuilder.BuildContext(resolved, {})
  local ok = pcall(function() context.policies.candidate = {} end)

  A.falsy(ok, "replacing a resolved phase array through context.policies should raise")
  A.equal(context.policies.candidate[1], "candidate-marker", "the original phase array should be unaffected")
end)

return tests
