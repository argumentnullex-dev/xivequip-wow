-- tests/specs/xivweights_repository_spec.lua
-- Repository storage against an injected backing-store table (doc section
-- 32) -- no SavedVariables coupling in Phase 1.

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

test("saves and retrieves a scale by id", function()
  local XIVWeights = newXIVWeights()
  local repo = XIVWeights.Repository.New()
  local scale = XIVWeights.NewScale({ id = "my-scale", name = "My Scale" })

  repo:Save(scale)

  A.same(repo:Get("my-scale"), scale)
end)

test("lists every saved scale", function()
  local XIVWeights = newXIVWeights()
  local repo = XIVWeights.Repository.New()
  repo:Save(XIVWeights.NewScale({ id = "a" }))
  repo:Save(XIVWeights.NewScale({ id = "b" }))

  local ids = {}
  for _, scale in ipairs(repo:List()) do ids[scale.id] = true end

  A.truthy(ids.a and ids.b, "both saved scales should be listed")
end)

test("deletes a scale and reports whether it existed", function()
  local XIVWeights = newXIVWeights()
  local repo = XIVWeights.Repository.New()
  repo:Save(XIVWeights.NewScale({ id = "gone-soon" }))

  A.truthy(repo:Delete("gone-soon"), "deleting an existing scale should report true")
  A.falsy(repo:Get("gone-soon"), "the scale should no longer be retrievable")
  A.falsy(repo:Delete("gone-soon"), "deleting an already-gone scale should report false")
end)

test("an injected store table is used directly, so callers can back it with SavedVariables", function()
  local XIVWeights = newXIVWeights()
  local store = {}
  local repo = XIVWeights.Repository.New(store)

  repo:Save(XIVWeights.NewScale({ id = "persisted" }))

  A.truthy(store.persisted ~= nil, "the caller's own table should contain the saved scale")
end)

return tests
