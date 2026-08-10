local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function near(actual, expected, message)
  actual = tonumber(actual)
  expected = tonumber(expected)
  if not actual or not expected or math.abs(actual - expected) > 0.000001 then
    error(string.format("%s: expected %s, got %s", message or "assertion failed", tostring(expected), tostring(actual)), 2)
  end
end

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

test("Demon Hunter defaults include Midnight Devourer", function()
  local addon = newAddon({})
  local defaults = addon.XIVWeights.Builtin.Defaults
  local specs = defaults.SpecsForClass("DEMONHUNTER")

  A.equal(#specs, 3)
  A.equal(specs[3].id, 1480)
  A.equal(specs[3].name, "Devourer")

  local scale = defaults.Get(1480)
  A.truthy(scale)
  A.equal(scale.weights.intellect, 1)
  near(scale.weights.haste, 0.5)
  near(scale.weights.mastery, 0.4)
  near(scale.weights.criticalStrike, 0.3)
  near(scale.weights.versatility, 0.2)
  A.equal(scale.source.specID, 1480)
  A.truthy(scale.source.guide:find("devourer", 1, true))
  A.equal(scale.source.reviewedAt, "2026-08-10")
end)

test("Protection Paladin default uses survivability stat order", function()
  local addon = newAddon({})
  local scale = addon.XIVWeights.Builtin.Defaults.Get(66)

  A.equal(scale.weights.strength, 1)
  near(scale.weights.haste, 0.5)
  near(scale.weights.versatility, 0.4)
  near(scale.weights.mastery, 0.3)
  near(scale.weights.criticalStrike, 0.2)
  A.truthy(scale.source.guide:find("paladin/protection", 1, true))
end)

test("reviewed examples preserve current Wowhead priority ordering", function()
  local addon = newAddon({})
  local defaults = addon.XIVWeights.Builtin.Defaults

  local fury = defaults.Get(72)
  near(fury.weights.haste, 0.5)
  near(fury.weights.mastery, 0.4)
  near(fury.weights.criticalStrike, 0.3)
  near(fury.weights.versatility, 0.2)

  local outlaw = defaults.Get(260)
  near(outlaw.weights.haste, 0.5)
  near(outlaw.weights.criticalStrike, 0.4)
  near(outlaw.weights.versatility, 0.4)
  near(outlaw.weights.mastery, 0.3)

  local brewmaster = defaults.Get(268)
  near(brewmaster.weights.versatility, 0.5)
  near(brewmaster.weights.criticalStrike, 0.5)
  near(brewmaster.weights.mastery, 0.5)
  near(brewmaster.weights.haste, 0.4)
end)

test("weapon-damage defaults value weapon DPS when the guide calls it out", function()
  local addon = newAddon({})
  local defaults = addon.XIVWeights.Builtin.Defaults

  local beastMastery = defaults.Get(253)
  A.equal(beastMastery.weights.weaponDps, 1)
  near(beastMastery.weights.agility, 0.9)
  near(beastMastery.weights.mastery, 0.5)
  A.equal(beastMastery.meta.weaponDpsPriority, "abovePrimary")

  local lowerDpsMoreAgility = addon.XIVWeights.Scorer.Score(beastMastery, { weaponDps = 100, agility = 1000 })
  local higherDpsLessAgility = addon.XIVWeights.Scorer.Score(beastMastery, { weaponDps = 110, agility = 990 })
  A.truthy(higherDpsLessAgility > lowerDpsMoreAgility, "BM default should not ignore weapon DPS")

  local arms = defaults.Get(71)
  local fury = defaults.Get(72)
  A.equal(arms.weights.weaponDps, 1)
  A.equal(fury.weights.weaponDps, 1)
  A.equal(arms.meta.weaponDpsPriority, "withPrimary")
  A.equal(fury.meta.weaponDpsPriority, "withPrimary")
end)

test("explicit class copy generation creates editable spec scale copies without selecting them", function()
  local addon = newAddon({})

  local scales = addon.XIVWeights.Config.EnsureClassSpecScales("PALADIN")

  A.equal(#scales, 3)
  A.truthy(_G.XIVEquip_Settings.XIVWeights.Scales["spec:65"])
  A.truthy(_G.XIVEquip_Settings.XIVWeights.Scales["spec:66"])
  A.truthy(_G.XIVEquip_Settings.XIVWeights.Scales["spec:70"])
  A.equal(_G.XIVEquip_Settings.XIVWeights.Scales["spec:70"].name, "Retribution")
  A.equal(_G.XIVEquip_Settings.XIVWeights.Scales["spec:70"].meta.tiedToSpecID, 70)
  A.equal(_G.XIVEquip_Settings.XIVWeights.Specs[70], nil)
end)

test("default provider lists built-in scales without creating SavedVariables copies", function()
  local addon = newAddon({})
  local provider = addon.XIVWeights.Providers.Default.New(addon.XIVWeights.Config)

  local list = provider:ListScales({ classFile = "PALADIN" })
  local xw = _G.XIVEquip_Settings and _G.XIVEquip_Settings.XIVWeights

  A.equal(#list, 3)
  A.equal(list[3].meta.specID, 70)
  A.equal(xw and xw.Scales and xw.Scales["spec:70"] or nil, nil)
end)

test("reset spec scale restores the hard-coded default copy", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local scale = Config.EnsureSpecScale(70)
  scale.weights.haste = 0.99
  Config.SaveScale(scale)

  local reset = Config.ResetSpecScale(70)

  near(reset.weights.haste, 0.3)
  A.equal(reset.source.kind, "xivequip-default-copy")
  A.equal(reset.meta.tiedToSpecID, 70)
  A.equal(Config.GetSpecSelection(70).provider, "manual")
  A.equal(Config.GetSpecSelection(70).scale, "spec:70")
end)

test("built-in default resolution ignores edited generated spec copy", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local generated = Config.EnsureSpecScale(66)
  generated.weights.haste = 0.01
  generated.weights.versatility = 0.02
  Config.SaveScale(generated)

  Config.SetSpecSelection(66, "default", nil)
  local resolved = Config.ResolveForSpec(66)

  A.equal(resolved.source.kind, "xivequip-default")
  near(resolved.weights.haste, 0.5)
  near(resolved.weights.versatility, 0.4)
  near(resolved.weights.mastery, 0.3)
  near(resolved.weights.criticalStrike, 0.2)
end)

test("fresh spec selection defaults to immutable built-in default", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config

  local selection = Config.GetSpecSelection(70)
  local resolved = Config.ResolveForSpec(70)

  A.equal(selection.provider, "default")
  A.equal(selection.scale, nil)
  A.equal(resolved.source.kind, "xivequip-default")
  A.equal(_G.XIVEquip_Settings.XIVWeights.Scales["spec:70"], nil)
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

test("new manual scale seed uses the current spec primary stat", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config

  local mage = Config.NewManualScaleSeed(62)
  A.equal(mage.intellect, 1)
  A.equal(mage.strength, nil)

  local rogue = Config.NewManualScaleSeed(260)
  A.equal(rogue.agility, 1)
  A.equal(rogue.strength, nil)

  local unknown = Config.NewManualScaleSeed(999999)
  A.equal(unknown.strength, 1)
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
