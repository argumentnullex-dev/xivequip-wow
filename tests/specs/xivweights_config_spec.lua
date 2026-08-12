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

test("resolved scale display labels use the compact source and scale format", function()
  local addon = newAddon({})
  local display = addon.XIVWeights.Config.ResolvedScaleDisplayLabel

  A.equal(display({ resolution = { sourceLabel = "Default", scaleLabel = "Retribution" } }),
    "Default | Retribution")
  A.equal(display({ resolution = { sourceLabel = "Custom", scaleLabel = "Retribution", defaultCopy = true } }),
    "Custom | Default (Retribution)")
  A.equal(display({ resolution = { sourceLabel = "Custom", scaleLabel = "Retribution SBA" } }),
    "Custom | Retribution SBA")
  A.equal(display({ resolution = { sourceLabel = "Pawn", scaleLabel = "Paladin: Retribution" } }),
    "Pawn | Paladin: Retribution")
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

test("Automatic Profile resolution prefers a usable Pawn scale", function()
  local addon = newAddon({})
  local pawnScale = addon.XIVWeights.NewScale({
    id = "pawn:protection",
    name = "Protection",
    source = { kind = "pawn", key = "pawn:protection" },
    weights = { strength = 1, haste = 0.8 },
  })
  local runtime = {
    UnitClass = function() return "Paladin", "PALADIN" end,
    UnitName = function() return "Daedric", "Area 52" end,
    PawnProvider = function()
      return { Resolve = function() return pawnScale end }
    end,
  }

  local result = addon.XIVWeights.Config.ResolveResultForSpec(66, runtime)

  A.equal(result.profile.automatic, true)
  A.equal(result.scale.source.kind, "pawn")
  A.equal(result.scale.resolution.sourceLabel, "Pawn")
  A.equal(result.scale.resolution.scaleLabel, "Protection")
  A.falsy(result.fallback)
end)

test("Automatic Profile falls back to the spec Default when no Integration is usable", function()
  local addon = newAddon({})
  local runtime = {
    UnitClass = function() return "Paladin", "PALADIN" end,
    UnitName = function() return "Daedric", "Area 52" end,
    PawnProvider = function() return nil end,
  }

  local result = addon.XIVWeights.Config.ResolveResultForSpec(66, runtime)

  A.equal(result.scale.source.kind, "xivequip-default")
  A.equal(result.scale.resolution.sourceLabel, "Default")
  A.equal(result.scale.resolution.scaleLabel, "Protection")
  A.equal(result.fallback, false)
  A.equal(result.fallbackReason, nil)
end)

test("Profile Integration resolution preserves opaque provider ids and source labels", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local Profiles = addon.Profiles.Config
  local registry = addon.Integrations.Registry
  local integrationScale = addon.XIVWeights.NewScale({
    id = "hypothetical:protection",
    name = "Hypothetical Protection",
    source = { kind = "hypothetical" },
    weights = { strength = 1, haste = 0.8 },
  })
  registry:Register({
    id = "hypotheticalA",
    label = "Hypothetical A",
    automaticPriority = 10,
    IsAvailable = function() return true end,
    Resolve = function(_, selection)
      A.equal(selection, "hypothetical:protection")
      return integrationScale
    end,
  })

  local profile = Profiles.GetDefault("PALADIN")
  A.truthy(Profiles.SetAutomatic(profile, false))
  A.truthy(Profiles.SetManualMode(profile, "integration"))
  A.truthy(Profiles.SetIntegrationProvider(profile, "hypotheticalA"))
  A.truthy(Profiles.SetIntegrationOverride(profile, 66, "hypothetical:protection"))

  local result = Config.ResolveResultForSpec(66, {
    UnitClass = function() return "Paladin", "PALADIN" end,
    UnitName = function() return "Daedric", "Area 52" end,
  })

  A.equal(result.selection.provider, "hypotheticalA")
  A.equal(result.scale.resolution.sourceKind, "integration")
  A.equal(result.scale.resolution.sourceLabel, "Hypothetical A")
  A.equal(result.scale.resolution.scaleLabel, "Hypothetical Protection")
  A.falsy(result.fallback)
end)

test("failed Pawn Integration falls back to Default without resolving a manual scale", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local Profiles = addon.Profiles.Config
  local profile = Profiles.GetDefault("PALADIN")
  local manual = Config.CreateManualScale("shared:protection", "Wrong Manual", { strength = 1 }, 66)

  A.truthy(Profiles.SetAutomatic(profile, false))
  A.truthy(Profiles.SetManualMode(profile, "integration"))
  A.truthy(Profiles.SetIntegrationProvider(profile, "pawn"))
  A.truthy(Profiles.SetIntegrationOverride(profile, 66, manual.id))

  local result = Config.ResolveResultForSpec(66, {
    UnitClass = function() return "Paladin", "PALADIN" end,
    UnitName = function() return "Daedric", "Area 52" end,
    PawnProvider = function()
      return { Resolve = function() return nil end }
    end,
  })

  A.equal(result.scale.source.kind, "xivequip-default")
  A.equal(result.scale.resolution.sourceLabel, "Default")
  A.equal(result.scale.resolution.fallback, true)
  A.equal(result.fallbackReason, "integration-scale-missing")
  A.equal(result.configuredSelection.provider, "pawn")
  A.equal(result.scale.resolution.configuredProvider, "pawn")
  A.equal(profile.manual.integration.provider, "pawn")
  A.equal(profile.manual.integration.overrides[66], manual.id)
end)

test("missing pinned Integration scale falls back through the provider recommendation before Default", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local Profiles = addon.Profiles.Config
  local registry = addon.Integrations.Registry
  local recommended = addon.XIVWeights.NewScale({
    id = "hypothetical:recommended",
    name = "Recommended Protection",
    source = { kind = "hypothetical" },
    weights = { strength = 1, haste = 0.8 },
  })
  registry:Register({
    id = "hypothetical-fallback",
    label = "Hypothetical",
    IsAvailable = function() return true end,
    Resolve = function(_, selection)
      if selection == nil then return recommended end
      return nil, "integration-scale-missing"
    end,
  })
  local profile = Profiles.GetDefault("PALADIN")
  A.truthy(Profiles.SetAutomatic(profile, false))
  A.truthy(Profiles.SetManualMode(profile, "integration"))
  A.truthy(Profiles.SetIntegrationProvider(profile, "hypothetical-fallback"))
  A.truthy(Profiles.SetIntegrationOverride(profile, 66, "removed:pinned-scale"))

  local result = Config.ResolveResultForSpec(66, {
    UnitClass = function() return "Paladin", "PALADIN" end,
    UnitName = function() return "Daedric", "Area 52" end,
  })

  A.equal(result.scale.id, recommended.id)
  A.equal(result.scale.resolution.sourceLabel, "Hypothetical")
  A.equal(result.scale.resolution.scaleLabel, "Recommended Protection")
  A.equal(result.selection.scale, nil, "effective selection should follow the provider recommendation")
  A.equal(result.configuredSelection.scale, "removed:pinned-scale", "missing pin should remain diagnostic context")
  A.equal(result.fallback, true)
  A.equal(result.fallbackReason, "integration-scale-missing")
end)

test("failed generic Integration falls back to Default and never resolves a manual key", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local Profiles = addon.Profiles.Config
  local registry = addon.Integrations.Registry
  registry:Register({
    id = "hypothetical-failing",
    label = "Hypothetical",
    IsAvailable = function() return true end,
    Resolve = function() return nil, "integration-scale-missing" end,
  })
  local profile = Profiles.GetDefault("PALADIN")
  local manual = Config.CreateManualScale("shared:protection", "Wrong Manual", { strength = 1 }, 66)

  A.truthy(Profiles.SetAutomatic(profile, false))
  A.truthy(Profiles.SetManualMode(profile, "integration"))
  A.truthy(Profiles.SetIntegrationProvider(profile, "hypothetical-failing"))
  A.truthy(Profiles.SetIntegrationOverride(profile, 66, manual.id))

  local result = Config.ResolveResultForSpec(66, {
    UnitClass = function() return "Paladin", "PALADIN" end,
    UnitName = function() return "Daedric", "Area 52" end,
  })

  A.equal(result.scale.source.kind, "xivequip-default")
  A.equal(result.scale.resolution.sourceLabel, "Default")
  A.equal(result.scale.resolution.fallback, true)
  A.equal(result.fallbackReason, "integration-scale-missing")
  A.equal(result.configuredSelection.provider, "hypothetical-failing")
end)

test("Profile mutation APIs enforce spec ownership for Custom scales", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local Profiles = addon.Profiles.Config
  local profile = Profiles.GetDefault("PALADIN")
  local holy = Config.CreateManualScale("custom:holy", "Holy Custom", { intellect = 1 }, 65)

  local selected, reason = Profiles.SetCustomOverride(profile, 66, holy.id)
  A.equal(selected, nil)
  A.equal(reason, "scale-spec-mismatch")

  selected = Profiles.SetCustomOverride(profile, 65, holy.id)
  A.equal(selected, profile)
  A.equal(profile.manual.customOverrides[65], holy.id)
  local warrior = Config.CreateManualScale("custom:arms", "Arms Custom", { strength = 1 }, 71)
  selected, reason = Profiles.SetCustomOverride(profile, 71, warrior.id)
  A.equal(selected, nil)
  A.equal(reason, "spec-class-mismatch")
  selected, reason = Profiles.SetIntegrationOverride(profile, 71, "arms-integration")
  A.equal(selected, nil)
  A.equal(reason, "spec-class-mismatch")
  selected, reason = Profiles.SetIntegrationOverride(profile, 999999, "unknown-integration-scale")
  A.equal(selected, nil)
  A.equal(reason, "unknown-spec")
  A.equal(Profiles.ClearCustomOverride(profile, 65), profile)
end)

test("Custom scale creation rejects unknown specializations", function()
  local addon = newAddon({})
  local created, reason = addon.XIVWeights.Config.CreateManualScale(
    "custom:unknown", "Unknown", { strength = 1 }, 999999)

  A.equal(created, nil)
  A.equal(reason, "unknown-spec")
end)

test("Custom scale creation requires a specialization owner", function()
  local addon = newAddon({})
  local created, reason = addon.XIVWeights.Config.CreateManualScale("custom:unscoped", "Unscoped", { strength = 1 })

  A.equal(created, nil)
  A.equal(reason, "spec-required")
end)

test("Custom Profile mode uses a spec-matching override and leaves other specs on Default", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local Profiles = addon.Profiles.Config
  local custom = Config.CreateManualScale("custom:protection", "Protection Raid", { strength = 1, haste = 0.9 }, 66)
  local profile = Profiles.GetDefault("PALADIN")
  profile.automatic = false
  profile.manual.mode = "custom"
  profile.manual.customOverrides[66] = custom.id

  local runtime = {
    UnitClass = function() return "Paladin", "PALADIN" end,
    UnitName = function() return "Daedric", "Area 52" end,
  }
  local selected = Config.ResolveResultForSpec(66, runtime)
  local defaulted = Config.ResolveResultForSpec(70, runtime)

  A.equal(selected.scale.source.kind, "manual")
  A.equal(selected.scale.resolution.sourceLabel, "Custom")
  A.equal(selected.scale.resolution.scaleLabel, "Protection Raid")
  A.equal(defaulted.scale.source.kind, "xivequip-default")
  A.equal(defaulted.scale.resolution.sourceLabel, "Default")
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

test("new manual scale seed clones the spec Default weights", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local defaults = addon.XIVWeights.Builtin.Defaults

  local protection = Config.NewManualScaleSeed(66)
  local expected = defaults.Get(66).weights
  local originalHaste = expected.haste
  A.same(protection, expected)
  protection.haste = 0
  A.equal(expected.haste, originalHaste)

  local mage = Config.NewManualScaleSeed(62)
  A.equal(mage.intellect, 1)
  A.equal(mage.strength, nil)

  local rogue = Config.NewManualScaleSeed(260)
  A.equal(rogue.agility, 1)
  A.equal(rogue.strength, nil)

  local unknown = Config.NewManualScaleSeed(999999)
  A.equal(unknown.strength, 1)
end)

test("creating a custom scale without weights clones the spec Default", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local defaults = addon.XIVWeights.Builtin.Defaults

  local created = Config.CreateManualScale("custom:seeded", "Seeded", nil, 66)
  A.same(created.weights, defaults.Get(66).weights)
  local originalHaste = defaults.Get(66).weights.haste
  created.weights.haste = 0
  A.equal(defaults.Get(66).weights.haste, originalHaste)
end)

test("manual scales can be created duplicated and deleted", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config

  local created = Config.CreateManualScale("manual:one", "One", { agility = 1, haste = 0.5 }, 260)
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
  Config.CreateManualScale("manual:ret-custom", "Ret Custom", { strength = 1, mastery = 0.8 }, 70)

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

  local imported = addon.XIVWeights.Import.Pawn.Import(adapter, "pawn-ret", "manual:pawn-ret-copy", "Pawn Ret Copy", 70)
  adapterValues.Strength = 1

  local saved = addon.XIVWeights.Config.Repository():Get("manual:pawn-ret-copy")
  A.same(saved, imported)
  A.equal(saved.weights.strength, 1)
  A.equal(saved.weights.haste, 0.5)
  A.equal(saved.source.kind, "manual")
  A.equal(saved.source.importedFrom, "pawn")
end)

test("central XIVWeights mutations invalidate preview state", function()
  local addon = newAddon({})
  local Config = addon.XIVWeights.Config
  local invalidations = 0
  addon.UI = { ClearPreviewCache = function() invalidations = invalidations + 1 end }

  local before = invalidations
  Config.ResetSpecScale(70)
  A.truthy(invalidations > before, "resetting a spec scale should invalidate preview")

  before = invalidations
  Config.SetSpecSelection(70, "manual", "spec:70")
  A.truthy(invalidations > before, "changing the selected scale should invalidate preview")

  local scale = Config.Repository():Get("spec:70")
  scale.weights.haste = 0.8
  before = invalidations
  Config.SaveScale(scale)
  A.truthy(invalidations > before, "saving weights should invalidate preview")

  Config.CreateManualScale("manual:delete-me", "Delete Me", { strength = 1 }, 70)
  before = invalidations
  Config.DeleteScale("manual:delete-me")
  A.truthy(invalidations > before, "deleting a scale should invalidate preview")

  local adapter = {
    ResolveValues = function()
      return { Strength = 10, HasteRating = 5 }, { key = "pawn-preview", name = "Pawn Preview" }
    end,
  }
  before = invalidations
  addon.XIVWeights.Import.Pawn.Import(
    adapter, "pawn-preview", "manual:import-preview", "Import Preview", 70)
  A.truthy(invalidations > before, "importing through SaveScale should invalidate preview")
end)

return tests
