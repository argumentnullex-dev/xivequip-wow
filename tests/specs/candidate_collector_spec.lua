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

test("occupied unresolved equipped slots make the evaluation pending", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = {
      ring = { itemID = 7151, equipLoc = "INVTYPE_FINGER", itemLevel = 300, loaded = false },
    },
    equipped = { [11] = "ring" },
    bags = {},
  })

  local result = addon.Evaluation.CandidateCollector.Collect({ slots = { 11, 12 } })

  A.equal(result.pending, true)
  A.equal(result.equippedBySlot[11], nil, "unresolved equipped item must not masquerade as a complete current slot")
  A.equal(#result.unresolved, 1)
  A.equal(result.unresolved[1].kind, "equipped")
  A.equal(result.unresolved[1].slot, 11)
end)

test("occupied equipped slot with no link is pending, not empty", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = {
      trinket = { itemID = 7152, equipLoc = "INVTYPE_TRINKET", itemLevel = 300 },
    },
    equipped = { [13] = "trinket" },
    bags = {},
  })
  _G.C_Item.GetItemLink = function() return nil end

  local result = addon.Evaluation.CandidateCollector.Collect({ slots = { 13, 14 } })

  A.equal(result.pending, true)
  A.equal(#result.unresolved, 1)
  A.equal(result.unresolved[1].reason, "no-link")
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

test("normalized cache reuses same GUID and link across scans", function()
  local addon = newAddon()
  local calls = 0
  local original = addon.Evaluation.CandidateNormalizer.FromLink
  addon.Evaluation.NormalizedItemCache.Reset()
  addon.Evaluation.CandidateNormalizer.FromLink = function(...)
    calls = calls + 1
    return original(...)
  end
  FakeWorld.Install({
    items = {
      ring = { itemID = 7301, equipLoc = "INVTYPE_FINGER", itemLevel = 300, guid = "guid-ring" },
    },
    bags = { [0] = { "ring" } },
  })

  local first = addon.Evaluation.CandidateCollector.Collect({ slots = { 11 } })
  local second = addon.Evaluation.CandidateCollector.Collect({ slots = { 11 } })

  A.equal(calls, 1)
  A.equal(#first.candidates, 1)
  A.equal(#second.candidates, 1)
  A.equal(second.candidates[1].guid, "guid-ring")
end)

test("normalized cache renormalizes when the same GUID has a changed item link", function()
  local addon = newAddon()
  local calls = 0
  local original = addon.Evaluation.CandidateNormalizer.FromLink
  addon.Evaluation.NormalizedItemCache.Reset()
  addon.Evaluation.CandidateNormalizer.FromLink = function(...)
    calls = calls + 1
    return original(...)
  end
  FakeWorld.Install({
    items = {
      ring = { itemID = 7302, equipLoc = "INVTYPE_FINGER", itemLevel = 300, guid = "guid-ring", link = "|Hitem:7302::::::::::::|h[old]|h" },
    },
    bags = { [0] = { "ring" } },
  })
  addon.Evaluation.CandidateCollector.Collect({ slots = { 11 } })

  FakeWorld.Install({
    items = {
      ring = { itemID = 7302, equipLoc = "INVTYPE_FINGER", itemLevel = 310, guid = "guid-ring", link = "|Hitem:7302:::::::::::::bonus|h[new]|h" },
    },
    bags = { [0] = { "ring" } },
  })
  local second = addon.Evaluation.CandidateCollector.Collect({ slots = { 11 } })

  A.equal(calls, 2)
  A.equal(second.candidates[1].itemLevel, 310)
end)

test("two different GUIDs with the same item ID remain distinct physical candidates", function()
  local addon = newAddon()
  local calls = 0
  local original = addon.Evaluation.CandidateNormalizer.FromLink
  addon.Evaluation.NormalizedItemCache.Reset()
  addon.Evaluation.CandidateNormalizer.FromLink = function(...)
    calls = calls + 1
    return original(...)
  end
  FakeWorld.Install({
    items = {
      ring = { itemID = 7303, equipLoc = "INVTYPE_FINGER", itemLevel = 300 },
    },
    bags = { [0] = { { item = "ring", guid = "guid-a" }, { item = "ring", guid = "guid-b" } } },
  })

  local result = addon.Evaluation.CandidateCollector.Collect({ slots = { 11, 12 } })

  A.equal(calls, 2)
  A.equal(#result.candidates, 2)
  A.truthy(result.candidates[1].guid ~= result.candidates[2].guid)
end)

test("moving an item to another location does not renormalize but refreshes source metadata", function()
  local addon = newAddon()
  local calls = 0
  local original = addon.Evaluation.CandidateNormalizer.FromLink
  addon.Evaluation.NormalizedItemCache.Reset()
  addon.Evaluation.CandidateNormalizer.FromLink = function(...)
    calls = calls + 1
    return original(...)
  end
  FakeWorld.Install({
    items = {
      ring = { itemID = 7304, equipLoc = "INVTYPE_FINGER", itemLevel = 300, guid = "guid-move" },
    },
    bags = { [0] = { "ring" } },
  })
  addon.Evaluation.CandidateCollector.Collect({ slots = { 11 } })

  FakeWorld.Install({
    items = {
      ring = { itemID = 7304, equipLoc = "INVTYPE_FINGER", itemLevel = 300, guid = "guid-move" },
    },
    equipped = { [11] = "ring" },
    bags = {},
  })
  local result = addon.Evaluation.CandidateCollector.Collect({ slots = { 11 } })

  A.equal(calls, 1)
  A.equal(result.equippedBySlot[11].source.kind, "equipped")
  A.equal(result.equippedBySlot[11].source.slot, 11)
end)

test("stale normalized cache entries never cause absent items to appear", function()
  local addon = newAddon()
  addon.Evaluation.NormalizedItemCache.Reset()
  FakeWorld.Install({
    items = {
      ring = { itemID = 7305, equipLoc = "INVTYPE_FINGER", itemLevel = 300, guid = "guid-stale" },
    },
    bags = { [0] = { "ring" } },
  })
  addon.Evaluation.CandidateCollector.Collect({ slots = { 11 } })
  A.equal(addon.Evaluation.NormalizedItemCache.Size(), 1)

  FakeWorld.Install({ items = {}, equipped = {}, bags = {} })
  local empty = addon.Evaluation.CandidateCollector.Collect({ slots = { 11 } })
  addon.Evaluation.CandidateCollector.Collect({ slots = { 11 } })
  addon.Evaluation.NormalizedItemCache.CollectGarbage(1)

  A.equal(#empty.candidates, 0)
  A.equal(addon.Evaluation.NormalizedItemCache.Size(), 0)
end)

test("resolved non-equipment bag items are rejected before full normalization", function()
  local addon = newAddon()
  local calls = 0
  local original = addon.Evaluation.CandidateNormalizer.FromLink
  addon.Evaluation.NormalizedItemCache.Reset()
  addon.Evaluation.CandidateNormalizer.FromLink = function(...)
    calls = calls + 1
    return original(...)
  end
  FakeWorld.Install({
    items = {
      food = { itemID = 7306, equipLoc = nil, itemLevel = 1 },
      helm = { itemID = 7307, equipLoc = "INVTYPE_HEAD", itemLevel = 300 },
    },
    bags = { [0] = { "food", "helm" } },
  })

  local result = addon.Evaluation.CandidateCollector.Collect({ slots = { 1 } })

  A.equal(calls, 1)
  A.equal(#result.candidates, 1)
  A.equal(result.candidates[1].itemID, 7307)
end)

return tests

