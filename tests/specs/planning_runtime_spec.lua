local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function join(...) return table.concat({ ... }, sep) end

local function loadAddonFile(rel, addon)
  local chunk = assert(loadfile(join(root, "XIVEquip", rel)))
  chunk("XIVEquip", addon)
end

local function newAddon()
  local addon = {
    L = { AddonPrefix = "XIVEquip: " },
    Log = {
      Debug = function() end,
      Info = function() end,
      Warn = function() end,
      Error = function() end,
    },
  }

  _G.XIVEquip_Settings = nil
  loadAddonFile("Global" .. sep .. "Settings.lua", addon)
  loadAddonFile("Core" .. sep .. "ComparerBootstrapper.lua", addon)
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPlanning(root, addon)
  return addon
end

local function registerComparers(addon, pawnUsable)
  addon.Comparers:RegisterComparer("Pawn", {
    Label = "Pawn",
    IsAvailable = function() return pawnUsable == true end,
    PrePass = function() return pawnUsable == true end,
  })
  addon.Comparers:RegisterComparer("ilvl", {
    Label = "Item Level",
    IsAvailable = function() return true end,
  })
end

test("live runtime honors explicit item-level comparer even when Pawn data exists", function()
  local addon = newAddon()
  registerComparers(addon, true)
  _G.XIVEquip_Settings = { SelectedComparer = "ilvl" }
  addon.Pawn = {
    GetBestScaleValuesForPlayer = function()
      return { Strength = 100 }, { key = "pawn-scale", name = "Pawn Scale" }
    end,
    GetActiveScales = function() return { { key = "pawn-scale" } } end,
  }

  local runtime = addon.Planning.Runtime.Live()
  local scale = runtime.ResolveWeights()

  A.equal(scale.source.kind, "ilvl")
  A.equal(runtime.ScoreSource({ weights = scale }), "Item Level")
  A.equal(runtime.ScoreCandidate({ itemLevel = 612 }, { weights = scale }, 16), 612)
  runtime.Close()
end)

test("live runtime falls back to item level when Pawn resolves but has no scale values", function()
  local addon = newAddon()
  registerComparers(addon, true)
  _G.XIVEquip_Settings = { SelectedComparer = "default" }
  addon.Pawn = {
    GetBestScaleValuesForPlayer = function() return nil, nil end,
    GetActiveScales = function() return { { key = "missing-scale" } } end,
  }

  local runtime = addon.Planning.Runtime.Live()
  local ok, scale = pcall(runtime.ResolveWeights)

  A.truthy(ok, "Pawn without values should not crash runtime weight resolution")
  A.equal(scale.source.kind, "ilvl")
  A.equal(runtime.ScoreSource({ weights = scale }), "item-level fallback")
  runtime.Close()
end)

return tests
