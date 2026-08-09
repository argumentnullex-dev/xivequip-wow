-- tests/specs/candidate_collector_spec.lua
local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")
local FakeWorld = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "fake_world.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function newAddon()
  local addon = {}
  Bootstrap.LoadCore(root, addon)
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  return addon
end

test("collects currently equipped supported items into the candidate universe", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = {
      ring = { itemID = 7101, equipLoc = "INVTYPE_FINGER", itemLevel = 300 },
      helm = { itemID = 7102, equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4, itemLevel = 300 },
    },
    equipped = { [11] = "ring" },
    bags = { [0] = { "helm" } },
  })

  local result = addon.Evaluation.CandidateCollector.Collect({ slots = { 1, 11, 12 } })

  A.equal(result.pending, false)
  A.equal(result.equippedBySlot[11].itemID, 7101)
  A.equal(#result.candidates, 2, "equipped ring plus bag helm should both be normalized")
end)

test("empty equipped slots are not reported as pending item data", function()
  local addon = newAddon()
  FakeWorld.Install({ items = {}, equipped = {}, bags = {} })

  local result = addon.Evaluation.CandidateCollector.Collect({ slots = { 11, 12, 13, 14 } })

  A.equal(result.pending, false)
  A.equal(#result.unresolved, 0)
  A.equal(#result.candidates, 0)
end)

test("pending bag item data is reported while resolved items still produce a partial candidate set", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = {
      ready = { itemID = 7201, equipLoc = "INVTYPE_FINGER", itemLevel = 300 },
      pending = { itemID = 7202, equipLoc = "INVTYPE_TRINKET", itemLevel = 400, loaded = false },
    },
    bags = { [0] = { "ready", "pending" } },
  })

  local result = addon.Evaluation.CandidateCollector.Collect({ slots = { 11, 12 } })

  A.equal(result.pending, true)
  A.equal(#result.candidates, 1, "the resolved ring should still be available")
  A.equal(result.candidates[1].itemID, 7201)
  A.equal(#result.unresolved, 1)
  A.equal(result.unresolved[1].itemID, 7202)
end)

return tests

