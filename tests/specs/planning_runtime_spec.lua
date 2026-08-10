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

test("live runtime uses built-in spec defaults without starting a legacy comparer", function()
  local addon = newAddon()
  registerComparers(addon, true)
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  _G.XIVEquip_Settings = { SelectedComparer = "pawn" }

  local starts = 0
  addon.Comparers.StartPass = function()
    starts = starts + 1
  end

  local runtime = addon.Planning.Runtime.Live()
  local scale = runtime.ResolveWeights()

  A.equal(starts, 0)
  A.equal(scale.source.kind, "xivequip-default")
  A.equal(scale.meta.specID, 70)
  A.equal(scale.weights.strength, 1)
  A.equal(runtime.ScoreSource({ weights = scale }), "Default: Retribution")
  runtime.Close()
end)

test("live runtime resolves exact configured Pawn scale without legacy comparer selection", function()
  local addon = newAddon()
  registerComparers(addon, true)
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  _G.XIVEquip_Settings = {
    XIVWeights = {
      Scales = {},
      Specs = { [70] = { provider = "pawn", scale = "pawn-ret" } },
    },
  }
  addon.Pawn = {
    GetScaleValues = function(key)
      if key == "pawn-ret" then return { Strength = 10, HasteRating = 5 }, { key = key, name = "Pawn Ret" } end
    end,
    GetActiveScales = function() return { { key = "pawn-ret", name = "Pawn Ret" } } end,
  }

  local runtime = addon.Planning.Runtime.Live()
  local ok, scale = pcall(runtime.ResolveWeights)

  A.truthy(ok)
  A.equal(scale.source.kind, "pawn")
  A.equal(scale.source.key, "pawn-ret")
  A.equal(scale.weights.strength, 1)
  A.equal(scale.weights.haste, 0.5)
  A.equal(runtime.ScoreSource({ weights = scale }), "Pawn: Pawn Ret")
  runtime.Close()
end)

test("live runtimes share the Pawn provider conversion cache for the addon session", function()
  local addon = newAddon()
  local oldLoaded = _G.IsAddOnLoaded
  _G.IsAddOnLoaded = function(name) return name == "Pawn" end
  addon.Pawn = {
    GetScaleValues = function(key)
      return { Strength = 10, HasteRating = 5 }, { key = key, name = "Pawn Ret" }
    end,
    GetActiveScales = function() return { { key = "pawn-ret", name = "Pawn Ret" } } end,
  }

  local first = addon.Planning.Runtime.Live()
  local second = addon.Planning.Runtime.Live()
  local firstProvider = first.PawnProvider()
  local firstScale = firstProvider:Resolve("pawn-ret")
  local secondProvider = second.PawnProvider()
  local secondScale = secondProvider:Resolve("pawn-ret")

  A.equal(firstProvider, secondProvider)
  A.equal(firstScale, secondScale)
  A.equal(firstProvider.cache["pawn-ret"].scale, firstScale)
  first.Close()
  second.Close()
  _G.IsAddOnLoaded = oldLoaded
end)

return tests
