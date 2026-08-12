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
      SetText = function(self, text)
        self.text = tostring(text or "")
        calls.fontText[#calls.fontText + 1] = self.text
      end,
      SetTextColor = function(self, ...)
        self.textColor = { ... }
      end,
      SetFontObject = function(self, fontObject)
        self.fontObject = fontObject
        calls.fontObjects[#calls.fontObjects + 1] = fontObject
      end,
      SetPoint = function(self, ...)
        self.points = self.points or {}
        self.points[#self.points + 1] = { ... }
      end,
      ClearAllPoints = function(self) self.points = {} end,
      SetWidth = function() end,
      SetJustifyH = function() end,
    }
  end

  local function frame(name)
    local f = { name = name, scripts = {}, shown = false }
    function f:SetSize(width, height) self.width, self.height = width, height end
    function f:SetHeight() end
    function f:SetWidth() end
    function f:SetMinMaxValues() end
    function f:SetValueStep() end
    function f:SetObeyStepOnDrag() end
    function f:SetValue(value) self.value = value end
    function f:SetFrameStrata(value) self.frameStrata = value end
    function f:SetToplevel(value) self.toplevel = value end
    function f:Raise() self.raised = true end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:Hide() self.shown = false end
    function f:Show() self.shown = true end
    function f:IsShown() return self.shown end
    function f:CreateFontString() return fontString() end
    function f:CreateTexture() return texture() end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(...)
      self.points = self.points or {}
      self.points[#self.points + 1] = { ... }
    end
    function f:SetAllPoints() end
    function f:SetScrollChild(child) self.scrollChild = child end
    function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:RegisterForClicks() end
    function f:Enable() self.enabled = true end
    function f:Disable() self.enabled = false end
    function f:SetAutoFocus() end
    function f:ClearFocus() end
    function f:GetText() return self.text end
    function f:SetTextInsets() end
    function f:SetMultiLine() end
    function f:SetFontObject() end
    function f:HighlightText() self.highlighted = true end
    function f:SetText(text) self.text = text; calls.buttons[text] = self end
    function f:SetID(id) self.id = id end
    function f:GetID() return self.id end
    function f:LockHighlight() self.locked = true end
    function f:UnlockHighlight() self.locked = false end
    function f:SetChecked(value) self.checked = value end
    function f:GetChecked() return self.checked end
    f.TitleBg = frame
    f.Text = { SetText = function(_, text) f.checkboxText = text end }
    return f
  end

  _G.UIParent = frame("UIParent")
  _G.UISpecialFrames = {}
  _G.PanelTemplates_SetNumTabs = function() end
  _G.PanelTemplates_SetTab = function() end
  _G.PanelTemplates_SelectTab = function() end
  _G.PanelTemplates_DeselectTab = function() end
  _G.UIDropDownMenu_Initialize = function(menu, initializer)
    menu.dropdownInitializer = initializer
  end
  _G.UIDropDownMenu_SetWidth = function(menu, width)
    if type(menu) ~= "table" or type(width) ~= "number" then
      error("UIDropDownMenu_SetWidth expects (frame, width)")
    end
    menu.dropdownWidth = width
  end
  _G.UIDropDownMenu_SetSelectedValue = function() end
  _G.UIDropDownMenu_CreateInfo = function() return {} end
  _G.UIDropDownMenu_AddButton = function(info)
    calls.dropdownButtons = calls.dropdownButtons or {}
    calls.dropdownButtons[#calls.dropdownButtons + 1] = info
  end
  _G.UIDropDownMenu_SetText = function(menu, text)
    if type(menu) ~= "table" or type(text) ~= "string" then
      error("UIDropDownMenu_SetText expects (frame, text)")
    end
    menu.dropdownText = text
  end
  _G.GameFontNormal = { name = "GameFontNormal" }
  _G.GameFontNormalLarge = { name = "GameFontNormalLarge" }
  _G.GameFontNormalSmall = { name = "GameFontNormalSmall" }
  _G.GameFontHighlight = { name = "GameFontHighlight" }
  _G.GameFontHighlightSmall = { name = "GameFontHighlightSmall" }
  _G.GameFontDisableSmall = { name = "GameFontDisableSmall" }
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
  local calls = { buttons = {}, fontText = {}, fontObjects = {}, created = nil, edited = nil, pickup = nil, settings = settingsTable }
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

test("Settings uses a vertical navigation rail", function()
  local addon, calls = harness()
  local Window = loadWindow(addon, calls)
  local frame = Window.Create()

  A.truthy(frame.sidebar, "settings should create a persistent navigation rail")
  A.equal(frame.tabs[1].points[1][1], "TOP", "first navigation item should anchor in the rail")
  A.equal(frame.tabs[1].points[1][2], frame.sidebar, "first navigation item should use the rail")
  A.equal(frame.tabs[2].points[1][1], "TOP", "second navigation item should stack vertically")
  A.equal(frame.tabs[2].points[1][2], frame.tabs[1], "second navigation item should follow the first")
  A.equal(frame.tabs[2].points[1][3], "BOTTOM", "navigation should be vertical rather than horizontal")
  A.equal(frame.content.points[1][4], 146, "page content should begin to the right of the rail")
end)

test("Settings reads and displays the full add-on version", function()
  local addon, calls = harness()
  _G.GetAddOnMetadata = nil
  _G.C_AddOns = {
    GetAddOnMetadata = function(name, field)
      A.equal(name, "XIVEquip", "version lookup should use the add-on name")
      A.equal(field, "Version", "version lookup should request TOC metadata")
      return "2.0.0-dev.78"
    end,
  }

  local Window = loadWindow(addon, calls)
  Window.Create()
  _G.C_AddOns = nil

  A.truthy(table.concat(calls.fontText, "\n"):find("v2.0.0-dev.78", 1, true), "sidebar should display the complete TOC version")
end)

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

test("Config page uses spec names and display labels instead of raw ids", function()
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
  Window.ShowTab(1)

  local text = table.concat(calls.fontText, "\n")
  A.truthy(text:find("Retribution", 1, true), "Config should show the spec name")
  A.truthy(text:find("Built%-in default", 1, true) or text:find("Built-in default", 1, true), "Config should show the source label")
  local profilePanel = Window.Frame.content.page._xivEquipPool.items.panel[1]
  A.truthy(profilePanel._xivEquipFrames["new-profile-name"], "Config should expose inline Profile creation")
  A.equal(profilePanel._xivEquipPool.items.button[1].text, "Create")
  A.equal(profilePanel._xivEquipPool.items.button[2].text, "Delete")
  A.falsy(calls.buttons["Manage"], "Config should not expose the obsolete Profile management dialog")
  A.truthy(calls.buttons["Create Macro"], "Config should preserve macro creation")
  A.falsy(text:find("spec:70", 1, true), "Config should not leak generated scale ids")
  A.falsy(text:find("| 70", 1, true), "Config should not show raw spec ids")
end)

test("Config page explains Integration fallback and reason", function()
  local addon, calls = harness()
  _G.GetMacroIndexByName = function() return 0 end
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end

  addon.XIVWeights = {
    Config = {
      ResolveResultForSpec = function()
        return {
          scale = { resolution = { sourceLabel = "Default", scaleLabel = "Retribution" } },
          fallback = true,
          fallbackReason = "integration-scale-missing",
          selection = { provider = "pawn" },
        }
      end,
      ListIntegrations = function() return { { id = "pawn", label = "Pawn" } } end,
      SpecName = function() return "Retribution" end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  local text = table.concat(calls.fontText, "\n")
  A.truthy(text:find("Default | Retribution %(Fallback%)"), "fallback should be visible in the source line")
  A.truthy(text:find("Fallback: Pawn", 1, true), "fallback warning should identify the provider")
  A.truthy(text:find("integration%-scale%-missing"), "fallback warning should include the resolver reason")
end)

test("repeated Config renders reuse the page frame", function()
  local addon, calls = harness()
  _G.GetMacroIndexByName = function() return 0 end
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  addon.XIVWeights = {
    Config = {
      ResolveResultForSpec = function()
        return { scale = { resolution = { sourceLabel = "Default", scaleLabel = "Retribution" } } }
      end,
      ListIntegrations = function() return {} end,
      SpecName = function() return "Retribution" end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  local page = Window.Frame.content.page
  Window.ShowTab(1)
  A.equal(Window.Frame.content.page, page, "same-state Config refresh should reuse the page frame")
end)

test("pooled settings fonts bind actual Font objects rather than template-name strings", function()
  local addon, calls = harness()
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  addon.XIVWeights = {
    Config = {
      ResolveResultForSpec = function()
        return { scale = { resolution = { sourceLabel = "Default", scaleLabel = "Retribution" } } }
      end,
      ListIntegrations = function() return {} end,
      SpecName = function() return "Retribution" end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  local sawNormal = false
  for _, fontObject in ipairs(calls.fontObjects) do
    A.falsy(type(fontObject) == "string", "font helper must not pass a template-name string to SetFontObject")
    if fontObject == _G.GameFontNormal then sawNormal = true end
  end
  A.truthy(sawNormal, "font helper should pass the actual WoW Font object")
end)

test("state changes and tab switches reset nested Config pools before rebinding", function()
  local addon, calls = harness()
  local profile = {
    id = "paladin-default",
    automatic = false,
    manual = { mode = "custom", customOverrides = {}, integration = { overrides = {} } },
  }
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  _G.UnitClass = function() return "Paladin", "PALADIN" end
  addon.XIVWeights = {
    Builtin = {
      Defaults = {
        SpecsForClass = function() return { { id = 70, name = "Retribution" } } end,
      },
    },
    Config = {
      ResolveResultForSpec = function()
        return { scale = { resolution = { sourceLabel = "Default", scaleLabel = "Retribution" } } }
      end,
      ListIntegrations = function() return {} end,
      ListManualScales = function() return {} end,
      GetScaleSpecID = function() return nil end,
      Repository = function() return { Get = function() return nil end } end,
      SpecName = function() return "Retribution" end,
    },
  }
  addon.Profiles = {
    Config = {
      CurrentContext = function() return { classFile = "PALADIN", characterKey = "Test-Realm" } end,
      GetForCharacter = function() return profile end,
      List = function() return { profile } end,
      Usage = function() return { count = 1 } end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  local page = Window.Frame.content.page
  local profilePanel = page._xivEquipPool.items.panel[1]
  local modePanel = page._xivEquipPool.items.panel[2]
  local profileFontCount = #profilePanel._xivEquipPool.items.font
  local profileButtonCount = #profilePanel._xivEquipPool.items.button
  local modeButtonCount = #modePanel._xivEquipPool.items.button
  local automaticBox = modePanel._xivEquipPool.items.checkbox[1]
  local setPreferenceBox = modePanel._xivEquipPool.items.checkbox[2]
  A.equal(automaticBox.points[1][2], 14, "Automatic should use the left settings column")
  A.equal(setPreferenceBox.points[1][2], 14, "set preference should align beneath Automatic")
  A.truthy(setPreferenceBox.points[1][3] < automaticBox.points[1][3], "set preference should render below Automatic")
  A.equal(setPreferenceBox.checkboxText, "Prefer set bonuses", "set preference should retain its clear label")
  local modeText = {}
  for _, item in ipairs(modePanel._xivEquipPool.items.font) do modeText[#modeText + 1] = item.text end
  A.truthy(table.concat(modeText, "\n"):find("Favor loadouts that complete 2-piece and 4-piece set bonuses.", 1, true),
    "set preference should explain its optimization effect")
  local customMapPanel = page._xivEquipPool.items.panel[3]
  local customMenu = customMapPanel._xivEquipPool.items.dropdown[1]
  local customEdit = customMapPanel._xivEquipPool.items.button[1]
  A.truthy(customEdit.points[1][2] >= customMenu.points[1][2] + customMenu.dropdownWidth + 36,
    "custom scale action buttons should clear the dropdown template's visible right edge")
  local generalPanel = page._xivEquipPool.items.panel[4]
  local debugBox = generalPanel._xivEquipPool.items.checkbox[3]
  local minimapBox = generalPanel._xivEquipPool.items.checkbox[6]
  local macroButton = generalPanel._xivEquipPool.items.button[1]
  A.equal(generalPanel._xivEquipPool.items.checkbox[5].checkboxText, "Save Equipment set after auto-equip",
    "automation setting should use the established label")
  A.equal(generalPanel.height, 216, "Addon Settings should contain its lower row with generous bottom padding")
  A.truthy(minimapBox.points[1][3] <= debugBox.points[1][3] - 62,
    "Minimap Button should have breathing room below the message checkboxes")
  A.equal(macroButton.points[1][3], minimapBox.points[1][3], "Minimap and Macro controls should share a baseline")

  profile.automatic = true
  Window.ShowTab(1)
  A.equal(#profilePanel._xivEquipPool.items.font, profileFontCount, "profile controls should be reused after a state change")
  A.equal(#profilePanel._xivEquipPool.items.button, profileButtonCount, "profile buttons should not accumulate after a state change")
  A.equal(#modePanel._xivEquipPool.items.button, modeButtonCount, "mode buttons should not accumulate after a state change")
  A.falsy(modePanel._xivEquipPool.items.button[1].enabled, "automatic mode should disable manual mode controls")
  A.equal(modePanel._xivEquipPool.items.button[2].text, "Custom", "Automatic should retain the selected manual mode as disabled context")
  local mapPanel = page._xivEquipPool.items.panel[3]
  A.truthy(mapPanel:IsShown(), "Automatic should keep the remembered Custom mappings visible")
  A.falsy(mapPanel._xivEquipPool.items.dropdown[1].enabled,
    "remembered Custom mappings should be disabled while Automatic is enabled")

  profile.automatic = false
  Window.ShowTab(2)
  Window.ShowTab(1)
  A.equal(Window.Frame.content.page, page, "Config to Scales to Config should reuse the same page frame")
  A.equal(#profilePanel._xivEquipPool.items.font, profileFontCount, "profile controls should remain pooled after tab switches")
  A.equal(#modePanel._xivEquipPool.items.button, modeButtonCount, "mode controls should remain pooled after tab switches")
  A.truthy(modePanel._xivEquipPool.items.button[1].enabled, "rebound manual mode controls should be enabled again")
  A.truthy(mapPanel._xivEquipPool.items.dropdown[1].enabled, "stored mapping controls should re-enable with manual mode")
end)

test("Automatic keeps the remembered manual configuration visible while Pawn supplies active weights", function()
  local addon, calls = harness()
  local profile = {
    id = "paladin-default",
    automatic = false,
    manual = { mode = "custom", customOverrides = {}, integration = { provider = "pawn", overrides = {} } },
  }
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  _G.UnitClass = function() return "Paladin", "PALADIN" end
  addon.XIVWeights = {
    Builtin = {
      Defaults = {
        SpecsForClass = function() return { { id = 70, name = "Retribution" } } end,
      },
    },
    Config = {
      ResolveResultForSpec = function()
        if profile.automatic then
          return {
            scale = { resolution = { sourceKind = "integration", sourceLabel = "Pawn", scaleLabel = "Retribution" } },
          }
        end
        return {
          scale = { resolution = { sourceKind = "default", sourceLabel = "Default", scaleLabel = "Retribution" } },
        }
      end,
      ListIntegrations = function()
        return {
          {
            id = "pawn",
            label = "Pawn",
            IsAvailable = function() return true end,
            Resolve = function() return { name = "Retribution" } end,
            ListScales = function() return { { key = "ret", name = "Retribution" } } end,
          },
        }
      end,
      ListManualScales = function() return {} end,
      SpecName = function() return "Retribution" end,
    },
  }
  addon.Profiles = {
    Config = {
      CurrentContext = function() return { classFile = "PALADIN", characterKey = "Test-Realm" } end,
      GetForCharacter = function() return profile end,
      List = function() return { profile } end,
      Usage = function() return { count = 1 } end,
      SetAutomatic = function(_, value) profile.automatic = value == true; return profile end,
      SetManualMode = function(_, value) profile.manual.mode = value; return profile end,
      SetPreferSetBonuses = function() return profile end,
      ClearIntegrationOverride = function() return profile end,
      SetIntegrationOverride = function() return profile end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  local page = Window.Frame.content.page
  local modePanel = page._xivEquipPool.items.panel[2]
  local automaticBox = modePanel._xivEquipPool.items.checkbox[1]
  automaticBox:SetChecked(true)
  automaticBox.scripts.OnClick(automaticBox)

  A.equal(profile.automatic, true, "Automatic click should enable Automatic on the Profile")
  A.equal(profile.manual.mode, "custom", "Automatic click should not mutate the stored manual mode")
  local refreshedModePanel = page._xivEquipPool.items.panel[2]
  A.truthy(refreshedModePanel._xivEquipPool.items.button[2].locked,
    "the remembered Custom mode should remain selected while Automatic is enabled")
  A.falsy(refreshedModePanel._xivEquipPool.items.button[3].locked,
    "Automatic's effective Pawn source should not replace the remembered manual mode in the UI")
  local refreshedMapPanel = page._xivEquipPool.items.panel[3]
  A.truthy(refreshedMapPanel:IsShown(), "the remembered Custom mapping panel should remain visible")
  A.equal(refreshedMapPanel._xivEquipPool.items.font[1].text, "Custom scale overrides by specialization")
  A.equal(refreshedMapPanel._xivEquipPool.items.dropdown[1].dropdownText, "Default")
  A.falsy(refreshedMapPanel._xivEquipPool.items.dropdown[1].enabled,
    "remembered Custom mappings should remain disabled while Automatic is enabled")
  local text = table.concat(calls.fontText, "\n")
  A.truthy(text:find("Active weights: Pawn | Retribution", 1, true), "Active source should show Pawn after enabling Automatic")
  A.truthy(text:find("Selection disabled while Automatic mode is engaged.", 1, true),
    "automatic mapping notice should explain why selection is unavailable")
end)

test("Integration dropdown refreshes live scales when opened and distinguishes the recommended choice", function()
  local addon, calls = harness()
  local profile = {
    id = "paladin-integration",
    automatic = false,
    manual = { mode = "integration", customOverrides = {}, integration = { provider = "pawn", overrides = {} } },
  }
  local scales = { { key = "ret-custom", name = "Retribution" } }
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  _G.UnitClass = function() return "Paladin", "PALADIN" end
  addon.XIVWeights = {
    Builtin = { Defaults = { SpecsForClass = function() return { { id = 70, name = "Retribution" } } end } },
    Config = {
      ResolveResultForSpec = function()
        return { scale = { resolution = { sourceLabel = "Pawn", scaleLabel = "Retribution" } } }
      end,
      ListIntegrations = function()
        return {
          {
            id = "pawn",
            label = "Pawn",
            IsAvailable = function() return true end,
            Resolve = function() return { name = "Retribution" } end,
            ListScales = function() return scales end,
          },
        }
      end,
      ListManualScales = function() return {} end,
      SpecName = function() return "Retribution" end,
    },
  }
  addon.Profiles = {
    Config = {
      CurrentContext = function() return { classFile = "PALADIN", characterKey = "Test-Realm" } end,
      GetForCharacter = function() return profile end,
      List = function() return { profile } end,
      Usage = function() return { count = 1 } end,
      ClearIntegrationOverride = function() return profile end,
      SetIntegrationOverride = function() return profile end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  local mapPanel = Window.Frame.content.page._xivEquipPool.items.panel[3]
  local menu = mapPanel._xivEquipPool.items.dropdown[1]
  A.equal(menu.dropdownText, "Recommended (Retribution)",
    "collapsed automatic selection should distinguish a recommendation from a pinned scale")

  calls.dropdownButtons = {}
  menu.dropdownInitializer()
  A.equal(calls.dropdownButtons[1].text, "Recommended (Retribution)")
  A.equal(calls.dropdownButtons[2].text, "Retribution")

  scales[#scales + 1] = { key = "ret-default", name = "Paladin: Retribution" }
  calls.dropdownButtons = {}
  menu.dropdownInitializer()
  A.equal(calls.dropdownButtons[3].text, "Paladin: Retribution",
    "opening the existing dropdown should read newly enabled provider scales")
end)

test("Config creates and selects Profiles inline and protects the class Default from deletion", function()
  local addon, calls = harness()
  local defaultProfile = {
    id = "paladin-default",
    name = "Default - Paladin",
    automatic = true,
    manual = { mode = "default", customOverrides = {}, integration = { overrides = {} } },
  }
  local activeProfile = defaultProfile
  local profiles = { defaultProfile }
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  _G.UnitClass = function() return "Paladin", "PALADIN" end
  _G.StaticPopupDialogs = nil
  _G.StaticPopup_Show = nil
  addon.XIVWeights = {
    Builtin = { Defaults = { SpecsForClass = function() return { { id = 70, name = "Retribution" } } end } },
    Config = {
      ResolveResultForSpec = function() return { scale = { resolution = { sourceLabel = "Default", scaleLabel = "Retribution" } } } end,
      ListIntegrations = function() return {} end,
      SpecName = function() return "Retribution" end,
    },
  }
  addon.Profiles = {
    Config = {
      CurrentContext = function() return { classFile = "PALADIN", characterKey = "Test-Realm" } end,
      GetForCharacter = function() return activeProfile end,
      List = function() return profiles end,
      Usage = function() return { count = 1 } end,
      DefaultProfileID = function() return defaultProfile.id end,
      AssignCharacter = function(_, _, profileID)
        for _, item in ipairs(profiles) do
          if item.id == profileID then activeProfile = item; return item end
        end
      end,
      Create = function(_, name)
        if name == "" then return nil end
        local created = {
          id = "paladin:raid",
          name = name,
          automatic = true,
          manual = { mode = "default", customOverrides = {}, integration = { overrides = {} } },
        }
        profiles[#profiles + 1] = created
        return created
      end,
      Delete = function(_, profileID)
        if profileID == defaultProfile.id then return nil, "default-profile" end
        for index, item in ipairs(profiles) do
          if item.id == profileID then table.remove(profiles, index); activeProfile = defaultProfile; return true end
        end
        return nil, "unknown-profile"
      end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  local profilePanel = Window.Frame.content.page._xivEquipPool.items.panel[1]
  local nameBox = profilePanel._xivEquipFrames["new-profile-name"]
  local create = profilePanel._xivEquipPool.items.button[1]
  local delete = profilePanel._xivEquipPool.items.button[2]
  A.falsy(delete.enabled, "Default - Paladin should not be deletable")

  nameBox:SetText("Raid")
  create.scripts.OnClick(create)
  A.equal(activeProfile.name, "Raid", "Create should select the new Profile for this character")
  A.truthy(delete.enabled, "a non-default active Profile should be deletable")

  delete.scripts.OnClick(delete)
  A.equal(activeProfile, defaultProfile, "deleting the active Profile should return the character to Default")
  A.falsy(delete.enabled, "Delete should become disabled again on the Default Profile")
end)

test("Config identifies missing per-spec Integration overrides and their Recommended fallback", function()
  local addon, calls = harness()
  local profile = {
    id = "paladin-integration",
    automatic = false,
    manual = {
      mode = "integration",
      customOverrides = {},
      integration = { provider = "pawn", overrides = { [65] = "My Holy Scale" } },
    },
  }
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  _G.UnitClass = function() return "Paladin", "PALADIN" end
  addon.XIVWeights = {
    Builtin = {
      Defaults = {
        SpecsForClass = function()
          return { { id = 65, name = "Holy" }, { id = 70, name = "Retribution" } }
        end,
      },
    },
    Config = {
      ResolveResultForSpec = function()
        return {
          scale = { resolution = {
            sourceKind = "integration",
            sourceLabel = "Pawn",
            scaleLabel = "Recommended Holy",
            fallback = true,
          } },
          configuredSelection = { provider = "pawn", scale = "My Holy Scale" },
          fallback = true,
          fallbackReason = "integration-scale-missing",
        }
      end,
      ListIntegrations = function()
        return { { id = "pawn", label = "Pawn", ListScales = function() return {} end } }
      end,
      ListManualScales = function() return {} end,
      SpecName = function(id) return id == 65 and "Holy" or "Retribution" end,
    },
  }
  addon.Profiles = {
    Config = {
      CurrentContext = function() return { classFile = "PALADIN", characterKey = "Test-Realm" } end,
      GetForCharacter = function() return profile end,
      List = function() return { profile } end,
      Usage = function() return { count = 1 } end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  local text = table.concat(calls.fontText, "\n")
  A.truthy(text:find("Holy %(Recommended fallback%)"),
    "missing Integration mappings should identify their effective Recommended fallback")
  A.truthy(text:find("Using Recommended %(Recommended Holy%)"),
    "fallback warning should name the effective recommended provider scale")
  A.falsy(text:find("Using Default", 1, true),
    "recommended provider fallback should not claim that Default is active")
end)

test("unavailable Integrations do not list scales and show Default fallback for automatic mapping", function()
  local addon, calls = harness()
  local listed = false
  local profile = {
    id = "paladin-integration",
    automatic = false,
    manual = { mode = "integration", customOverrides = {}, integration = { provider = "pawn", overrides = {} } },
  }
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  _G.UnitClass = function() return "Paladin", "PALADIN" end
  addon.XIVWeights = {
    Builtin = { Defaults = { SpecsForClass = function() return { { id = 70, name = "Retribution" } } end } },
    Config = {
      ResolveResultForSpec = function() return { scale = { resolution = { sourceLabel = "Default", scaleLabel = "Retribution" } } } end,
      ListIntegrations = function()
        return {
          {
            id = "pawn",
            label = "Pawn",
            IsAvailable = function() return false end,
            ListScales = function()
              listed = true
              error("unavailable provider must not be queried")
            end,
          },
        }
      end,
      SpecName = function() return "Retribution" end,
    },
  }
  addon.Profiles = {
    Config = {
      CurrentContext = function() return { classFile = "PALADIN", characterKey = "Test-Realm" } end,
      GetForCharacter = function() return profile end,
      List = function() return { profile } end,
      Usage = function() return { count = 1 } end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  local mapPanel = Window.Frame.content.page._xivEquipPool.items.panel[3]
  A.falsy(listed, "unavailable Integration must not receive ListScales calls")
  A.equal(mapPanel._xivEquipPool.items.dropdown[1].dropdownText, "Recommended (Default - Pawn unavailable)",
    "automatic Integration mapping should show its effective Default fallback")
end)

test("Scale editor uses its full width and refreshes the active selector label", function()
  local addon, calls = harness()
  local sourceScale = { id = "manual:source", name = "Protection Raid" }
  local scale = {
    id = "manual:retribution",
    name = "Retribution Raid",
    weights = { strength = 1 },
    source = { kind = "manual", importedFrom = "pawn" },
    meta = { specID = 70, importedFrom = "pawn" },
  }
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  _G.UnitClass = function() return "Paladin", "PALADIN" end
  addon.XIVWeights = {
    Builtin = {
      Defaults = {
        SpecsForClass = function() return { { id = 70, name = "Retribution" } } end,
      },
    },
    Config = {
      ListManualScales = function() return { scale } end,
      GetScaleSpecID = function(item) return item.meta.specID end,
      Repository = function()
        return {
          Get = function(_, id)
            if id == scale.id then return scale end
            if id == sourceScale.id then return sourceScale end
            return nil
          end,
        }
      end,
      SaveScale = function() end,
      SpecName = function() return "Retribution" end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  Window.ShowTab(2)
  local page = Window.Frame.content.page
  local specLabel = page._xivEquipPool.items.font[3]
  local scaleLabel = page._xivEquipPool.items.font[4]
  local specMenu = page._xivEquipPool.items.dropdown[1]
  local scaleMenu = page._xivEquipPool.items.dropdown[2]
  A.equal(specLabel.textColor[1], 1, "Specialization label should reset the prior Config page's green color")
  A.equal(specLabel.textColor[2], 1, "Specialization label should be white")
  A.truthy(scaleMenu.points[1][2] > specMenu.points[1][2] + specMenu.dropdownWidth,
    "specialization and scale dropdowns should have a visible gap")
  A.equal(scaleLabel.points[1][2], scaleMenu.points[1][2] + 16,
    "Scale label should align with the dropdown's visible left edge")
  local editorText = table.concat(calls.fontText, "\n")
  A.falsy(editorText:find("This scale is tied to this specialization.", 1, true),
    "editor should not reserve a summary card for redundant specialization information")
  A.falsy(editorText:find("Based on: Default", 1, true), "editor should not show routine provenance noise")
  local scroll = page._xivEquipFrames["settings-scroll"]
  local editor = scroll._xivEquipScrollChild
  local nameEdit = editor._xivEquipFrames["scale-name"]
  local nameLabel
  for _, item in ipairs(editor._xivEquipPool.items.font) do
    if item.text == "Scale name" then nameLabel = item end
  end
  A.truthy(nameLabel, "scale editor should show the Scale name label")
  A.equal(nameLabel.points[1][2], 14, "scale editor content should use the left side freed by the removed summary card")
  A.equal(nameEdit.points[1][2], nameLabel.points[1][2], "scale name input should align with its label")
  A.truthy(nameEdit.points[1][3] < nameLabel.points[1][3], "scale name input should sit below its label")
  local swingLabel
  for _, item in ipairs(editor._xivEquipPool.items.font) do
    if item.text == "Weapon Swing Interval / Speed" then swingLabel = item end
  end
  local swingEdit = editor._xivEquipFrames["weight-edit:weaponSwingIntervalSeconds"]
  A.truthy(swingLabel, "scale editor should show the weapon swing interval label")
  A.truthy(swingEdit.points[1][2] >= swingLabel.points[1][2] + 286,
    "the full-width editor should give stat labels a generous lane before numeric inputs")
  nameEdit:SetText("Retribution Mythic")
  nameEdit.scripts.OnEnterPressed(nameEdit)

  A.equal(scale.name, "Retribution Mythic", "rename should save the selected Custom scale")
  A.equal(page._xivEquipPool.items.dropdown[2].dropdownText, "Retribution Mythic", "rename should refresh the selected-scale menu label")

  calls.buttons["Import"].scripts.OnClick(calls.buttons["Import"])
  A.truthy(Window.ImportDialog:IsShown(), "Import should open its dialog")
  A.equal(Window.ImportDialog.frameStrata, "DIALOG", "Import dialog should render above the settings window")
  calls.buttons["Export"].scripts.OnClick(calls.buttons["Export"])
  A.truthy(Window.TextDialog:IsShown(), "Export should open its dialog")
  A.equal(Window.TextDialog.frameStrata, "DIALOG", "Export dialog should render above the settings window")
end)

return tests
