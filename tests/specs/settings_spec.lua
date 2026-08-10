local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function loadAddonFile(rel, addon)
  local chunk = assert(loadfile(root .. sep .. "XIVEquip" .. sep .. rel))
  chunk("XIVEquip", addon)
end

local function newAddon(settings)
  local addon = {
    L = { AddonPrefix = "XIVEquip: " },
    Log = {
      Debug = function() end,
      Info = function() end,
      Warn = function() end,
      Error = function() end,
      Debugf = function() end,
    },
  }

  _G.XIVEquip_Settings = settings
  _G.SlashCmdList = {}
  _G.printed = {}
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    _G.printed[#_G.printed + 1] = table.concat(parts, " ")
  end

  loadAddonFile("Global" .. sep .. "Settings.lua", addon)
  loadAddonFile("Profiles" .. sep .. "Config.lua", addon)
  loadAddonFile("Core" .. sep .. "ComparerBootstrapper.lua", addon)
  loadAddonFile("Core" .. sep .. "CommandRouter.lua", addon)

  addon.Comparers:RegisterComparer("ilvl", {
    Label = "Item Level",
    IsAvailable = function() return true end,
  })

  local meta = { passStarts = 0, passEnds = 0 }
  local realStartPass = addon.Comparers.StartPass
  addon.Comparers.StartPass = function(self, ...)
    meta.passStarts = meta.passStarts + 1
    return realStartPass(self, ...)
  end
  local realEndPass = addon.Comparers.EndPass
  addon.Comparers.EndPass = function(self, ...)
    meta.passEnds = meta.passEnds + 1
    if realEndPass then return realEndPass(self, ...) end
  end

  return addon, meta
end

local function commandHarness(settings)
  local addon, meta = newAddon(settings)
  local calls = { plan = {}, equip = {} }

  addon.Gear = {
    PlanBest = function(_, cmp, opts)
      opts = opts or {}
      calls.plan[#calls.plan + 1] = {
        cmp = cmp,
        opts = opts,
        planner = opts.planner or addon.Settings:GetPlannerMode(),
      }
      if opts.planner == "native" then
        return {}, false, {}, { diagnostics = { scoreSource = "Item Level" } }
      end
      return {}, false, {}
    end,
    EquipBest = function(_, opts)
      opts = opts or {}
      calls.equip[#calls.equip + 1] = {
        opts = opts,
        planner = opts.planner or addon.Settings:GetPlannerMode(),
      }
      return { completed = true }
    end,
  }

  return addon, meta, calls
end

test("fresh settings produce canonical schema", function()
  local addon = newAddon(nil)
  local st = addon.Settings:Get()

  A.equal(st.SchemaVersion, 4)
  A.equal(st.SettingsModel, "v2")
  A.equal(st.Migration.SourceModel, "fresh")
  A.equal(st.Migration.AutomaticDefaulted, true)
  A.equal(st.Comparer.Selected, "default")
  A.equal(st.Automation.SpecEquip, false)
  A.equal(st.Automation.SaveSpecSet, false)
  A.equal(st.Messages.Preview, true)
  A.equal(st.Planner.Mode, "legacy")
  A.equal(type(st.Debug), "table")
  A.equal(type(st.XIVWeights), "table")
  A.equal(type(st.XIVWeights.Scales), "table")
  A.equal(st.UI.Minimap.Hidden, false)
end)

test("pre-profile settings migrate to a v2 model with Automatic as the default", function()
  local addon = newAddon({ SchemaVersion = 3, Planner = { Mode = "native" } })
  local st = addon.Settings:Get()

  A.equal(st.SchemaVersion, 4)
  A.equal(st.SettingsModel, "v2")
  A.equal(st.Migration.SourceSchemaVersion, 3)
  A.equal(st.Migration.SourceModel, "pre-profile-v2")

  local profile = addon.Profiles.Config.GetDefault("PALADIN")
  A.truthy(profile)
  A.equal(profile.automatic, true)
  A.equal(profile.manual.mode, "default")
  A.equal(addon.Settings:GetPlannerMode(), "native")
end)

test("class Default Profile is lazy, class-specific, and assigned per character", function()
  local addon = newAddon({})
  local Profiles = addon.Profiles.Config

  local profile, context = Profiles.EnsureCurrent({
    UnitClass = function() return "Paladin", "PALADIN" end,
    UnitName = function() return "Daedric", "Area 52" end,
  })

  A.equal(profile.id, "paladin:default")
  A.equal(profile.classFile, "PALADIN")
  A.equal(profile.automatic, true)
  A.equal(context.characterKey, "Daedric-Area 52")
  A.equal(_G.XIVEquip_Settings.Profiles.CharacterAssignments["Daedric-Area 52"].profileID, profile.id)
  A.falsy(_G.XIVEquip_Settings.Profiles.ByClass.WARRIOR)
end)

test("Profile CRUD preserves stable ids and repairs assignments when deleting", function()
  local addon = newAddon({})
  local Profiles = addon.Profiles.Config
  local default = Profiles.GetDefault("PALADIN")
  local raid = Profiles.Create("PALADIN", "Raid")
  A.truthy(raid)
  A.equal(raid.automatic, true)
  A.equal(Profiles.Rename("PALADIN", raid.id, "Raid Plus").id, raid.id)
  A.equal(Profiles.AssignCharacter("Daedric-Area 52", "PALADIN", raid.id).id, raid.id)
  A.equal(Profiles.Usage("PALADIN", raid.id).count, 1)

  local copy = Profiles.Duplicate("PALADIN", raid.id, "Raid Copy")
  A.truthy(copy)
  A.falsy(copy.id == raid.id)
  A.equal(Profiles.Delete("PALADIN", raid.id), true)
  A.equal(_G.XIVEquip_Settings.Profiles.CharacterAssignments["Daedric-Area 52"].profileID, default.id)
  local deleted, reason = Profiles.Delete("PALADIN", default.id)
  A.equal(deleted, nil)
  A.equal(reason, "default-profile")
end)

test("legacy AutoSpecEquip migrates to SpecEquip", function()
  local addon = newAddon({ AutoSpecEquip = true })
  local st = addon.Settings:Get()

  A.equal(st.Automation.SpecEquip, true)
  A.equal(st.AutoSpecEquip, nil)
end)

test("legacy Automation.AutoSpec migrates when root legacy field is absent", function()
  local addon = newAddon({ Automation = { AutoSpec = true } })
  local st = addon.Settings:Get()

  A.equal(st.Automation.SpecEquip, true)
  A.equal(st.Automation.AutoSpec, nil)
end)

test("legacy Automation.AutoSets takes precedence over seeded AutoSpecSets", function()
  local addon = newAddon({ AutoSpecSets = false, Automation = { AutoSets = true } })
  local st = addon.Settings:Get()

  A.equal(st.Automation.SaveSpecSet, true)
  A.equal(st.Automation.AutoSets, nil)
  A.equal(st.AutoSpecSets, nil)
end)

test("debug boolean migrates to canonical table", function()
  local addon = newAddon({ Debug = true, DebugSlot = 16 })
  local st = addon.Settings:Get()

  A.equal(st.Debug.Enabled, true)
  A.equal(st.Debug.Slot, 16)
  A.equal(_G.XIVEquip_Debug, true)
  A.equal(_G.XIVEquip_DebugSlot, 16)
end)

test("comparer labels migrate to canonical keys", function()
  local addon = newAddon({ SelectedComparer = "Item Level" })
  local st = addon.Settings:Get()

  A.equal(st.Comparer.Selected, "ilvl")
  A.equal(st.SelectedComparer, nil)
end)

test("planner mode normalizes aliases", function()
  local addon = newAddon({})

  addon.Settings:SetPlannerMode("2.0")
  A.equal(addon.Settings:GetPlannerMode(), "native")

  addon.Settings:SetPlannerMode("1.0")
  A.equal(addon.Settings:GetPlannerMode(), "legacy")
end)

test("legacy planner mode field migrates to canonical planner table", function()
  local addon = newAddon({ PlannerMode = "native" })
  local st = addon.Settings:Get()

  A.equal(st.Planner.Mode, "native")
  A.equal(st.PlannerMode, nil)
end)

test("slash automation commands mutate canonical fields", function()
  local addon = newAddon({})

  SlashCmdList.XIVE("auto spec on")
  SlashCmdList.XIVE("auto sets on")

  local st = addon.Settings:Get()
  A.equal(st.Automation.SpecEquip, true)
  A.equal(st.Automation.SaveSpecSet, true)
end)

test("slash planner commands mutate canonical planner mode", function()
  local addon = newAddon({})

  SlashCmdList.XIVE("planner native")
  A.equal(addon.Settings:GetPlannerMode(), "native")

  SlashCmdList.XIVE("planner legacy")
  A.equal(addon.Settings:GetPlannerMode(), "legacy")
end)

test("/xive plan resolves configured and explicit planner modes before opening resources", function()
  local addon, meta, calls = commandHarness({ Planner = { Mode = "legacy" } })
  SlashCmdList.XIVE("plan")
  A.equal(#calls.plan, 1)
  A.equal(calls.plan[1].planner, "legacy")
  A.truthy(calls.plan[1].cmp, "legacy plan should receive a comparer")
  A.equal(meta.passStarts, 1)
  A.equal(meta.passEnds, 1)

  addon, meta, calls = commandHarness({ Planner = { Mode = "native" } })
  SlashCmdList.XIVE("plan")
  A.equal(#calls.plan, 1)
  A.equal(calls.plan[1].planner, "native")
  A.equal(calls.plan[1].cmp, nil)
  A.equal(meta.passStarts, 0)
  A.equal(meta.passEnds, 0)

  addon, meta, calls = commandHarness({ Planner = { Mode = "native" } })
  SlashCmdList.XIVE("plan legacy")
  A.equal(#calls.plan, 1)
  A.equal(calls.plan[1].planner, "legacy")
  A.truthy(calls.plan[1].cmp, "explicit legacy plan should receive a comparer")
  A.equal(meta.passStarts, 1)
  A.equal(meta.passEnds, 1)
  A.equal(addon.Settings:GetPlannerMode(), "native")

  addon, meta, calls = commandHarness({ Planner = { Mode = "legacy" } })
  SlashCmdList.XIVE("plan native")
  A.equal(#calls.plan, 1)
  A.equal(calls.plan[1].planner, "native")
  A.equal(calls.plan[1].cmp, nil)
  A.equal(meta.passStarts, 0)
  A.equal(meta.passEnds, 0)
  A.equal(addon.Settings:GetPlannerMode(), "legacy")
end)

test("/xive equip uses configured planner mode and honors explicit overrides", function()
  local addon, _, calls = commandHarness({ Planner = { Mode = "legacy" } })
  SlashCmdList.XIVE("equip")
  A.equal(#calls.equip, 1)
  A.equal(calls.equip[1].planner, "legacy")

  addon, _, calls = commandHarness({ Planner = { Mode = "native" } })
  SlashCmdList.XIVE("equip")
  A.equal(#calls.equip, 1)
  A.equal(calls.equip[1].planner, "native")

  addon, _, calls = commandHarness({ Planner = { Mode = "native" } })
  SlashCmdList.XIVE("equip legacy")
  A.equal(#calls.equip, 1)
  A.equal(calls.equip[1].planner, "legacy")
  A.equal(addon.Settings:GetPlannerMode(), "native")

  addon, _, calls = commandHarness({ Planner = { Mode = "legacy" } })
  SlashCmdList.XIVE("equip native")
  A.equal(#calls.equip, 1)
  A.equal(calls.equip[1].planner, "native")
  A.equal(addon.Settings:GetPlannerMode(), "legacy")
end)

test("invalid explicit planner arguments do not plan or equip", function()
  local _, meta, calls = commandHarness({ Planner = { Mode = "native" } })

  SlashCmdList.XIVE("plan invalid")
  A.equal(#calls.plan, 0)
  A.equal(meta.passStarts, 0)
  A.equal(meta.passEnds, 0)
  A.contains(_G.printed, "Usage: /xive plan [legacy|native]")

  _G.printed = {}
  SlashCmdList.XIVE("equip invalid")
  A.equal(#calls.equip, 0)
  A.contains(_G.printed, "Usage: /xive equip [legacy|native]")
end)

test("/xive equip2 is no longer a registered or documented command", function()
  local _, _, calls = commandHarness({})
  SlashCmdList.XIVE("equip2")

  A.equal(#calls.equip, 0)
  A.contains(_G.printed, "Unknown command")

  local readme = assert(io.open(root .. sep .. "XIVEquip" .. sep .. "README.md", "r"))
  local body = readme:read("*a")
  readme:close()
  A.equal(body:find("/xive equip2", 1, true), nil)
end)

test("/xive with no arguments and /xive settings open the custom settings window", function()
  local addon = newAddon({})
  local opens = 0
  addon.UI = { SettingsWindow = { Open = function() opens = opens + 1 end } }

  SlashCmdList.XIVE("")
  SlashCmdList.XIVE("settings")

  A.equal(opens, 2)
end)

test("initialization is idempotent", function()
  local addon = newAddon({ AutoSpecEquip = true, Debug = true })
  local st1 = addon.Settings:Get()
  local st2 = addon.Settings:Get()

  A.equal(st1, st2)
  A.equal(st2.Automation.SpecEquip, true)
  A.equal(st2.Debug.Enabled, true)
end)

return tests
