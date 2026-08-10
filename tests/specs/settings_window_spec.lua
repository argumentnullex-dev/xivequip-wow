local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local ADDON_ICON = "Interface\\AddOns\\XIVEquip\\Assets\\icon_blue_64"

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
    function f:RegisterEvent(event) calls.registeredEvents[#calls.registeredEvents + 1] = event end
    function f:UnregisterAllEvents() calls.unregisteredEvents = calls.unregisteredEvents + 1 end
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
  _G.GameTooltip = {
    SetOwner = function(_, owner, anchor) calls.tooltipOwner = owner; calls.tooltipAnchor = anchor end,
    AddLine = function(_, text) calls.tooltipLine = text end,
    Show = function() calls.tooltipShown = true end,
    Hide = function() calls.tooltipHidden = true end,
  }

  local chunk = assert(loadfile(root .. sep .. "XIVEquip" .. sep .. "UI" .. sep .. "SettingsWindow" .. sep .. "Window.lua"))
  chunk("XIVEquip", addon)
  return addon.UI.SettingsWindow
end

local function harness()
  local calls = {
    buttons = {},
    created = nil,
    edited = nil,
    pickup = nil,
    registeredEvents = {},
    unregisteredEvents = 0,
  }
  local addon = {
    UI = {},
    L = { AddonPrefix = "XIVEquip: " },
    Settings = {
      Get = function()
        return { UI = { SettingsWindow = {} } }
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

test("Create Macro uses the XIVEquip addon icon texture", function()
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

  A.equal(calls.created.icon, ADDON_ICON, "macro should use the addon icon texture path")
  A.equal(calls.created.body, "/xivequip", "macro should run /xivequip")
  A.equal(calls.pickup, 42, "new macro should be picked up by index")
end)

test("Create Macro refreshes an existing macro with the XIVEquip addon icon texture", function()
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
  A.equal(calls.edited.icon, ADDON_ICON, "existing macro should use the addon icon texture path")
  A.equal(calls.pickup, 7, "existing macro should be picked up by index")
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

test("Create Macro shows drop tooltip until an action bar slot changes", function()
  local addon, calls = harness()
  _G.GetMacroIndexByName = function() return 0 end
  _G.CreateMacro = function() return 42 end
  _G.EditMacro = nil
  _G.GetCursorInfo = function() return "macro", 42 end

  local Window = loadWindow(addon, calls)
  Window.Open()
  local owner = calls.buttons["Create Macro"]
  owner.scripts.OnClick(owner)

  A.equal(calls.tooltipOwner, owner, "drop tooltip should anchor to the Create Macro button")
  A.equal(calls.tooltipAnchor, "ANCHOR_CURSOR_RIGHT", "drop tooltip should follow the cursor side")
  A.truthy(calls.tooltipShown, "drop tooltip should show after macro pickup")
  A.equal(calls.registeredEvents[1], "ACTIONBAR_SLOT_CHANGED", "drop watcher should wait for an action bar change")
  A.truthy(Window.MacroDropWatcher, "drop watcher should be retained on the window")

  Window.MacroDropWatcher.scripts.OnEvent(Window.MacroDropWatcher, "ACTIONBAR_SLOT_CHANGED", 1)
  A.truthy(calls.tooltipHidden, "drop tooltip should hide when the macro is dropped")
  A.equal(calls.unregisteredEvents, 1, "drop watcher should unregister after drop")
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
