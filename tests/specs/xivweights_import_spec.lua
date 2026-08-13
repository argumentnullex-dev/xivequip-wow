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

test("parses a real Raidbots stat-weights Pawn export", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  local text = '( Pawn: v1: "talkamar - Retribution - Patchwerk (Raidbots)": Class=Paladin, Spec=Retribution, '
    .. "Strength=24.53, CritRating=9.60, HasteRating=8.57, MasteryRating=11.47, Versatility=8.86, Dps=134.17 )"
  A.equal(importer.Detect(text), "pawn")
  local parsed = assert(importer.Parse(text, 70))
  A.equal(parsed.name, "talkamar - Retribution - Patchwerk (Raidbots)")
  A.equal(parsed.weights.weaponDps, 1, "Dps is the largest raw value, so it anchors the normalized scale")
  A.truthy(parsed.weights.strength < 1 and parsed.weights.strength > 0, "Strength should normalize to a fraction of Dps, not be dropped")
  A.equal(parsed.weights.criticalStrike, 9.60 / 134.17)
  A.equal(parsed.weights.haste, 8.57 / 134.17)
  A.equal(parsed.weights.mastery, 11.47 / 134.17)
  A.equal(parsed.weights.versatility, 8.86 / 134.17)
end)

test("detects and parses a Wowhead multi-line priority paste (abbreviated stat names)", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  local text = "Agility\nCrit\nMastery\nHaste\nVersatility"
  A.equal(importer.Detect(text), "priority-list")
  local parsed = assert(importer.Parse(text, 70))
  A.equal(parsed.format, "priority-list")
  A.equal(parsed.weights.agility, 1.0)
  A.equal(parsed.weights.criticalStrike, 0.5)
  A.equal(parsed.weights.mastery, 0.375)
  A.equal(parsed.weights.haste, 0.25)
  A.equal(parsed.weights.versatility, 0.125)
end)

test("detects and parses a Wowhead multi-line priority paste (full stat names)", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  local text = "Agility\nCritical Strike\nMastery\nHaste\nVersatility"
  A.equal(importer.Detect(text), "priority-list")
  local parsed = assert(importer.Parse(text, 70))
  A.equal(parsed.weights.agility, 1.0)
  A.equal(parsed.weights.criticalStrike, 0.5)
  A.equal(parsed.weights.mastery, 0.375)
  A.equal(parsed.weights.haste, 0.25)
  A.equal(parsed.weights.versatility, 0.125)
end)

test("detects and parses an inline '>' priority list", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  local text = "Strength > Crit > Haste > Mastery > Versatility"
  A.equal(importer.Detect(text), "priority-list")
  local parsed = assert(importer.Parse(text, 70))
  A.equal(parsed.weights.strength, 1.0)
  A.equal(parsed.weights.criticalStrike, 0.5)
  A.equal(parsed.weights.haste, 0.375)
  A.equal(parsed.weights.mastery, 0.25)
  A.equal(parsed.weights.versatility, 0.125)
end)

test("a lone stat name is not treated as a priority list", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  A.equal(importer.Detect("Mastery"), "text")
end)

return tests
