local root = ...
local A = dofile(root .. package.config:sub(1, 1) .. "tests" .. package.config:sub(1, 1) .. "assertions.lua")

local sep = package.config:sub(1, 1)
local function join(...)
  return table.concat({ ... }, sep)
end

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

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
      Debugf = function() end,
    },
  }

  _G.XIVEquip_Settings = nil
  _G.SlashCmdList = {}
  _G.printed = {}
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(i, ...))
    end
    _G.printed[#_G.printed + 1] = table.concat(parts, " ")
  end

  loadAddonFile("Global" .. sep .. "Settings.lua", addon)
  loadAddonFile("Core" .. sep .. "ComparerBootstrapper.lua", addon)
  loadAddonFile("Core" .. sep .. "CommandRouter.lua", addon)

  return addon
end

local function registerComparers(addon, pawnUsable)
  addon.Comparers:RegisterComparer("Pawn", {
    Label = "Pawn",
    IsAvailable = function() return pawnUsable == true end,
    PrePass = function() return pawnUsable == true end,
    DebugScore = function() return 42, "PawnScale", { name = "PawnScale" } end,
    GetActiveTooltipHeader = function() return "Comparer: Pawn" end,
  })
  addon.Comparers:RegisterComparer("ilvl", {
    Label = "Item Level",
    IsAvailable = function() return true end,
    DebugScore = function() return 99, "ilvl" end,
    GetActiveTooltipHeader = function() return "Comparer: Item Level" end,
  })
end

test("default resolves to ilvl when Pawn is absent or unusable", function()
  local addon = newAddon()
  registerComparers(addon, false)
  _G.XIVEquip_Settings = { SelectedComparer = "default" }

  local cmp, resolution = addon.Comparers:StartPass()

  A.truthy(cmp, "fallback comparer should be available")
  A.equal(resolution.configured_key, "default")
  A.equal(resolution.resolved_key, "ilvl")
  A.truthy(resolution.fallback_used, "default should report fallback")
end)

test("default resolves to Pawn when Pawn is usable", function()
  local addon = newAddon()
  registerComparers(addon, true)
  _G.XIVEquip_Settings = { SelectedComparer = "default" }

  local cmp, resolution = addon.Comparers:StartPass()

  A.truthy(cmp, "Pawn comparer should be available")
  A.equal(resolution.resolved_key, "pawn")
  A.falsy(resolution.fallback_used, "Pawn default should not be a fallback")
end)

test("explicit Pawn stays strict when unavailable", function()
  local addon = newAddon()
  registerComparers(addon, false)
  _G.XIVEquip_Settings = { SelectedComparer = "pawn" }

  local cmp, resolution = addon.Comparers:StartPass()

  A.falsy(cmp, "explicit unavailable Pawn should not fall back silently")
  A.equal(resolution.configured_key, "pawn")
  A.equal(addon.Settings:GetComparerName(), "pawn")
end)

test("/xive use ilvl stores the canonical key and applies immediately", function()
  local addon = newAddon()
  registerComparers(addon, true)
  _G.XIVEquip_Settings = { SelectedComparer = "default" }

  SlashCmdList.XIVE("use ilvl")

  A.equal(addon.Settings:GetComparerName(), "ilvl")
  A.equal(addon.Comparers:GetResolvedName(), "ilvl")
end)

test("/xive use Item Level accepts label aliases but stores ilvl", function()
  local addon = newAddon()
  registerComparers(addon, true)
  _G.XIVEquip_Settings = { SelectedComparer = "default" }

  SlashCmdList.XIVE("use Item Level")

  A.equal(addon.Settings:GetComparerName(), "ilvl")
  A.equal(addon.Comparers:GetResolvedName(), "ilvl")
end)

test("/xive use Pawn stores the canonical Pawn key", function()
  local addon = newAddon()
  registerComparers(addon, true)
  _G.XIVEquip_Settings = { SelectedComparer = "default" }

  SlashCmdList.XIVE("use Pawn")

  A.equal(addon.Settings:GetComparerName(), "pawn")
  A.equal(addon.Comparers:GetResolvedName(), "pawn")
end)

test("/xive score uses the resolved comparer without an explicit scale", function()
  local addon = newAddon()
  registerComparers(addon, false)
  _G.XIVEquip_Settings = { SelectedComparer = "default" }

  SlashCmdList.XIVE("score |Hitem:1|h[Test]|h")

  A.truthy((_G.printed[#_G.printed] or ""):find("99%.00 %(ilvl%)"), "score output should use ilvl fallback")
end)

return tests
