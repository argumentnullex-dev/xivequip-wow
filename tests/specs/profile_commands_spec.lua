-- tests/specs/profile_commands_spec.lua
-- Profiles/Commands.lua's `/xive wish` and `/xive avoid` slash commands had
-- zero offline coverage -- everything about their behavior (item ID
-- parsing from a link/plain number, add/remove/list dispatch, usage and
-- error messages, and the "no active profile" fallback) was only ever
-- exercised live in-game.
local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function loadAddonFile(rel, addon)
  local chunk = assert(loadfile(root .. sep .. "XIVEquip" .. sep .. rel))
  chunk("XIVEquip", addon)
end

local function newAddon()
  local addon = { L = { AddonPrefix = "XIVEquip: " } }

  _G.XIVEquip_Settings = {}
  _G.SlashCmdList = {}
  _G.printed = {}
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    _G.printed[#_G.printed + 1] = table.concat(parts, " ")
  end

  -- Profiles.SetWishlistItem/SetAvoidlistItem validate specID against
  -- XIVWeights.Builtin.Defaults.ClassForSpec (does this spec belong to this
  -- Profile's class?), so the full XIVWeights tree Bootstrap.LoadWeights
  -- loads is a real dependency here, not incidental -- without it every
  -- add/remove silently fails validation regardless of the item ID given.
  Bootstrap.LoadWeights(root, addon)
  loadAddonFile("Core" .. sep .. "CommandRouter.lua", addon)
  loadAddonFile("Profiles" .. sep .. "Commands.lua", addon)
  return addon
end

local function stubRetributionPaladin()
  _G.UnitClass = function() return "Paladin", "PALADIN" end
  _G.UnitName = function() return "Tester" end
  _G.GetRealmName = function() return "Area 52" end
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
end

local function runCommand(addon, cmd)
  addon.__cmd(cmd)
end

local function wireSlash(addon)
  -- CommandRouter.lua registers into _G.SlashCmdList.XIVE at load time;
  -- capture it once so tests can invoke it directly.
  addon.__cmd = _G.SlashCmdList.XIVE
end

test("/xive wish add <item link> adds the item to the active spec's Wishlist", function()
  local addon = newAddon()
  stubRetributionPaladin()
  wireSlash(addon)

  runCommand(addon, "wish add |Hitem:12345::::::::::::|h[Thing]|h")

  local Profiles = addon.Profiles.Config
  local profile = Profiles.GetDefault("PALADIN")
  local preferences = Profiles.GetSpecPreferences(profile, 70)
  A.truthy(preferences.wishlist[12345], "the linked item should be added to the Wishlist")
  A.contains(_G.printed, "XIVEquip: Item 12345 added to wishlist for this specialization.")
end)

test("/xive wish add <plain item ID> works without a link", function()
  local addon = newAddon()
  stubRetributionPaladin()
  wireSlash(addon)

  runCommand(addon, "wish add 999")

  local Profiles = addon.Profiles.Config
  local profile = Profiles.GetDefault("PALADIN")
  A.truthy(Profiles.GetSpecPreferences(profile, 70).wishlist[999])
end)

test("/xive wish remove clears a previously wishlisted item", function()
  local addon = newAddon()
  stubRetributionPaladin()
  wireSlash(addon)

  runCommand(addon, "wish add 555")
  runCommand(addon, "wish remove 555")

  local Profiles = addon.Profiles.Config
  local profile = Profiles.GetDefault("PALADIN")
  A.falsy(Profiles.GetSpecPreferences(profile, 70).wishlist[555])
  A.contains(_G.printed, "XIVEquip: Item 555 removed from wishlist for this specialization.")
end)

test("/xive avoid add mirrors the Wishlist command for the Avoidlist, independently", function()
  local addon = newAddon()
  stubRetributionPaladin()
  wireSlash(addon)

  runCommand(addon, "avoid add 777")

  local Profiles = addon.Profiles.Config
  local profile = Profiles.GetDefault("PALADIN")
  local preferences = Profiles.GetSpecPreferences(profile, 70)
  A.truthy(preferences.avoidlist[777])
  A.falsy(preferences.wishlist[777])
end)

test("/xive wish (no args) and /xive wish list both print the current Wishlist", function()
  local addon = newAddon()
  stubRetributionPaladin()
  wireSlash(addon)

  runCommand(addon, "wish add 1")
  runCommand(addon, "wish add 2")
  _G.printed = {}

  runCommand(addon, "wish")
  runCommand(addon, "wish list")

  A.equal(#_G.printed, 2)
  A.equal(_G.printed[1], "XIVEquip: wishlist for this specialization: 1, 2")
  A.equal(_G.printed[2], _G.printed[1], "bare and explicit 'list' should behave identically")
end)

test("/xive wish list prints an explicit empty message rather than nothing", function()
  local addon = newAddon()
  stubRetributionPaladin()
  wireSlash(addon)

  runCommand(addon, "wish list")

  A.contains(_G.printed, "XIVEquip: wishlist is empty for this specialization.")
end)

test("an unrecognized action prints usage instead of silently failing", function()
  local addon = newAddon()
  stubRetributionPaladin()
  wireSlash(addon)

  runCommand(addon, "wish bogus 12345")

  A.contains(_G.printed, "XIVEquip: Usage: /xive wish <add|remove> <item link|itemID>")
end)

test("add with an unparseable value reports the problem instead of crashing", function()
  local addon = newAddon()
  stubRetributionPaladin()
  wireSlash(addon)

  runCommand(addon, "wish add not-an-item")

  A.contains(_G.printed, "XIVEquip: Provide an item link or item ID.")
  local Profiles = addon.Profiles.Config
  local profile = Profiles.GetDefault("PALADIN")
  A.same(Profiles.GetSpecPreferences(profile, 70).wishlist, {})
end)

test("commands report rather than crash when no character context is available", function()
  local addon = newAddon()
  _G.UnitClass = function() return nil end
  wireSlash(addon)

  runCommand(addon, "wish add 12345")

  A.contains(_G.printed, "XIVEquip: Unable to identify your active profile and specialization.")
end)

return tests
