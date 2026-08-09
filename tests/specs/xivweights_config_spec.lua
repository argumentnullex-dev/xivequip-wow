local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function loadSettings(addon)
  local chunk = assert(loadfile(root .. sep .. "XIVEquip" .. sep .. "Global" .. sep .. "Settings.lua"))
  chunk("XIVEquip", addon)
end

local function newAddon(settings)
  local addon = {
    L = { AddonPrefix = "XIVEquip: " },
    Log = { Debug = function() end, Info = function() end, Warn = function() end, Error = function() end, Debugf = function() end },
  }
  _G.XIVEquip_Settings = settings
  loadSettings(addon)
  Bootstrap.LoadWeights(root, addon)
  return addon
end

test("every built-in supported spec has a default scale with valid normalized weights", function()
  local addon = newAddon({})
  local defaults = addon.XIVWeights.Builtin.Defaults

  for classFile, specs in pairs(defaults.Classes) do
    for _, spec in ipairs(specs) do
      local scale = defaults.Get(spec.id)
      A.truthy(scale, "missing default for spec " .. tostring(spec.id))
      A.equal(scale.meta.specID, spec.id)
      local hasPrimaryOne = false
      for _, feature in ipairs(addon.XIVWeights.FEATURES) do
        local value = scale.weights[feature] or 0
        A.truthy(value >= 0 and value <= 1, "weight out of range for " .. tostring(spec.id) .. "/" .. feature)
        if value == 1 then hasPrimaryOne = true end
      end
      A.truthy(hasPrimaryOne, "default should have one primary/top stat at 1.0 for " .. tostring(spec.id))
    end
  end
end)

test("class login generation creates editable spec scale copies for every class spec", function()
  local addon = newAddon({})

  local scales = addon.XIVWeights.Config.EnsureClassSpecScales("PALADIN")

  A.equal(#scales, 3)
  A.truthy(_G.XIVEquip_Settings.XIVWeights.Scales["spec:65"])
  A.truthy(_G.XIVEquip_Settings.XIVWeights.Scales["spec:66"])
  A.truthy(_G.XIVEquip_Settings.XIVWeights.Scales["spec:70"])
  A.equal(_G.XIVEquip_Settings.XIVWeights.Scales["spec:70"].name, "Retribution")
  A.equal(_G.XIVEquip_Settings.XIVWeights.Scales["spec:70"].meta.tiedToSpecID, 70)
end)

test("reset spec scale restores the hard-coded default copy", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local scale = Config.EnsureSpecScale(70)
  scale.weights.haste = 0.99
  Config.SaveScale(scale)

  local reset = Config.ResetSpecScale(70)

  A.equal(reset.weights.haste, 0.3)
  A.equal(reset.source.kind, "xivequip-default-copy")
  A.equal(reset.meta.tiedToSpecID, 70)
end)

test("manual scale validation enforces name, range, and 1.0 anchor", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config

  local ok, err = Config.ValidateAuthoredWeights({ name = "", weights = { strength = 1 } })
  A.falsy(ok)
  A.truthy(err:find("name", 1, true))

  ok, err = Config.ValidateAuthoredWeights({ name = "Bad", weights = { strength = 1.2 } })
  A.falsy(ok)
  A.truthy(err:find("between 0 and 1", 1, true))

  ok, err = Config.ValidateAuthoredWeights({ name = "No Anchor", weights = { strength = 0.9 } })
  A.falsy(ok)
  A.truthy(err:find("1.0", 1, true))

  ok = Config.ValidateAuthoredWeights({ name = "Good", weights = { strength = 1.0, haste = 0.5 } })
  A.truthy(ok)
end)

test("manual scales can be created duplicated and deleted", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config

  local created = Config.CreateManualScale("manual:one", "One", { agility = 1, haste = 0.5 })
  A.truthy(created)
  A.equal(Config.Repository():Get("manual:one").name, "One")

  local duplicated = Config.DuplicateScale("manual:one", "manual:two", "Two")
  A.truthy(duplicated)
  A.equal(duplicated.weights.agility, 1)
  A.equal(duplicated.source.duplicatedFrom, "manual:one")

  A.truthy(Config.DeleteScale("manual:one"))
  A.falsy(Config.Repository():Get("manual:one"))
end)

test("explicit per-spec selection persists without changing generated defaults", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  Config.EnsureSpecScale(70)
  Config.CreateManualScale("manual:ret-custom", "Ret Custom", { strength = 1, mastery = 0.8 })

  Config.SetSpecSelection(70, "manual", "manual:ret-custom")
  local selection = Config.GetSpecSelection(70)

  A.equal(selection.provider, "manual")
  A.equal(selection.scale, "manual:ret-custom")
  A.truthy(Config.Repository():Get("spec:70"), "generated default copy remains available for reset")
end)

test("imported Pawn scale becomes independent manual XIVWeights scale", function()
  local addon = newAddon({})
  local adapterValues = { Strength = 10, HasteRating = 5 }
  local adapter = {
    ListScales = function() return { { key = "pawn-ret", name = "Pawn Ret" } } end,
    ResolveValues = function(selection)
      return adapterValues, { key = selection, name = "Pawn Ret" }
    end,
  }

  local imported = addon.XIVWeights.Import.Pawn.Import(adapter, "pawn-ret", "manual:pawn-ret-copy", "Pawn Ret Copy")
  adapterValues.Strength = 1

  local saved = addon.XIVWeights.Config.Repository():Get("manual:pawn-ret-copy")
  A.same(saved, imported)
  A.equal(saved.weights.strength, 1)
  A.equal(saved.weights.haste, 0.5)
  A.equal(saved.source.kind, "manual")
  A.equal(saved.source.importedFrom, "pawn")
end)

return tests
