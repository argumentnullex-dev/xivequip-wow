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
      SetTextColor = function() end,
      SetFontObject = function(self, fontObject)
        self.fontObject = fontObject
        calls.fontObjects[#calls.fontObjects + 1] = fontObject
      end,
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
    function f:SetMinMaxValues() end
    function f:SetValueStep() end
    function f:SetObeyStepOnDrag() end
    function f:SetValue(value) self.value = value end
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
  _G.UIDropDownMenu_Initialize = function() end
  _G.UIDropDownMenu_SetWidth = function(menu, width)
    if type(menu) ~= "table" or type(width) ~= "number" then
      error("UIDropDownMenu_SetWidth expects (frame, width)")
    end
    menu.dropdownWidth = width
  end
  _G.UIDropDownMenu_SetSelectedValue = function() end
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
      GetPlannerMode = function() return settingsTable.PlannerMode or "native" end,
      SetPlannerMode = function(_, mode) settingsTable.PlannerMode = mode end,
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
  A.truthy(calls.buttons["Manage"], "Config should expose Profile management")
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

  profile.automatic = true
  Window.ShowTab(1)
  A.equal(#profilePanel._xivEquipPool.items.font, profileFontCount, "profile controls should be reused after a state change")
  A.equal(#profilePanel._xivEquipPool.items.button, profileButtonCount, "profile buttons should not accumulate after a state change")
  A.equal(#modePanel._xivEquipPool.items.button, modeButtonCount, "mode buttons should not accumulate after a state change")
  A.falsy(modePanel._xivEquipPool.items.button[1].enabled, "automatic mode should disable manual mode controls")
  A.equal(modePanel._xivEquipPool.items.button[2].text, "[Stored] Custom Scales", "Automatic should retain the selected manual mode as disabled context")
  local mapPanel = page._xivEquipPool.items.panel[3]
  A.truthy(mapPanel:IsShown(), "Automatic should retain the stored per-spec mapping as visible context")
  A.falsy(mapPanel._xivEquipPool.items.dropdown[1].enabled, "Automatic should disable stored per-spec mapping controls")

  profile.automatic = false
  Window.ShowTab(2)
  Window.ShowTab(1)
  A.equal(Window.Frame.content.page, page, "Config to Scales to Config should reuse the same page frame")
  A.equal(#profilePanel._xivEquipPool.items.font, profileFontCount, "profile controls should remain pooled after tab switches")
  A.equal(#modePanel._xivEquipPool.items.button, modeButtonCount, "mode controls should remain pooled after tab switches")
  A.truthy(modePanel._xivEquipPool.items.button[1].enabled, "rebound manual mode controls should be enabled again")
  A.truthy(mapPanel._xivEquipPool.items.dropdown[1].enabled, "stored mapping controls should re-enable with manual mode")
end)

test("Profile Management reuses its name field and refreshes profile usage", function()
  local addon, calls = harness()
  local usageCount = 1
  local profile = {
    id = "paladin-default",
    name = "Paladin Default",
    automatic = true,
    manual = { mode = "default", customOverrides = {}, integration = { overrides = {} } },
  }
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 70, "Retribution" end
  _G.UnitClass = function() return "Paladin", "PALADIN" end
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
      GetForCharacter = function() return profile end,
      List = function() return { profile } end,
      Usage = function() return { count = usageCount } end,
      DefaultProfileID = function() return profile.id end,
    },
  }

  local Window = loadWindow(addon, calls)
  Window.Open()
  calls.buttons["Manage"].scripts.OnClick(calls.buttons["Manage"])
  local detail = Window.ProfileDialog.body._xivEquipPool.items.panel[1]
  local nameBox = detail._xivEquipFrames["profile-name"]
  usageCount = 2
  calls.buttons["Manage"].scripts.OnClick(calls.buttons["Manage"])

  A.equal(detail._xivEquipFrames["profile-name"], nameBox, "Profile Management should reuse the keyed name field")
  A.equal(detail._xivEquipPool.items.font[3].text, "Used by 2 characters", "Profile Management should refresh usage when reopened")
end)

test("Config identifies missing per-spec Integration overrides and their Default fallback", function()
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
        return { scale = { resolution = { sourceLabel = "Pawn", scaleLabel = "Retribution" } } }
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
  A.truthy(text:find("Holy %(Default fallback%)"), "missing Integration mappings should identify their effective Default fallback")
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
  A.equal(mapPanel._xivEquipPool.items.dropdown[1].dropdownText, "Default - Pawn unavailable", "automatic Integration mapping should show its effective Default fallback")
end)

test("Scale editor displays import provenance and refreshes the active selector label", function()
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
  local importedText = table.concat(calls.fontText, "\n")
  A.truthy(importedText:find("Imported from: Pawn", 1, true), "imported scales should display their real provenance")
  A.falsy(importedText:find("Based on: Default", 1, true), "imported scales should not claim to be based on Default")
  local scroll = page._xivEquipFrames["settings-scroll"]
  local nameEdit = scroll._xivEquipScrollChild._xivEquipFrames["scale-name"]
  nameEdit:SetText("Retribution Mythic")
  nameEdit.scripts.OnEnterPressed(nameEdit)

  A.equal(scale.name, "Retribution Mythic", "rename should save the selected Custom scale")
  A.equal(page._xivEquipPool.items.dropdown[2].dropdownText, "Retribution Mythic", "rename should refresh the selected-scale menu label")

  scale.meta.duplicatedFrom = sourceScale.id
  scale.source.duplicatedFrom = sourceScale.id
  Window.ScaleRevision = (Window.ScaleRevision or 0) + 1
  calls.fontText = {}
  Window.ShowTab(2)
  A.truthy(table.concat(calls.fontText, "\n"):find("Duplicated from: Protection Raid", 1, true), "duplicated scales should identify their source scale")
end)

return tests
