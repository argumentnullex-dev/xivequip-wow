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

test("EncodeBase64/DecodeBase64 round-trip against RFC 4648 test vectors", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  -- https://www.rfc-editor.org/rfc/rfc4648#section-10
  local vectors = {
    { "", "" },
    { "f", "Zg==" },
    { "fo", "Zm8=" },
    { "foo", "Zm9v" },
    { "foob", "Zm9vYg==" },
    { "fooba", "Zm9vYmE=" },
    { "foobar", "Zm9vYmFy" },
  }
  for _, vector in ipairs(vectors) do
    local plain, encoded = vector[1], vector[2]
    A.equal(importer.EncodeBase64(plain), encoded, "encoding '" .. plain .. "'")
    A.equal(importer.DecodeBase64(encoded), plain, "decoding '" .. encoded .. "'")
  end
end)

test("DecodeBase64 rejects malformed padding and non-alphabet input", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  A.falsy(importer.DecodeBase64("Zm9v="), "length not a multiple of 4")
  A.falsy(importer.DecodeBase64("Z=8v"), "padding character before the end")
  A.falsy(importer.DecodeBase64("Zg=Z"), "a real character cannot follow padding")
  A.falsy(importer.DecodeBase64("!!!!"), "characters outside the base64 alphabet")
end)

test("detects and parses a base64-encoded XIVEquip JSON export, decoding transparently", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  local json = '{"format":"xivequip-scale","name":"Retribution Copy","specID":70,"weights":{"strength":1,"haste":0.5}}'
  local encoded = importer.EncodeBase64(json)

  A.equal(importer.Detect(encoded), "native-json", "base64-wrapped scale JSON should still be detected as native-json")
  local parsed = assert(importer.Parse(encoded, 70))
  A.equal(parsed.format, "native-json")
  A.equal(parsed.name, "Retribution Copy")
  A.equal(parsed.specID, 70)
  A.equal(parsed.weights.strength, 1)
  A.equal(parsed.weights.haste, 0.5)
end)

test("base64 detection does not falsely trigger on ordinary pasted text", function()
  local addon = newAddon()
  local importer = addon.XIVWeights.Import.Serialized
  -- Real base64-alphabet-only text that is NOT actually an encoded scale
  -- (decodes to bytes that don't look like JSON) must still fail cleanly,
  -- not be misinterpreted as a scale.
  local parsed, reason = importer.Parse("QUJDREVGRw==", 70)
  A.falsy(parsed)
  A.equal(reason, "no-weights")
end)

return tests
