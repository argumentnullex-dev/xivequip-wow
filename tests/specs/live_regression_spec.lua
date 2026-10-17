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

test("the in-game regression suite passes against the current settings schema", function()
  local originalSettings = _G.XIVEquip_Settings
  local originalSlashCmdList = _G.SlashCmdList
  local originalPrint = _G.print
  local printed = {}

  local ok, err = xpcall(function()
    local addon = {
      L = { AddonPrefix = "XIVEquip: " },
      Commands = {
        RegisterRoot = function() end,
        Help = function() end,
      },
      Gear = {
        PlanBest = function() return {}, false end,
      },
    }

    _G.XIVEquip_Settings = {}
    _G.print = function(message) printed[#printed + 1] = tostring(message) end

    loadAddonFile("Global" .. sep .. "Settings.lua", addon)
    _G.SlashCmdList = {
      XIVE = function(command)
        if command == "status" then return end
        if command == "auto spec on" then
          addon.Settings:SetAutomation("SpecEquip", true)
          return
        end
        if command == "auto sets on" then
          addon.Settings:SetAutomation("SaveSpecSet", true)
          return
        end
        error("unexpected regression command: " .. tostring(command))
      end,
    }
    loadAddonFile("Tests" .. sep .. "Regression.lua", addon)

    local passed, passCount, failCount = addon.Tests:Run()
    A.truthy(passed)
    A.truthy(passCount > 0, "the live regression suite should execute at least one case")
    A.equal(failCount, 0)
    A.contains(printed, "legacy settings migrate to the current canonical schema")
  end, debug.traceback)

  _G.XIVEquip_Settings = originalSettings
  _G.SlashCmdList = originalSlashCmdList
  _G.print = originalPrint

  if not ok then error(err, 0) end
end)

for _, mode in ipairs({ "namespaced-only", "deprecated-globals-error" }) do
  test("fixture capture preserves item metadata and stats with current APIs: " .. mode, function()
    local FakeWorld = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "fake_world.lua")
    local originals = {}
    for _, name in ipairs({ "C_Item", "GetItemInfo", "GetItemInfoInstant", "GetItemStats", "GetDetailedItemLevelInfo" }) do
      originals[#originals + 1] = { name, _G[name] }
    end
    local ok, err = xpcall(function()
      FakeWorld.Install({
        itemAPIMode = mode,
        items = {
          helm = { itemID = 99201, equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4,
            itemLevel = 110, stats = { ITEM_MOD_STRENGTH_SHORT = 80 } },
        },
        equipped = { [1] = "helm" },
      })
      local addon = {}
      loadAddonFile("Tests" .. sep .. "Regression.lua", addon)
      local fixture = addon.Tests:CaptureFixture()
      A.equal(fixture.equipped[1].itemID, 99201)
      A.equal(fixture.equipped[1].itemLevel, 110)
      A.equal(fixture.equipped[1].stats.ITEM_MOD_STRENGTH_SHORT, 80)
    end, debug.traceback)
    for _, entry in ipairs(originals) do _G[entry[1]] = entry[2] end
    if not ok then error(err, 0) end
  end)
end

return tests
