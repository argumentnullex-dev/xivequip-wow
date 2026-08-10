local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local MACRO_ICON = "Garrison_ArmorUpgrade"

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
      SetText = function(_, text) calls.fontText[#calls.fontText + 1] = tostring(text or "") end,
      SetPoint = function() end,
      SetWidth = function() end,
      SetJustifyH = function() end,
    }
  end

  local function frame(name)
    local f = { name = name, scripts = {}, shown = false }
    function f:SetSize() end
    function f:SetHeight() end
    function f:SetWidth() end
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
    function f:SetScrollChild(child) self.scrollChild = child end
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

  local chunk = assert(loadfile(root .. sep .. "XIVEquip" .. sep .. "UI" .. sep .. "SettingsWindow" .. sep .. "Window.lua"))
  chunk("XIVEquip", addon)
  return addon.UI.SettingsWindow
end

local function harness()
  local settingsTable = { UI = { SettingsWindow = {} } }
  local calls = { buttons = {}, fontText = {}, created = nil, edited = nil, pickup = nil, settings = settingsTable }
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
      GetPlannerMode = function() return settingsTable.PlannerMode or "native" end,
      SetPlannerMode = function(_, mode) settingsTable.PlannerMode = mode end,
    },
  }
  return addon, calls
end

test("Create Macro uses the built-in armor upgrade icon", function()
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

  A.equal(calls.created.icon, MACRO_ICON, "macro should use the chosen built-in armor upgrade icon")
  A.equal(calls.created.body, "/xivequip", "macro should run /xivequip")
  A.falsy(calls.created.perCharacter, "new macro should be created in General Macros")
  A.equal(calls.pickup, 42, "new macro should be picked up by index")
end)

test("Create Macro refreshes an existing macro with the built-in armor upgrade icon", function()
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
  A.equal(calls.edited.icon, MACRO_ICON, "existing macro should use the chosen built-in armor upgrade icon")
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

test("Core tab uses spec names and display labels instead of raw ids", function()
  local addon, calls = harness()
  _G.GetMacroIndexByName = function() return 0 end
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end

  addon.XIVWeights = {
    Config = {
      GetSpecSelection = function() return { provider = "default", scale = nil } end,
      SelectionDisplay = function() return "Built-in default", "Retribution" end,
      ListManualScales = function() return { { id = "spec:70", name = "Retribution", meta = { tiedToSpecID = 70 } } } end,
      SetSpecSelection = function() end,
      EnsureSpecScale = function() end,
      GeneratedScaleID = function() return "spec:70" end,
      SpecName = function() return "Retribution" end,
    },
  }
  addon.Pawn = { GetActiveScales = function() return {} end }

  local Window = loadWindow(addon, calls)
  Window.Open()
  Window.ShowTab(3)

  local text = table.concat(calls.fontText, "\n")
  A.truthy(text:find("Current specialization: Retribution", 1, true), "Core tab should show the spec name")
  A.truthy(text:find("Source: Built-in default", 1, true), "Core tab should show the source label")
  A.truthy(text:find("Scale: Retribution", 1, true), "Core tab should show the scale name")
  A.truthy(calls.buttons["Use Native"], "Core tab should use native without 2.0 wording")
  A.truthy(calls.buttons["Customize Spec Scale"], "Core tab should describe the editable spec-scale action")
  A.falsy(text:find("spec:70", 1, true), "Core tab should not leak generated scale ids")
  A.falsy(text:find("Current specialization: 70", 1, true), "Core tab should not show raw spec ids")
  A.falsy(calls.buttons["Use Native 2.0"], "Core tab should not show native 2.0 wording")
end)

return tests
