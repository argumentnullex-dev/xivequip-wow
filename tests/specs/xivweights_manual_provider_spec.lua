-- tests/specs/xivweights_manual_provider_spec.lua
-- Doc section 11/32: the native/manual Provider is a thin Repository lookup.

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

test("ListScales returns every scale stored in the repository", function()
  local XIVWeights = newXIVWeights()
  local repo = XIVWeights.Repository.New()
  repo:Save(XIVWeights.NewScale({ id = "a" }))
  repo:Save(XIVWeights.NewScale({ id = "b" }))
  local provider = XIVWeights.Providers.Manual.New(repo)

  local scales = provider:ListScales({})

  A.equal(#scales, 2)
end)

test("Resolve returns the exact scale saved under the selected id", function()
  local XIVWeights = newXIVWeights()
  local repo = XIVWeights.Repository.New()
  local scale = XIVWeights.NewScale({ id = "mine", weights = { strength = 1.0 } })
  repo:Save(scale)
  local provider = XIVWeights.Providers.Manual.New(repo)

  local resolved = provider:Resolve("mine", {})

  A.same(resolved, scale)
end)

test("Resolve raises for an unknown scale id rather than returning a partial/default scale", function()
  local XIVWeights = newXIVWeights()
  local provider = XIVWeights.Providers.Manual.New(XIVWeights.Repository.New())

  local ok = pcall(function() provider:Resolve("does-not-exist", {}) end)

  A.falsy(ok, "resolving an unknown scale id should raise")
end)

return tests
