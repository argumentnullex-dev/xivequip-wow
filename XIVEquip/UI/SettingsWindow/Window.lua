-- UI/SettingsWindow/Window.lua
local addonName, XIVEquip = ...
XIVEquip.UI = XIVEquip.UI or {}
XIVEquip.UI.SettingsWindow = XIVEquip.UI.SettingsWindow or {}

local Window = XIVEquip.UI.SettingsWindow
local PREFIX = (XIVEquip.L and XIVEquip.L.AddonPrefix) or "XIVEquip: "

local tabs = { "General", "XIVWeights Scales", "XIVEquip Core" }

local function settings()
  return XIVEquip.Settings and XIVEquip.Settings:Get() or _G.XIVEquip_Settings or {}
end

local function currentSpecID()
  local index = GetSpecialization and GetSpecialization()
  if not index then return nil end
  return GetSpecializationInfo and select(1, GetSpecializationInfo(index)) or nil
end

local function currentClassFile()
  return UnitClass and select(2, UnitClass("player")) or nil
end

local function font(parent, template, text)
  local f = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
  f:SetText(text or "")
  f:SetJustifyH("LEFT")
  return f
end

local function button(parent, text, width, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 120, height or 24)
  b:SetText(text)
  return b
end

local function checkbox(parent, text, checked, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  cb.Text:SetText(text)
  cb:SetChecked(checked == true)
  cb:SetScript("OnClick", function(self) onClick(self:GetChecked()) end)
  return cb
end

local function clearContent(frame)
  for _, child in ipairs({ frame:GetChildren() }) do child:Hide() end
end

local function savePosition(frame)
  local st = settings()
  st.UI = st.UI or {}
  st.UI.SettingsWindow = st.UI.SettingsWindow or {}
  local point, _, relativePoint, x, y = frame:GetPoint()
  st.UI.SettingsWindow.Point = point
  st.UI.SettingsWindow.RelativePoint = relativePoint
  st.UI.SettingsWindow.X = x
  st.UI.SettingsWindow.Y = y
end

local function restorePosition(frame)
  local ui = settings().UI and settings().UI.SettingsWindow
  if ui and ui.Point then
    frame:ClearAllPoints()
    frame:SetPoint(ui.Point, UIParent, ui.RelativePoint or ui.Point, tonumber(ui.X) or 0, tonumber(ui.Y) or 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function makeContent(parent)
  local content = CreateFrame("Frame", nil, parent)
  content:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -78)
  content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 18)
  return content
end

local function specRows()
  local classFile = currentClassFile()
  if XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config then
    XIVEquip.XIVWeights.Config.EnsureClassSpecScales(classFile)
  end
  local defaults = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Builtin and XIVEquip.XIVWeights.Builtin.Defaults
  local specs = defaults and defaults.SpecsForClass(classFile) or {}
  return specs
end

local featureGroups = {
  { "Primary", { "strength", "agility", "intellect" } },
  { "Defensive / Base", { "stamina", "armor", "bonusArmor" } },
  { "Secondary", { "criticalStrike", "haste", "mastery", "versatility" } },
  { "Tertiary", { "leech", "avoidance", "movementSpeed", "indestructible" } },
  { "Weapon", { "weaponDps", "weaponMinDamage", "weaponMaxDamage", "weaponSwingIntervalSeconds" } },
}

local featureLabels = {
  strength = "Strength",
  agility = "Agility",
  intellect = "Intellect",
  stamina = "Stamina",
  armor = "Armor",
  bonusArmor = "Bonus Armor",
  criticalStrike = "Critical Strike",
  haste = "Haste",
  mastery = "Mastery",
  versatility = "Versatility",
  leech = "Leech",
  avoidance = "Avoidance",
  movementSpeed = "Movement Speed",
  indestructible = "Indestructible",
  weaponDps = "Weapon DPS",
  weaponMinDamage = "Weapon Min Damage",
  weaponMaxDamage = "Weapon Max Damage",
  weaponSwingIntervalSeconds = "Weapon Swing Interval / Speed",
}

