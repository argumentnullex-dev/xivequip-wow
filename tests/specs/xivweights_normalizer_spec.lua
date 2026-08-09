-- tests/specs/xivweights_normalizer_spec.lua
-- Doc section 8: normalization invariant (max positive weight -> 1.0) and
-- missing-weight-means-zero semantics.

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

test("the strongest positive weight normalizes to 1.0", function()
  local XIVWeights = newXIVWeights()
  local normalized = XIVWeights.Normalizer.Normalize({ strength = 200, stamina = 50 })

  A.equal(normalized.strength, 1.0, "strongest feature should normalize to 1.0")
  A.equal(normalized.stamina, 0.25, "other features should scale proportionally")
end)

test("a feature absent from the input normalizes to zero", function()
  local XIVWeights = newXIVWeights()
  local normalized = XIVWeights.Normalizer.Normalize({ strength = 100 })

  A.equal(normalized.haste, 0, "missing feature should be zero, not nil")
  A.truthy(normalized.haste ~= nil, "missing feature should be an explicit zero entry")
end)

test("every known feature is present in the output even for an empty input", function()
  local XIVWeights = newXIVWeights()
  local normalized = XIVWeights.Normalizer.Normalize({})

  for _, feature in ipairs(XIVWeights.FEATURES) do
    A.equal(normalized[feature], 0, "feature '" .. feature .. "' should default to zero")
  end
end)

test("a scale with only negative (avoid) weights normalizes everything to zero rather than dividing by zero", function()
  local XIVWeights = newXIVWeights()
  local normalized = XIVWeights.Normalizer.Normalize({ strength = -50 })

  A.equal(normalized.strength, 0, "no positive anchor exists, so nothing can be scaled")
end)

test("a nonpositive weight normalizes to zero even once a positive anchor exists", function()
  local XIVWeights = newXIVWeights()
  local normalized = XIVWeights.Normalizer.Normalize({ strength = 100, haste = -50, mastery = 0 })

  A.equal(normalized.strength, 1.0)
  A.equal(normalized.haste, 0, "the native-scale invariant is 0..1 -- there is no negative XIVWeights value")
  A.equal(normalized.mastery, 0, "an explicit zero source weight is still zero")
end)

return tests
