-- tests/specs/xivweights_resolver_spec.lua
-- Doc section 13: provider-wins effective-scale composition. Core weights
-- are never filled from a default; only supplemental namespaces (setBonuses)
-- deep-fill, and an explicit value (including zero) is never overwritten.

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function newXIVWeights()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  return addon.XIVWeights
end

test("with no default scale, the provider scale (including supplemental data) passes through unchanged", function()
  local XIVWeights = newXIVWeights()
  local provider = XIVWeights.NewScale({ id = "p", weights = { strength = 1.0 } })
  provider.setBonuses = { [111] = { [4] = { equivalentPrimaryStat = 420 } } }

  local effective = XIVWeights.Resolver.Resolve(provider, nil)

  A.same(effective.weights, { strength = 1.0 })
  A.equal(effective.setBonuses[111][4].equivalentPrimaryStat, 420,
    "provider wins (13.1) must hold even with no default to compose against")
end)

test("a missing core weight is never filled from the default scale", function()
  local XIVWeights = newXIVWeights()
  local provider = XIVWeights.NewScale({ id = "p", weights = { strength = 1.0 } }) -- no haste
  local default = XIVWeights.NewScale({ id = "d", weights = { haste = 1.0 } })

  local effective = XIVWeights.Resolver.Resolve(provider, default)

  A.falsy(effective.weights.haste, "haste should remain absent, not borrowed from the default")
end)

test("supplemental setBonuses data missing from the provider is filled from the default", function()
  local XIVWeights = newXIVWeights()
  local provider = XIVWeights.NewScale({ id = "p" }) -- no setBonuses at all
  local default = XIVWeights.NewScale({
    id = "d",
    meta = {},
  })
  default.setBonuses = { [111] = { [2] = { equivalentPrimaryStat = 180 } } }

  local effective = XIVWeights.Resolver.Resolve(provider, default)

  A.equal(effective.setBonuses[111][2].equivalentPrimaryStat, 180)
end)

test("a provider-supplied setBonuses value, including an explicit zero, is never overwritten by the default", function()
  local XIVWeights = newXIVWeights()
  local provider = XIVWeights.NewScale({ id = "p" })
  provider.setBonuses = { [111] = { [2] = { equivalentPrimaryStat = 0 }, [4] = { equivalentPrimaryStat = 420 } } }
  local default = XIVWeights.NewScale({ id = "d" })
  default.setBonuses = { [111] = { [2] = { equivalentPrimaryStat = 500 }, [4] = { equivalentPrimaryStat = 999 } } }

  local effective = XIVWeights.Resolver.Resolve(provider, default)

  A.equal(effective.setBonuses[111][2].equivalentPrimaryStat, 0, "explicit zero must survive")
  A.equal(effective.setBonuses[111][4].equivalentPrimaryStat, 420, "explicit provider value must survive")
end)

test("resolving does not mutate the original provider or default scales", function()
  local XIVWeights = newXIVWeights()
  local provider = XIVWeights.NewScale({ id = "p" })
  provider.setBonuses = { [111] = { [2] = { equivalentPrimaryStat = 0 } } }
  local default = XIVWeights.NewScale({ id = "d" })
  default.setBonuses = { [111] = { [4] = { equivalentPrimaryStat = 420 } } }

  XIVWeights.Resolver.Resolve(provider, default)

  A.equal(provider.setBonuses[111][4], nil, "provider scale should not gain the default's fields")
  A.falsy(default.setBonuses[111][2], "default scale should be untouched")
end)

return tests
