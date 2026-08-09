-- tests/specs/xivweights_pawn_provider_spec.lua
-- Doc section 12/31: Pawn scale-weight conversion, hash-based caching, and
-- converter-version invalidation. Uses a fake adapter (not the real Pawn
-- addon) -- this Provider only converts scale weights, so it has no
-- dependency on Comparers/Pawn/Interface's item-stat/tooltip code.

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

-- A fake Pawn adapter: `state.values` is mutable so tests can simulate the
-- scale changing between resolves.
local function fakeAdapter(initialValues, key, name)
  local state = { values = initialValues }
  local adapter = {
    ListScales = function()
      return { { key = key, name = name, values = state.values } }
    end,
    ResolveValues = function(selection)
      return state.values, { key = key, name = name }
    end,
  }
  return adapter, state
end

test("converts Pawn stat keys into normalized XIVWeights features", function()
  local XIVWeights = newXIVWeights()
  local adapter = fakeAdapter({ Strength = 200, Stamina = 100, CritRating = 50 }, "my-scale", "My Scale")
  local provider = XIVWeights.Providers.Pawn.New(adapter)

  local scale = provider:Resolve(nil, {})

  A.equal(scale.weights.strength, 1.0, "strength is the strongest mapped weight")
  A.equal(scale.weights.stamina, 0.5)
  A.equal(scale.weights.criticalStrike, 0.25)
  A.equal(scale.name, "My Scale")
end)

test("a Pawn scale with only Dps still scores weapon DPS end-to-end through Normalize and the Scorer", function()
  local XIVWeights = newXIVWeights()
  local adapter = fakeAdapter({ Dps = 100 }, "dps-only", "DPS Only")
  local provider = XIVWeights.Providers.Pawn.New(adapter)

  local scale = provider:Resolve(nil, {})
  local score = XIVWeights.Scorer.Score(scale, { weaponDps = 50, weaponMinDamage = 999, weaponMaxDamage = 999 })

  A.equal(scale.weights.weaponDps, 1.0, "Dps should be the (only, therefore strongest) mapped weight")
  A.equal(score, 50, "a converted DPS-only Pawn scale must still score DPS, not silently score zero")
end)

test("weapon-type usability sentinels are dropped rather than copied as scoring weights", function()
  local XIVWeights = newXIVWeights()
  local adapter = fakeAdapter({ Strength = 100, IsAxe1H = -999999, IsOffHand = -999999 }, "s", "S")
  local provider = XIVWeights.Providers.Pawn.New(adapter)

  local scale = provider:Resolve(nil, {})

  for _, feature in ipairs(XIVWeights.FEATURES) do
    A.truthy(scale.weights[feature] ~= nil, "every known feature should still resolve to an explicit number")
  end
  A.equal(scale.weights.strength, 1.0, "the usability sentinel should not have polluted normalization")
end)

test("ListScales returns the adapter's active scale list", function()
  local XIVWeights = newXIVWeights()
  local adapter = fakeAdapter({ Strength = 100 }, "s", "S")
  local provider = XIVWeights.Providers.Pawn.New(adapter)

  local scales = provider:ListScales({})

  A.equal(#scales, 1)
  A.equal(scales[1].key, "s")
end)

test("resolving twice with unchanged source values returns the same cached scale object", function()
  local XIVWeights = newXIVWeights()
  local adapter = fakeAdapter({ Strength = 100 }, "s", "S")
  local provider = XIVWeights.Providers.Pawn.New(adapter)

  local first = provider:Resolve(nil, {})
  local second = provider:Resolve(nil, {})

  A.truthy(first == second, "unchanged source values should hit the cache and return the same object")
end)

test("a changed source weight invalidates the cache and produces a freshly converted scale", function()
  local XIVWeights = newXIVWeights()
  local adapter, state = fakeAdapter({ Strength = 100 }, "s", "S")
  local provider = XIVWeights.Providers.Pawn.New(adapter)

  local first = provider:Resolve(nil, {})
  state.values = { Strength = 200 }
  local second = provider:Resolve(nil, {})

  A.truthy(first ~= second, "changed source weights should invalidate the cache")
end)

test("bumping the converter version invalidates the cache even when source values are unchanged", function()
  local XIVWeights = newXIVWeights()
  local adapter = fakeAdapter({ Strength = 100 }, "s", "S")
  local provider = XIVWeights.Providers.Pawn.New(adapter)
  local originalVersion = XIVWeights.Providers.Pawn.ConverterVersion

  local first = provider:Resolve(nil, {})
  XIVWeights.Providers.Pawn.ConverterVersion = originalVersion + 1
  local second = provider:Resolve(nil, {})
  XIVWeights.Providers.Pawn.ConverterVersion = originalVersion

  A.truthy(first ~= second, "a converter version bump should invalidate previously cached conversions")
end)

return tests
