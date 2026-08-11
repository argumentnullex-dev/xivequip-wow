local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function newAddon()
  local addon = {}
  Bootstrap.LoadWeights(root, addon)
  return addon
end

test("detects and parses exported XIVEquip JSON", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  local text = '{"format":"xivequip-scale","name":"Retribution Copy","specID":70,"weights":{"strength":1,"haste":0.5}}'
  A.equal(importer.Detect(text), "native-json")
  local parsed = assert(importer.Parse(text, 70))
  A.equal(parsed.format, "native-json")
  A.equal(parsed.name, "Retribution Copy")
  A.equal(parsed.specID, 70)
  A.equal(parsed.weights.strength, 1)
  A.equal(parsed.weights.haste, 0.5)
end)

test("detects Pawn and converts canonical Pawn stat-key formats", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  local text = 'Pawn: v1: "My Scale", Strength=200, HasteRating=100, MasteryRating=50, CritRating=40, AvoidanceRating=20, Speed=20'
  A.equal(importer.Detect(text), "pawn")
  local parsed = assert(importer.Parse(text, 70))
  A.equal(parsed.weights.strength, 1)
  A.equal(parsed.weights.haste, 0.5)
  A.equal(parsed.weights.mastery, 0.25)
  A.equal(parsed.weights.criticalStrike, 0.2)
  A.equal(parsed.weights.avoidance, 0.1)
  A.equal(parsed.weights.weaponSwingIntervalSeconds, 0.1)
end)

test("rejects pasted data without usable weights", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  local parsed, reason = importer.Parse("this is not a scale", 70)
  A.falsy(parsed)
  A.equal(reason, "no-weights")
end)

return tests
