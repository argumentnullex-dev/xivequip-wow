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
  loadAddonFile("Diagnostics" .. sep .. "Perf.lua", addon)
  loadAddonFile("Profiles" .. sep .. "Config.lua", addon)
  loadAddonFile("Core" .. sep .. "CommandRouter.lua", addon)
  return addon
end

local function commandHarness(settings)
  local addon = newAddon(settings)
  local calls = { plan = {}, equip = {} }

  addon.Gear = {
    PlanBest = function(_, opts)
      calls.plan[#calls.plan + 1] = opts or {}
      local perf = opts and opts.planner and opts.planner.perf
      if perf and perf.Add then perf:Add("optimizer.nodes_visited", 3) end
      return {}, false, {}, { diagnostics = { scoreSource = "Default | Retribution" } }
    end,
    EquipBest = function(_, opts)
      calls.equip[#calls.equip + 1] = opts or {}
      return { completed = true }
    end,
  }

  return addon, calls
end

test("fresh settings produce canonical schema", function()
  local addon = newAddon(nil)
  local st = addon.Settings:Get()

  A.equal(st.SchemaVersion, 4)
  A.equal(st.SettingsModel, "v2")
  A.equal(st.Migration.SourceModel, "fresh")
  A.equal(st.Migration.AutomaticDefaulted, true)
  A.equal(st.Comparer, nil)
  A.equal(st.Automation.SpecEquip, false)
  A.equal(st.Automation.SaveSpecSet, false)
  A.equal(st.Messages.Preview, true)
  A.equal(st.Planner, nil)
  A.equal(type(st.Debug), "table")
  A.equal(type(st.XIVWeights), "table")
  A.equal(type(st.XIVWeights.Scales), "table")
  A.equal(st.UI.Minimap.Hidden, false)
end)

test("pre-profile settings migrate to a v2 model with Automatic as the default", function()
  local addon = newAddon({ SchemaVersion = 3, Planner = { Mode = "legacy" }, Comparer = { Selected = "ilvl" } })
  local st = addon.Settings:Get()

  A.equal(st.SchemaVersion, 4)
  A.equal(st.SettingsModel, "v2")
  A.equal(st.Migration.SourceSchemaVersion, 3)
  A.equal(st.Migration.SourceModel, "pre-profile-v2")

  local profile = addon.Profiles.Config.GetDefault("PALADIN")
  A.truthy(profile)
  A.equal(profile.automatic, true)
  A.equal(profile.manual.mode, "default")
  A.equal(st.Planner, nil)
  A.equal(st.Comparer, nil)
end)

test("older v1/v2 settings are marked as pre-profile rather than fresh", function()
  local addon = newAddon({ SchemaVersion = 2 })
  local st = addon.Settings:Get()

  A.equal(st.Migration.SourceSchemaVersion, 2)
  A.equal(st.Migration.SourceModel, "pre-profile-v2")
  A.equal(st.Migration.AutomaticDefaulted, true)
end)

test("class Default Profile is lazy, class-specific, and assigned per character", function()
  local addon = newAddon({})
  local Profiles = addon.Profiles.Config

  local profile, context = Profiles.EnsureCurrent({
    UnitClass = function() return "Paladin", "PALADIN" end,
    UnitName = function() return "Daedric", "Area 52" end,
  })

  A.equal(profile.id, "paladin:default")
  A.equal(profile.name, "Default - Paladin")
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

test("retired comparer and planner settings are discarded", function()
  local addon = newAddon({
    SelectedComparer = "Item Level",
    Comparer = { Selected = "pawn" },
    PlannerMode = "legacy",
    Planner = { Mode = "legacy" },
  })
  local st = addon.Settings:Get()
  A.equal(st.SelectedComparer, nil)
  A.equal(st.Comparer, nil)
  A.equal(st.PlannerMode, nil)
  A.equal(st.Planner, nil)
end)

test("slash automation commands mutate canonical fields", function()
  local addon = newAddon({})

  SlashCmdList.XIVE("auto spec on")
  SlashCmdList.XIVE("auto sets on")

  local st = addon.Settings:Get()
  A.equal(st.Automation.SpecEquip, true)
  A.equal(st.Automation.SaveSpecSet, true)
end)

test("/xive help prints the command list", function()
  newAddon({})

  SlashCmdList.XIVE("help")

  A.contains(_G.printed, "XIVEquip: Commands:")
  A.contains(_G.printed, "/xive help")
  A.contains(_G.printed, "/xive settings")
  A.contains(_G.printed, "/xive equip")
  A.contains(_G.printed, "/xive status")
end)

test("plan and equip commands use the planner entry points", function()
  local addon, calls = commandHarness({})
  SlashCmdList.XIVE("plan")
  SlashCmdList.XIVE("equip")
  A.equal(#calls.plan, 1)
  A.equal(#calls.equip, 1)
end)

test("/xive perf runs a plan with a performance recorder", function()
  local addon, calls = commandHarness({})
  SlashCmdList.XIVE("perf")

  A.equal(#calls.plan, 1)
  A.truthy(calls.plan[1].planner)
  A.truthy(calls.plan[1].planner.perf)
  A.contains(_G.printed, "Perf: plan produced")
  A.contains(_G.printed, "Score source: Default | Retribution")
  A.contains(_G.printed, "Performance:")
  A.contains(_G.printed, "optimizer.nodes_visited: 3")
end)

test("legacy planner arguments and commands are rejected", function()
  local addon, calls = commandHarness({})
  SlashCmdList.XIVE("plan legacy")
  SlashCmdList.XIVE("equip legacy")
  SlashCmdList.XIVE("planner legacy")
  SlashCmdList.XIVE("compare")
  A.equal(#calls.plan, 0)
  A.equal(#calls.equip, 0)
  A.contains(_G.printed, "Usage: /xive plan")
  A.contains(_G.printed, "Usage: /xive equip")
  A.contains(_G.printed, "Unknown command")
end)

test("/xive equip2 is no longer a registered or documented command", function()
  local _, calls = commandHarness({})
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
