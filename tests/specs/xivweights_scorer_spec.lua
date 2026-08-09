-- tests/specs/xivweights_scorer_spec.lua
-- Doc section 10.2-10.4: weighted-sum scoring plus the weapon min/max-vs-dps
-- preference branch. Pure math -- no item-fetching involved.

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

test("scores a plain stat feature vector as a weighted sum", function()
  local XIVWeights = newXIVWeights()
  local scale = XIVWeights.NewScale({ weights = { strength = 1.0, stamina = 0.5 } })

  local score = XIVWeights.Scorer.Score(scale, { strength = 100, stamina = 40 })

  A.equal(score, 100 * 1.0 + 40 * 0.5)
end)

test("a feature with no weight on the scale contributes nothing", function()
  local XIVWeights = newXIVWeights()
  local scale = XIVWeights.NewScale({ weights = { strength = 1.0 } })

  local score = XIVWeights.Scorer.Score(scale, { strength = 100, haste = 999 })

  A.equal(score, 100, "haste has no weight on this scale, so it should be ignored")
end)

test("prefers min/max damage weighting over dps when the scale values min/max", function()
  local XIVWeights = newXIVWeights()
  local scale = XIVWeights.NewScale({ weights = { weaponMinDamage = 1.0, weaponMaxDamage = 1.0, weaponDps = 5.0 } })

  local score = XIVWeights.Scorer.Score(scale, { weaponMinDamage = 100, weaponMaxDamage = 200, weaponDps = 9999 })

  A.equal(score, 100 * 1.0 + 200 * 1.0, "dps weight should be ignored once min/max weights are present")
end)

test("falls back to dps weighting when the scale has no min/max weight", function()
  local XIVWeights = newXIVWeights()
  local scale = XIVWeights.NewScale({ weights = { weaponDps = 2.0 } })

  local score = XIVWeights.Scorer.Score(scale, { weaponDps = 50, weaponMinDamage = 999 })

  A.equal(score, 100, "min damage should be ignored -- no min/max weight is present on the scale")
end)

test("a normalized DPS-only scale still scores weapon DPS, despite Normalize emitting explicit zeros for min/max", function()
  local XIVWeights = newXIVWeights()
  -- A scale built by hand can simply omit weaponMinDamage/weaponMaxDamage,
  -- but a *normalized* scale (as every Provider produces) always carries an
  -- explicit 0 for every absent feature per Normalizer's 8.2 semantics --
  -- and 0 is truthy in Lua, so this is the case that actually exercises the
  -- "has a min/max weight" branch condition.
  local weights = XIVWeights.Normalizer.Normalize({ weaponDps = 100 })
  local scale = XIVWeights.NewScale({ weights = weights })

  A.equal(scale.weights.weaponMinDamage, 0, "sanity check: Normalize really does emit an explicit zero")

  local score = XIVWeights.Scorer.Score(scale, { weaponDps = 50, weaponMinDamage = 999, weaponMaxDamage = 999 })

  A.equal(score, 50, "a DPS-only scale must still score DPS, not silently score zero")
end)

test("an unrecognized feature key in the vector is silently ignored", function()
  local XIVWeights = newXIVWeights()
  local scale = XIVWeights.NewScale({ weights = { strength = 1.0 } })

  local score = XIVWeights.Scorer.Score(scale, { strength = 10, someFutureFeature = 99999 })

  A.equal(score, 10)
end)

return tests