local function addScaleEditor(content, scale, x, y)
  if not scale then return y end
  local Config = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config
  local working = {}
  for k, v in pairs(scale.weights or {}) do working[k] = tonumber(v) or 0 end

  local header = font(content, "GameFontNormal", "Edit current spec scale: " .. tostring(scale.name or scale.id))
  header:SetPoint("TOPLEFT", x, y)
  y = y - 24

  local function addRow(feature)
    local label = font(content, "GameFontHighlightSmall", featureLabels[feature] or feature)
    label:SetPoint("TOPLEFT", x, y)

    local edit = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    edit:SetSize(44, 20)
    edit:SetPoint("TOPLEFT", x + 170, y + 4)
    edit:SetAutoFocus(false)
    edit:SetText(string.format("%.1f", tonumber(working[feature]) or 0))

    local slider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x + 226, y + 1)
    slider:SetWidth(140)
    slider:SetMinMaxValues(0, 1)
    slider:SetValueStep(0.1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetValue(tonumber(working[feature]) or 0)
    slider:SetScript("OnValueChanged", function(_, value)
      local rounded = math.floor((tonumber(value) or 0) * 10 + 0.5) / 10
      working[feature] = rounded
      edit:SetText(string.format("%.1f", rounded))
    end)
    edit:SetScript("OnEnterPressed", function(self)
      local value = tonumber(self:GetText())
      if value and value >= 0 and value <= 1 then
        working[feature] = value
        slider:SetValue(value)
        self:ClearFocus()
      else
        print(PREFIX .. "Weight must be between 0 and 1.")
      end
    end)
    y = y - 24
  end

  for _, group in ipairs(featureGroups) do
    local groupLabel = font(content, "GameFontNormalSmall", group[1])
    groupLabel:SetPoint("TOPLEFT", x, y)
    y = y - 18
    for _, feature in ipairs(group[2]) do addRow(feature) end
  end

  local save = button(content, "Save Scale", 100, 22)
  save:SetPoint("TOPLEFT", x, y - 4)
  save:SetScript("OnClick", function()
    scale.weights = working
    local ok, err = Config.ValidateAuthoredWeights(scale)
    if not ok then
      print(PREFIX .. tostring(err))
      return
    end
    Config.SaveScale(scale)
    print(PREFIX .. "Saved " .. tostring(scale.name or scale.id) .. " weights.")
  end)
  return y - 34
end

local function showGeneral(content)
  clearContent(content)
  local S = XIVEquip.Settings
  local title = font(content, "GameFontNormalLarge", "General")
  title:SetPoint("TOPLEFT", 0, 0)

  local y = -28
  local rows = {
    { "Show login message", function() return S:GetMessage("Login") end, function(v) S:SetMessage("Login", v) end },
    { "Show equip messages", function() return S:GetMessage("Equip") end, function(v) S:SetMessage("Equip", v) end },
    { "Debug logging", function() return S:GetDebugEnabled() end, function(v) S:SetDebugEnabled(v) end },
    { "Auto-equip on spec change", function() return S:GetAutomation("SpecEquip") end, function(v) S:SetAutomation("SpecEquip", v) end },
    { "Auto-save spec equipment set after equip", function() return S:GetAutomation("SaveSpecSet") end, function(v) S:SetAutomation("SaveSpecSet", v) end },
    { "Hide minimap button", function() return S:GetMinimapHidden() end, function(v)
      S:SetMinimapHidden(v)
      if XIVEquip.UI.MinimapButton and XIVEquip.UI.MinimapButton.Refresh then XIVEquip.UI.MinimapButton.Refresh() end
    end },
  }
  for _, row in ipairs(rows) do
    local cb = checkbox(content, row[1], row[2](), row[3])
    cb:SetPoint("TOPLEFT", 4, y)
    y = y - 30
  end
end

local function showScales(content)
  clearContent(content)
  local Config = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config
  local title = font(content, "GameFontNormalLarge", "XIVWeights Scales")
  title:SetPoint("TOPLEFT", 0, 0)
  local note = font(content, "GameFontHighlightSmall", "Generated spec scales are editable copies of XIVEquip defaults.")
  note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  note:SetWidth(560)

  local current = currentSpecID()
  local y = -54
  for _, spec in ipairs(specRows()) do
    local scale = Config and Config.EnsureSpecScale(spec.id)
    local label = font(content, "GameFontNormal", tostring(spec.name))
    label:SetPoint("TOPLEFT", 6, y)
    if spec.id == current then label:SetText(tostring(spec.name) .. "  (current spec)") end

    local tied = font(content, "GameFontHighlightSmall", "Tied to spec ID " .. tostring(spec.id))
    tied:SetPoint("TOPLEFT", 160, y - 1)

    local reset = button(content, "Reset to Default", 125, 22)
    reset:SetPoint("TOPRIGHT", -4, y + 4)
    reset:SetScript("OnClick", function()
      local newScale = Config.ResetSpecScale(spec.id)
      print(PREFIX .. "Reset " .. tostring(spec.name) .. " weights to XIVEquip defaults.")
      Window.ShowTab(2)
    end)

    y = y - 34
  end

  local currentScale = current and Config and Config.EnsureSpecScale(current)
  addScaleEditor(content, currentScale, 6, y - 8)
end

local function showCore(content)
  clearContent(content)
  local S = XIVEquip.Settings
  local Config = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config
  local title = font(content, "GameFontNormalLarge", "XIVEquip Core")
  title:SetPoint("TOPLEFT", 0, 0)

  local mode = font(content, "GameFontNormal", "Planner mode: " .. tostring(S:GetPlannerMode()))
  mode:SetPoint("TOPLEFT", 4, -32)

  local legacy = button(content, "Use Legacy", 110, 24)
  legacy:SetPoint("TOPLEFT", 4, -58)
  legacy:SetScript("OnClick", function()
    S:SetPlannerMode("legacy")
    Window.ShowTab(3)
  end)

  local native = button(content, "Use Native 2.0", 130, 24)
  native:SetPoint("LEFT", legacy, "RIGHT", 10, 0)
  native:SetScript("OnClick", function()
    S:SetPlannerMode("native")
    Window.ShowTab(3)
  end)

  local specID = currentSpecID()
  local selection = specID and Config and Config.GetSpecSelection(specID)
  local specText = "Current specialization: " .. tostring(specID or "unknown")
  if selection then
    specText = specText .. "  |  Source: " .. tostring(selection.provider) .. "  |  Scale: " .. tostring(selection.scale)
  end
  local specLine = font(content, "GameFontHighlight", specText)
  specLine:SetPoint("TOPLEFT", 4, -98)
  specLine:SetWidth(560)

  local default = button(content, "Use XIVEquip Default", 160, 24)
  default:SetPoint("TOPLEFT", 4, -130)
  default:SetScript("OnClick", function()
    if specID and Config then
      Config.EnsureSpecScale(specID)
      Config.SetSpecSelection(specID, "default", Config.GeneratedScaleID(specID))
      Window.ShowTab(3)
    end
  end)
end

local renderers = { showGeneral, showScales, showCore }

function Window.ShowTab(index)
  local frame = Window.Frame
  if not frame then return end
  frame.selectedTab = index
  for i, tab in ipairs(frame.tabs or {}) do
    if i == index then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
  end
  renderers[index](frame.content)
end

function Window.Create()
  if Window.Frame then return Window.Frame end

  local frame = CreateFrame("Frame", "XIVEquipSettingsWindow", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(760, 760)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition(self)
  end)
  frame:Hide()

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
  title:SetText("XIVEquip")

  frame.content = makeContent(frame)
  frame.tabs = {}
  for i, label in ipairs(tabs) do
    local tab = CreateFrame("Button", "XIVEquipSettingsTab" .. tostring(i), frame, "PanelTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(label)
    tab:SetScript("OnClick", function(self) Window.ShowTab(self:GetID()) end)
    if i == 1 then
      tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 8, 2)
    else
      tab:SetPoint("LEFT", frame.tabs[i - 1], "RIGHT", -14, 0)
    end
    frame.tabs[i] = tab
  end
  PanelTemplates_SetNumTabs(frame, #tabs)
  PanelTemplates_SetTab(frame, 1)

  restorePosition(frame)
  Window.Frame = frame
  return frame
end

function Window.Open()
  local frame = Window.Create()
  Window.ShowTab(frame.selectedTab or 1)
  frame:Show()
end

function Window.Toggle()
  local frame = Window.Create()
  if frame:IsShown() then frame:Hide() else Window.Open() end
end
