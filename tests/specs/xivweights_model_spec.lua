-- tests/specs/xivweights_model_spec.lua
-- NewScale's field-preservation contract: it's the one place every other
-- module constructs a Scale record, so any field silently dropped here
-- (e.g. a supplemental namespace like setBonuses) is invisible everywhere
-- downstream, including the Resolver's "provider wins" contract.

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

test("NewScale defaults source/weights/meta when omitted", function()
  local XIVWeights = newXIVWeights()
  local scale = XIVWeights.NewScale()

  A.same(scale.source, { kind = "manual" })
  A.same(scale.weights, {})
  A.same(scale.meta, {})
end)

test("NewScale preserves supplemental fields beyond the well-known ones", function()
  local XIVWeights = newXIVWeights()
  local setBonuses = { [111] = { [4] = { equivalentPrimaryStat = 420 } } }

  local scale = XIVWeights.NewScale({ id = "s", setBonuses = setBonuses })

  A.same(scale.setBonuses, setBonuses)
end)

return tests
