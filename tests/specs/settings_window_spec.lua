local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local ADDON_ICON_PATH = "Interface/AddOns/XIVEquip/Assets/icon_blue_128.tga"
local ADDON_ICON_FILE_ID = -12345
local FALLBACK_MACRO_ICON = "INV_Misc_Gear_01"
local ICON_TEST_VARIANTS = {
  ["XIVE Upgrade"] = "UI_ItemUpgrade",
  ["XIVE Equipped"] = "UI_Transmog_ShowEquippedGear",
  ["XIVE Gear"] = "INV_Misc_Gear_01",
  ["XIVE Armor"] = "Garrison_ArmorUpgrade",
  ["XIVE Repair"] = "Ability_Repair",
}

local function loadWindow(addon, calls)
  local function texture()
    return {
      SetAllPoints = function() end,
      SetPoint = function() end,
      SetSize = function() end,
      SetTexture = function() end,
      SetTexCoord = function() end,
      SetBlendMode = function() end,
    }
  end

  local function fontString()
    return {
      SetText = function() end,
      SetPoint = function() end,
      SetWidth = function() end,
      SetJustifyH = function() end,
    }
  end

  local function frame(name)
    local f = { name = name, scripts = {}, shown = false }
    function f:SetSize() end
    function f:SetFrameStrata() end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:Hide() self.shown = false end
    function f:Show() self.shown = true end
    function f:IsShown() return self.shown end
    function f:CreateFontString() return fontString() end
    function f:CreateTexture() return texture() end
    function f:ClearAllPoints() end
    function f:SetPoint() end
    function f:SetAllPoints() end
    function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:RegisterForClicks() end
    function f:SetText(text) self.text = text; calls.buttons[text] = self end
    function f:SetID(id) self.id = id end
    function f:GetID() return self.id end
    function f:SetChecked(value) self.checked = value end
    function f:GetChecked() return self.checked end
    f.TitleBg = frame
    f.Text = { SetText = function() end }
    return f
  end

  _G.UIParent = frame("UIParent")
  _G.UISpecialFrames = {}
  _G.PanelTemplates_SetNumTabs = function() end
  _G.PanelTemplates_SetTab = function() end
  _G.PanelTemplates_SelectTab = function() end
  _G.PanelTemplates_DeselectTab = function() end
  _G.CreateFrame = function(_, name)
    return frame(name)
  end
  _G.GetCursorPosition = function() return 100, 200 end
  _G.print = function() end
  _G.PickupMacro = calls.pickupFn or function(index) calls.pickup = index end
  _G.C_Macro = {
    GetMacroName = function(index)
      return calls.macroNames and calls.macroNames[index] or nil
    end,
  }
  _G.GetActionInfo = calls.getActionInfo or function() return nil end
  _G.GetFileIDFromPath = calls.getFileIDFromPath or function(path)
    calls.fileIDPaths[#calls.fileIDPaths + 1] = path
    return ADDON_ICON_FILE_ID
  end

  local chunk = assert(loadfile(root .. sep .. "XIVEquip" .. sep .. "UI" .. sep .. "SettingsWindow" .. sep .. "Window.lua"))
  chunk("XIVEquip", addon)
  return addon.UI.SettingsWindow
end

local function harness()
  local settingsTable = { UI = { SettingsWindow = {} } }
  local calls = { buttons = {}, created = nil, createdList = {}, edited = nil, pickup = nil, fileIDPaths = {}, settings = settingsTable }
  local addon = {
    UI = {},
    L = { AddonPrefix = "XIVEquip: " },
    Settings = {
      Get = function()
        return settingsTable
      end,
      GetMessage = function() return true end,
      SetMessage = function() end,
      GetDebugEnabled = function() return false end,
      SetDebugEnabled = function() end,
      GetAutomation = function() return false end,
      SetAutomation = function() end,
      GetMinimapHidden = function() return false end,
      SetMinimapHidden = function() end,
    },
  }
  return addon, calls
end

test("Create Macro uses the XIVEquip addon icon FileID", function()
  local addon, calls = harness()
  _G.GetMacroIndexByName = function() return 0 end
  _G.CreateMacro = function(name, icon, body, perCharacter)
    calls.created = { name = name, icon = icon, body = body, perCharacter = perCharacter }
    return 42
  end
  _G.EditMacro = nil
  _G.GetCursorInfo = function() return "macro", 42 end

  local Window = loadWindow(addon, calls)
  Window.Open()
  calls.buttons["Create Macro"].scripts.OnClick(calls.buttons["Create Macro"])

  A.equal(calls.fileIDPaths[1], ADDON_ICON_PATH, "macro should resolve addon icon path")
  A.equal(calls.created.icon, ADDON_ICON_FILE_ID, "macro should use resolved addon icon FileID")
  A.equal(calls.created.body, "/xivequip", "macro should run /xivequip")
  A.falsy(calls.created.perCharacter, "new macro should be created in General Macros")
  A.equal(calls.pickup, 42, "new macro should be picked up by index")
end)

test("Create Macro refreshes an existing macro with the XIVEquip addon icon FileID", function()
  local addon, calls = harness()
  _G.GetMacroIndexByName = function() return 7 end
  _G.EditMacro = function(index, name, icon, body)
    calls.edited = { index = index, name = name, icon = icon, body = body }
  end
  _G.CreateMacro = nil
  _G.GetCursorInfo = function() return "macro", 7 end

  local Window = loadWindow(addon, calls)
  Window.Open()
  calls.buttons["Create Macro"].scripts.OnClick(calls.buttons["Create Macro"])

  A.equal(calls.edited.index, 7, "existing macro should be edited")
  A.equal(calls.edited.icon, ADDON_ICON_FILE_ID, "existing macro should use resolved addon icon FileID")
  A.equal(calls.pickup, 7, "existing macro should be picked up by index")
end)

test("Create Macro refreshes the XIVEquip macro already placed on an action bar", function()
  local addon, calls = harness()
  calls.macroNames = { [7] = "XIVEquip", [42] = "XIVEquip" }
  calls.getActionInfo = function(slot)
    if slot == 3 then return "macro", 42 end
    return nil
  end
  _G.GetMacroIndexByName = function() return 7 end
  _G.EditMacro = function(index, name, icon, body)
    calls.edited = { index = index, name = name, icon = icon, body = body }
  end
  _G.CreateMacro = nil
  _G.GetCursorInfo = function() return "macro", 42 end

  local Window = loadWindow(addon, calls)
  Window.Open()
  calls.buttons["Create Macro"].scripts.OnClick(calls.buttons["Create Macro"])

  A.equal(calls.edited.index, 42, "placed action-bar macro should be edited before same-name fallback")
  A.equal(calls.pickup, 42, "placed action-bar macro should be picked up")
  A.equal(calls.settings.MacroID, 42, "saved macro id should follow the refreshed placed macro")
end)

test("Create Macro ignores character-specific XIVEquip macros and creates a General Macro", function()
  local addon, calls = harness()
  calls.settings.MacroID = 121
  calls.macroNames = { [121] = "XIVEquip" }
  calls.getActionInfo = function(slot)
    if slot == 3 then return "macro", 121 end
    return nil
  end
  _G.GetMacroIndexByName = function() return 121 end
  _G.CreateMacro = function(name, icon, body, perCharacter)
    calls.created = { name = name, icon = icon, body = body, perCharacter = perCharacter }
    return 42
  end
  _G.EditMacro = function(index) calls.edited = { index = index } end
  _G.GetCursorInfo = function() return "macro", 42 end

  local Window = loadWindow(addon, calls)
  Window.Open()
  calls.buttons["Create Macro"].scripts.OnClick(calls.buttons["Create Macro"])

  A.falsy(calls.edited, "character-specific same-name macro should not be edited")
  A.equal(calls.created.name, "XIVEquip", "missing General Macro should be created")
  A.falsy(calls.created.perCharacter, "created macro should land in General Macros")
  A.equal(calls.pickup, 42, "new General Macro should be picked up")
  A.equal(calls.settings.MacroID, 42, "saved macro id should point at the General Macro")
end)

test("Create Macro falls back to a built-in icon when addon icon FileID is unavailable", function()
  local addon, calls = harness()
  calls.getFileIDFromPath = function(path)
    calls.fileIDPaths[#calls.fileIDPaths + 1] = path
    return nil
  end
  _G.GetMacroIndexByName = function() return 0 end
  _G.CreateMacro = function(name, icon, body, perCharacter)
    calls.created = { name = name, icon = icon, body = body, perCharacter = perCharacter }
    return 42
  end
  _G.EditMacro = nil
  _G.GetCursorInfo = function() return "macro", "XIVEquip" end

  local Window = loadWindow(addon, calls)
  Window.Open()
  calls.buttons["Create Macro"].scripts.OnClick(calls.buttons["Create Macro"])

  A.equal(calls.fileIDPaths[1], ADDON_ICON_PATH, "fallback should still try the addon icon path first")
  A.equal(calls.created.icon, FALLBACK_MACRO_ICON, "macro should use built-in fallback icon")
end)

test("Create Icon Test Macros creates built-in icon variants in General Macros", function()
  local addon, calls = harness()
  local nextIndex = 20
  _G.GetMacroIndexByName = function() return 0 end
  _G.CreateMacro = function(name, icon, body, perCharacter)
    calls.createdList[#calls.createdList + 1] = { name = name, icon = icon, body = body, perCharacter = perCharacter }
    nextIndex = nextIndex + 1
    return nextIndex
  end
  _G.EditMacro = nil
  _G.GetCursorInfo = function() return nil end

  local Window = loadWindow(addon, calls)
  Window.Open()
  calls.buttons["Create Icon Test Macros"].scripts.OnClick(calls.buttons["Create Icon Test Macros"])

  A.equal(#calls.createdList, 5, "tester should create every built-in icon variant")
  for _, created in ipairs(calls.createdList) do
    A.equal(created.body, "/xivequip", "test macro should run /xivequip")
    A.falsy(created.perCharacter, "test macro should be created in General Macros")
    A.equal(created.icon, ICON_TEST_VARIANTS[created.name], "test macro should use the configured built-in icon")
  end
  A.falsy(calls.pickup, "icon test macros should not place any macro on the cursor")
end)

test("Create Macro falls back from macro index pickup to name pickup", function()
  local addon, calls = harness()
  local pickupAttempts = {}
  _G.GetMacroIndexByName = function() return 7 end
  _G.EditMacro = function() end
  _G.CreateMacro = nil
  calls.pickupFn = function(id)
    pickupAttempts[#pickupAttempts + 1] = id
    calls.pickup = id
  end
  _G.GetCursorInfo = function()
    if pickupAttempts[#pickupAttempts] == "XIVEquip" then return "macro", "XIVEquip" end
    return nil
  end

  local Window = loadWindow(addon, calls)
  Window.Open()
  calls.buttons["Create Macro"].scripts.OnClick(calls.buttons["Create Macro"])

  A.equal(pickupAttempts[1], 7, "macro pickup should try by index first")
  A.equal(pickupAttempts[2], "XIVEquip", "macro pickup should fall back to name")
  A.equal(calls.pickup, "XIVEquip", "fallback macro name should be the final pickup")
end)

test("Create Macro shows and hides a XIVEquip cursor ghost for custom icon pickup", function()
  local addon, calls = harness()
  local cursorKind, cursorID = "macro", 42
  _G.GetMacroIndexByName = function() return 0 end
  _G.CreateMacro = function() return 42 end
  _G.EditMacro = nil
  _G.GetCursorInfo = function() return cursorKind, cursorID end

  local Window = loadWindow(addon, calls)
  Window.Open()
  calls.buttons["Create Macro"].scripts.OnClick(calls.buttons["Create Macro"])

  A.truthy(Window.CursorGhost, "custom-icon pickup should create a cursor ghost")
  A.truthy(Window.CursorGhost.scripts.OnUpdate, "cursor ghost should follow while macro is on cursor")
  Window.CursorGhost.scripts.OnUpdate(Window.CursorGhost)
  A.truthy(Window.CursorGhost:IsShown(), "cursor ghost should be visible while matching macro is on cursor")

  cursorKind, cursorID = nil, nil
  Window.CursorGhost.scripts.OnUpdate(Window.CursorGhost)
  A.falsy(Window.CursorGhost:IsShown(), "cursor ghost should hide after cursor no longer has the macro")
  A.falsy(Window.CursorGhost.scripts.OnUpdate, "cursor ghost should stop updating after cursor clears")
end)

test("settings window registers once for Escape close", function()
  local addon, calls = harness()
  _G.GetMacroIndexByName = function() return 0 end

  local Window = loadWindow(addon, calls)
  Window.Create()
  Window.Create()

  local count = 0
  for _, name in ipairs(_G.UISpecialFrames) do
    if name == "XIVEquipSettingsWindow" then count = count + 1 end
  end
  A.equal(count, 1, "settings window should be registered once as an Escape-close frame")
end)

return tests
