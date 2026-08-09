local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function join(...) return table.concat({ ... }, sep) end

local function loadCommandRouter(addon)
  local chunk = assert(loadfile(join(root, "XIVEquip", "Core", "CommandRouter.lua")))
  chunk("XIVEquip", addon)
end

local function newAddon()
  _G.SlashCmdList = {}
  _G.printed = {}
  _G.XIVEquip_Settings = {}
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    _G.printed[#_G.printed + 1] = table.concat(parts, " ")
  end
  _G.C_AddOns = {
    GetAddOnMetadata = function(_, field)
      if field == "Version" then return "2.0.0-test" end
      return nil
    end,
  }

  local calls = { legacy = 0, native = 0, captures = 0, passStarts = 0, passEnds = 0 }
  local addon = {
    L = { AddonPrefix = "XIVEquip: " },
    Gear_Core = {
      SLOT_LABEL = {
        [16] = "Main Hand",
        [17] = "Off Hand",
      },
    },
    Planning = {
      Coordinator = {
        OPTIMIZED_SLOTS = { 16, 17 },
        Plan = function() end,
      },
    },
    Comparers = {
      StartPass = function()
        calls.passStarts = calls.passStarts + 1
        return { Label = "Item Level" }, {
          configured_key = "default",
          requested_key = "default",
          resolved_key = "ilvl",
          fallback_used = true,
          comparer = { Label = "Item Level", ScoreItem = function() return 1 end },
        }
      end,
      EndPass = function() calls.passEnds = calls.passEnds + 1 end,
    },
    Gear = {},
    Tests = {
      CaptureFixture = function()
        calls.captures = calls.captures + 1
        return { capturedAt = 123, equipped = {}, bags = {}, pawn = { activeScales = {} } }
      end,
    },
  }
  loadCommandRouter(addon)
  return addon, calls
end

local function containsPrinted(text)
  for _, line in ipairs(_G.printed or {}) do
    if tostring(line):find(text, 1, true) then return true end
  end
  return false
end

test("/xive compare saves a fixture-backed log using item-string identity", function()
  local addon, calls = newAddon()
  local currentLink = "|Hitem:200:0:0:0::::::::::::|h[Variant Ring]|h"
  local upgradedLink = "|Hitem:200:1:0:0::::::::::::|h[Variant Ring]|h"

  _G.GetInventoryItemLink = function(_, slot)
    if slot == 16 then return currentLink end
    return nil
  end
  addon.Gear.PlanBest = function(_, _, opts)
    if opts and opts.planner == "native" then
      calls.native = calls.native + 1
      return true, false, {}, {
        finalSlots = { [16] = { itemID = 200, link = upgradedLink, itemLevel = 600 } },
        score = 600,
        diagnostics = { scoreSource = "Item Level" },
      }
    end
    calls.legacy = calls.legacy + 1
    return true, false, { { targetSlot = 16, itemID = 200, link = currentLink, equipLoc = "INVTYPE_WEAPON" } }
  end

  SlashCmdList.XIVE("compare")

  A.equal(calls.native, 1)
  A.equal(calls.legacy, 1)
  A.equal(calls.captures, 1)
  A.equal(calls.passStarts, 1)
  A.equal(calls.passEnds, 1)
  A.contains(_G.printed, "mismatches=1", "same-ID variant should count as a mismatch")

  local log = _G.XIVEquip_Settings.Diagnostics.PlannerCompare
  A.truthy(log, "compare command should save a diagnostic log")
  A.truthy(log.fixture, "compare log should include a fixture capture")
  A.equal(log.addonVersion, "2.0.0-test")
  A.equal(log.native.finalSlots[16].identity, "200:1:0:0::::::::::::")
  A.equal(log.legacy.finalIdentitiesBySlot[16], "200:0:0:0::::::::::::")
  A.equal(log.comparison.mismatchSlots[1], 16)
  A.equal(log.legacy.resolution.comparer, nil, "saved resolution should not retain comparer function tables")
  A.equal(log.savedVariablesPathHint, nil, "compare log should not persist machine-specific filesystem paths")
  A.contains(_G.printed, "Saved comparison log to XIVEquip_Settings.Diagnostics.PlannerCompare.")
  A.contains(_G.printed, "WTF/Account/<ACCOUNT>/SavedVariables/XIVEquip.lua")
end)

test("/xive compare simulates offhand clearing when legacy equips a non-Titan-Grip two-hander", function()
  local addon = newAddon()
  local oneHand = "|Hitem:301::::::::::::|h[One Hand]|h"
  local offhand = "|Hitem:302::::::::::::|h[Offhand]|h"
  local twoHand = "|Hitem:303::::::::::::|h[Two Hand]|h"

  _G.UnitClass = function() return "Shaman", "SHAMAN", 7 end
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 262, "Elemental" end
  _G.GetInventoryItemLink = function(_, slot)
    if slot == 16 then return oneHand end
    if slot == 17 then return offhand end
    return nil
  end

  addon.Gear.PlanBest = function(_, _, opts)
    if opts and opts.planner == "native" then
      return true, false, {}, {
        finalSlots = { [16] = { itemID = 303, link = twoHand, itemLevel = 700 }, [17] = nil },
        score = 1400,
        diagnostics = { scoreSource = "Item Level" },
      }
    end
    return true, false, { { targetSlot = 16, itemID = 303, link = twoHand, equipLoc = "INVTYPE_2HWEAPON" } }
  end

  SlashCmdList.XIVE("compare")

  A.falsy(containsPrinted("Native differs from legacy"), "2H side-effect offhand clear should not be reported as a mismatch")
  A.contains(_G.printed, "mismatches=0")
end)

test("/xive plan2 is no longer registered and does not run planner comparison", function()
  local addon, calls = newAddon()
  addon.Gear.PlanBest = function(_, _, opts)
    if opts and opts.planner == "native" then calls.native = calls.native + 1 else calls.legacy = calls.legacy + 1 end
    return true, false, {}
  end

  SlashCmdList.XIVE("plan2")

  A.contains(_G.printed, "Unknown command")
  A.equal(calls.native, 0)
  A.equal(calls.legacy, 0)
end)

test("/xive plan2 is no longer documented", function()
  local readme = assert(io.open(root .. sep .. "XIVEquip" .. sep .. "README.md", "r"))
  local body = readme:read("*a")
  readme:close()
  A.equal(body:find("/xive plan2", 1, true), nil)
end)

return tests
