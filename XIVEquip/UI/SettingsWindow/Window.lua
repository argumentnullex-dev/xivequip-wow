-- UI/SettingsWindow/Window.lua
local addonName, XIVEquip = ...
XIVEquip.UI = XIVEquip.UI or {}
XIVEquip.UI.SettingsWindow = XIVEquip.UI.SettingsWindow or {}

local Window = XIVEquip.UI.SettingsWindow
local PREFIX = (XIVEquip.L and XIVEquip.L.AddonPrefix) or "XIVEquip: "
local WINDOW_NAME = "XIVEquipSettingsWindow"
local GENERAL_MACRO_MAX = 120
local MACRO_BODY = "/xivequip"
local MACRO_ICON = "Garrison_ArmorUpgrade"

local tabs = { "General", "XIVWeights Scales", "XIVEquip Core" }

local function settings()
  return XIVEquip.Settings and XIVEquip.Settings:Get() or _G.XIVEquip_Settings or {}
end

local function Config()
  return XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config
end

local function currentSpecID()
  local index = GetSpecialization and GetSpecialization()
  if not index then return nil end
  return GetSpecializationInfo and select(1, GetSpecializationInfo(index)) or nil
end

local function currentSpecName()
  local index = GetSpecialization and GetSpecialization()
  if index and GetSpecializationInfo then
    local _, name = GetSpecializationInfo(index)
    if name and name ~= "" then return name end
  end
  local C = Config()
  local specID = currentSpecID()
  return C and C.SpecName and C.SpecName(specID) or nil
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
  if frame.page then frame.page:Hide() end
  local page = CreateFrame("Frame", nil, frame)
  page:SetAllPoints(frame)
  frame.page = page
  return page
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

local function registerEscapeClose(frameName)
  if type(UISpecialFrames) ~= "table" then return end
  for _, name in ipairs(UISpecialFrames) do
    if name == frameName then return end
  end
  table.insert(UISpecialFrames, frameName)
end

local function cursorHasPickedMacro(index, name)
  if GetCursorInfo then
    local kind, id = GetCursorInfo()
    if kind == "macro" then return id == index or id == name end
    return false
  end
  return not CursorHasMacro or CursorHasMacro()
end

local function macroSlotName(index)
  if not index or index <= 0 then return nil end
  if C_Macro and C_Macro.GetMacroName then
    return C_Macro.GetMacroName(index)
  end
  if GetMacroInfo then
    local name = GetMacroInfo(index)
    return name
  end
  return nil
end

local function isGeneralMacroIndex(index)
  index = tonumber(index)
  return index and index >= 1 and index <= GENERAL_MACRO_MAX
end

local function findActionBarMacro(name)
  if not GetActionInfo then return nil end
  for slot = 1, 180 do
    local actionType, macroID = GetActionInfo(slot)
    if actionType == "macro" and isGeneralMacroIndex(macroID) and macroSlotName(macroID) == name then
      return macroID
    end
  end
  return nil
end

local function findNamedMacro(name, savedID)
  local placed = findActionBarMacro(name)
  if placed then return placed end

  local saved = tonumber(savedID)
  if isGeneralMacroIndex(saved) and macroSlotName(saved) == name then
    return saved
  end

  local index = GetMacroIndexByName and GetMacroIndexByName(name) or 0
  if isGeneralMacroIndex(index) then return index end

  for i = 1, GENERAL_MACRO_MAX do
    if macroSlotName(i) == name then return i end
  end
  return 0
end

local function makeContent(parent)
  local content = CreateFrame("Frame", nil, parent)
  content:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -78)
  content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 18)
  return content
end

local function specRows()
  local classFile = currentClassFile()
  local defaults = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Builtin and XIVEquip.XIVWeights.Builtin.Defaults
  return defaults and defaults.SpecsForClass(classFile) or {}
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

local function listScales()
  local C = Config()
  if not C then return {} end
  local list = C.ListManualScales()
  table.sort(list, function(a, b)
    local at = a.meta and a.meta.tiedToSpecID and 0 or 1
    local bt = b.meta and b.meta.tiedToSpecID and 0 or 1
    if at ~= bt then return at < bt end
    return tostring(a.name or a.id) < tostring(b.name or b.id)
  end)
  return list
end

local function pawnAdapter()
  return {
    ListScales = function()
      return XIVEquip.Pawn and XIVEquip.Pawn.GetActiveScales and XIVEquip.Pawn.GetActiveScales() or {}
    end,
    ResolveValues = function(selection)
      if XIVEquip.Pawn and XIVEquip.Pawn.GetScaleValues then
        return XIVEquip.Pawn.GetScaleValues(selection)
      end
      for _, entry in ipairs(XIVEquip.Pawn and XIVEquip.Pawn.GetActiveScales and XIVEquip.Pawn.GetActiveScales() or {}) do
        if entry.key == selection or entry.name == selection then return entry.values, entry end
      end
      return nil, nil
    end,
  }
end

local function uniqueScaleID(prefix)
  local C = Config()
  local repo = C and C.Repository()
  Window.NextScaleID = (Window.NextScaleID or 0) + 1
  for i = 1, 200 do
    local id = tostring(prefix or "manual") .. ":" .. tostring(time and time() or 0) .. ":" .. tostring(Window.NextScaleID + i)
    if not repo or not repo:Get(id) then
      Window.NextScaleID = Window.NextScaleID + i
      return id
    end
  end
  return tostring(prefix or "manual") .. ":" .. tostring(Window.NextScaleID)
end

local function selectedScaleID()
  local C = Config()
  local current = currentSpecID()
  if not Window.SelectedScaleID and C and current then
    local sel = C.GetSpecSelection(current)
    Window.SelectedScaleID = sel and sel.scale or C.GeneratedScaleID(current)
  end
  if C and Window.SelectedScaleID and C.Repository():Get(Window.SelectedScaleID) then
    return Window.SelectedScaleID
  end
  local list = listScales()
  return list[1] and list[1].id or nil
end

local function createScroll(parent, x, y, width, height)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", x, y)
  scroll:SetSize(width, height)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(width - 24, height)
  scroll:SetScrollChild(child)
  return scroll, child
end

local function addScaleEditor(content, scale, x, y, width)
  if not scale then return y end
  local C = Config()
  local working = {}
  for k, v in pairs(scale.weights or {}) do working[k] = tonumber(v) or 0 end

  local header = font(content, "GameFontNormal", "Edit scale")
  header:SetPoint("TOPLEFT", x, y)
  y = y - 26

  local nameLabel = font(content, "GameFontHighlightSmall", "Name")
  nameLabel:SetPoint("TOPLEFT", x, y + 2)
  local nameEdit = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
  nameEdit:SetSize(width - 76, 20)
  nameEdit:SetPoint("TOPLEFT", x + 58, y + 4)
  nameEdit:SetAutoFocus(false)
  nameEdit:SetText(tostring(scale.name or scale.id))
  y = y - 30

  local specNote = font(content, "GameFontHighlightSmall", "Spec: " .. tostring((scale.meta and scale.meta.specName) or "None"))
  specNote:SetPoint("TOPLEFT", x, y)
  specNote:SetWidth(width)
  y = y - 26

  local function addRow(feature)
    local label = font(content, "GameFontHighlightSmall", featureLabels[feature] or feature)
    label:SetPoint("TOPLEFT", x, y)

    local edit = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    edit:SetSize(56, 20)
    edit:SetPoint("TOPLEFT", x + 175, y + 4)
    edit:SetAutoFocus(false)
    edit:SetText(string.format("%.2f", tonumber(working[feature]) or 0))

    local slider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x + 244, y + 1)
    slider:SetWidth(160)
    slider:SetMinMaxValues(0, 1)
    slider:SetValueStep(0.1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    for i = 0, 10 do
      local tick = font(content, "GameFontDisableSmall", "|")
      tick:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", (i * 16) - 1, 5)
    end
    local suppress = true
    slider:SetValue(tonumber(working[feature]) or 0)
    suppress = false
    slider:SetScript("OnValueChanged", function(_, value)
      if suppress then return end
      local rounded = math.floor((tonumber(value) or 0) * 10 + 0.5) / 10
      working[feature] = rounded
      edit:SetText(string.format("%.2f", rounded))
    end)
    edit:SetScript("OnEnterPressed", function(self)
      local value = tonumber(self:GetText())
      if value and value >= 0 and value <= 1 then
        working[feature] = value
        suppress = true
        slider:SetValue(value)
        suppress = false
        self:SetText(string.format("%.2f", value))
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
    y = y - 4
  end

  local save = button(content, "Save", 82, 22)
  save:SetPoint("TOPLEFT", x, y - 4)
  save:SetScript("OnClick", function()
    scale.name = nameEdit:GetText()
    scale.weights = working
    local ok, err = C.ValidateAuthoredWeights(scale)
    if not ok then
      print(PREFIX .. tostring(err))
      return
    end
    C.SaveScale(scale)
    print(PREFIX .. "Saved " .. tostring(scale.name or scale.id) .. " weights.")
    Window.ShowTab(2)
  end)

  local tiedSpecID = scale.meta and scale.meta.tiedToSpecID
  if tiedSpecID then
    local reset = button(content, "Reset", 82, 22)
    reset:SetPoint("LEFT", save, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function()
      local newScale = C.ResetSpecScale(tiedSpecID)
      if newScale then
        Window.SelectedScaleID = newScale.id
        print(PREFIX .. "Reset " .. tostring(newScale.name or scale.name or scale.id) .. " weights to XIVEquip defaults.")
      end
      Window.ShowTab(2)
    end)
  end
  return y - 36
end

local function createEquipMacro()
  local st = settings()
  local name = "XIVEquip"
  local body = MACRO_BODY
  local icon = MACRO_ICON
  local index = findNamedMacro(name, st.MacroID)
  local ok = true
  if index and index > 0 then
    if EditMacro then
      ok = pcall(EditMacro, index, name, icon, body)
    end
  elseif CreateMacro then
    ok, index = pcall(CreateMacro, name, icon, body, nil)
    if not ok then index = 0 end
  end
  if (not index or index <= 0) and GetMacroIndexByName then
    local resolved = GetMacroIndexByName(name)
    if isGeneralMacroIndex(resolved) then index = resolved end
  end
  st.MacroID = index or 0
  local pickedUp = false
  if ok and index and index > 0 and PickupMacro then
    local pickupOk = pcall(PickupMacro, index)
    pickedUp = pickupOk and cursorHasPickedMacro(index, name)
    if not pickedUp then
      pickupOk = pcall(PickupMacro, name)
      pickedUp = pickupOk and cursorHasPickedMacro(index, name)
    end
  end
  if ok and index and index > 0 and pickedUp then
    print(PREFIX .. "Created /xivequip macro and placed it on your cursor.")
  elseif ok and index and index > 0 then
    print(PREFIX .. "Created /xivequip macro, but WoW did not place it on your cursor.")
  else
    print(PREFIX .. "Unable to create macro.")
  end
end

local function showGeneral(content)
  local page = clearContent(content)
  local S = XIVEquip.Settings
  local title = font(page, "GameFontNormalLarge", "General")
  title:SetPoint("TOPLEFT", 0, 0)

  local y = -28
  local rows = {
    { "Show login message", function() return S:GetMessage("Login") end, function(v) S:SetMessage("Login", v) end },
    { "Show equip messages", function() return S:GetMessage("Equip") end, function(v) S:SetMessage("Equip", v) end },
    { "Debug logging", function() return S:GetDebugEnabled() end, function(v) S:SetDebugEnabled(v) end },
    { "Auto-equip on spec change", function() return S:GetAutomation("SpecEquip") end, function(v) S:SetAutomation("SpecEquip", v) end },
    { "Auto-save spec equipment set after equip", function() return S:GetAutomation("SaveSpecSet") end, function(v) S:SetAutomation("SaveSpecSet", v) end },
    { "Show minimap button", function() return not S:GetMinimapHidden() end, function(v)
      S:SetMinimapHidden(v ~= true)
      if XIVEquip.UI.MinimapButton and XIVEquip.UI.MinimapButton.Refresh then XIVEquip.UI.MinimapButton.Refresh() end
    end },
  }
  for _, row in ipairs(rows) do
    local cb = checkbox(page, row[1], row[2](), row[3])
    cb:SetPoint("TOPLEFT", 4, y)
    y = y - 30
  end

  local macroTitle = font(page, "GameFontNormal", "Macro")
  macroTitle:SetPoint("TOPLEFT", 4, y - 12)
  local macroNote = font(page, "GameFontHighlightSmall", "Create a draggable /xivequip macro for your bars.")
  macroNote:SetPoint("TOPLEFT", 4, y - 34)
  macroNote:SetWidth(420)
  local macro = button(page, "Create Macro", 120, 24)
  macro:SetPoint("TOPLEFT", 4, y - 62)
  macro:SetScript("OnClick", createEquipMacro)
end

local function showScales(content)
  local page = clearContent(content)
  local C = Config()
  local title = font(page, "GameFontNormalLarge", "XIVWeights Scales")
  title:SetPoint("TOPLEFT", 0, 0)
  local note = font(page, "GameFontHighlightSmall", "Built-in defaults are immutable. Customize a spec to create an editable SavedVariables copy.")
  note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  note:SetWidth(640)

  if not C then return end
  local specs = specRows()
  local scales = listScales()
  local selected = selectedScaleID()
  Window.SelectedScaleID = selected

  local _, left = createScroll(page, 0, -48, 230, 610)
  local leftTitle = font(left, "GameFontNormal", "Scales")
  leftTitle:SetPoint("TOPLEFT", 0, 0)

  local newButton = button(left, "Create", 70, 22)
  newButton:SetPoint("TOPLEFT", 0, -24)
  newButton:SetScript("OnClick", function()
    local scale = C.CreateManualScale(uniqueScaleID("manual"), "New Scale", C.NewManualScaleSeed(currentSpecID()), currentSpecID())
    if scale then Window.SelectedScaleID = scale.id end
    Window.ShowTab(2)
  end)
  local duplicate = button(left, "Duplicate", 82, 22)
  duplicate:SetPoint("LEFT", newButton, "RIGHT", 4, 0)
  duplicate:SetScript("OnClick", function()
    if not Window.SelectedScaleID then return end
    local source = C.Repository():Get(Window.SelectedScaleID)
    if not source then return end
    local scale = C.DuplicateScale(source.id, uniqueScaleID("manual"), tostring(source.name or "Scale") .. " Copy")
    if scale then Window.SelectedScaleID = scale.id end
    Window.ShowTab(2)
  end)
  local delete = button(left, "Delete", 64, 22)
  delete:SetPoint("TOPLEFT", 0, -52)
  delete:SetScript("OnClick", function()
    local source = Window.SelectedScaleID and C.Repository():Get(Window.SelectedScaleID)
    if not source then return end
    if source.meta and source.meta.tiedToSpecID then
      print(PREFIX .. "Spec scales cannot be deleted. Use Reset to restore defaults.")
      return
    end
    C.DeleteScale(source.id)
    Window.SelectedScaleID = nil
    Window.ShowTab(2)
  end)

  local y = -86
  if #specs > 0 then
    local specTitle = font(left, "GameFontNormalSmall", "Spec defaults")
    specTitle:SetPoint("TOPLEFT", 0, y)
    y = y - 22
    for _, spec in ipairs(specs) do
      local customize = button(left, "Customize " .. tostring(spec.name or spec.id), 206, 22)
      customize:SetPoint("TOPLEFT", 0, y)
      customize:SetScript("OnClick", function()
        local scale = C.EnsureSpecScale(spec.id)
        if scale then
          Window.SelectedScaleID = scale.id
          C.SetSpecSelection(spec.id, "manual", scale.id)
        end
        Window.ShowTab(2)
      end)
      y = y - 25
    end
    y = y - 8
  end

  local savedTitle = font(left, "GameFontNormalSmall", "Saved scales")
  savedTitle:SetPoint("TOPLEFT", 0, y)
  y = y - 22
  for _, scale in ipairs(scales) do
    local label = tostring(scale.name or scale.id)
    if scale.meta and scale.meta.tiedToSpecID then label = label .. " *" end
    local pick = button(left, label, 214, 22)
    pick:SetPoint("TOPLEFT", 0, y)
    if scale.id == selected then pick:Disable() end
    pick:SetScript("OnClick", function()
      Window.SelectedScaleID = scale.id
      Window.ShowTab(2)
    end)
    y = y - 25
  end

  local importTitle = font(left, "GameFontNormalSmall", "Pawn import")
  importTitle:SetPoint("TOPLEFT", 0, y - 10)
  y = y - 32
  local pawnEntries = pawnAdapter().ListScales()
  if #pawnEntries == 0 then
    local empty = font(left, "GameFontDisableSmall", "No active Pawn scales found.")
    empty:SetPoint("TOPLEFT", 0, y)
  else
    for _, entry in ipairs(pawnEntries) do
      local import = button(left, tostring(entry.name or entry.key), 214, 22)
      import:SetPoint("TOPLEFT", 0, y)
      import:SetScript("OnClick", function()
        local ok, imported = pcall(function()
          return XIVEquip.XIVWeights.Import.Pawn.Import(
              pawnAdapter(), entry.key or entry.name, uniqueScaleID("manual:pawn"), "Imported: " .. tostring(entry.name or entry.key), currentSpecID())
        end)
        if ok and imported then
          Window.SelectedScaleID = imported.id
          print(PREFIX .. "Imported Pawn scale " .. tostring(entry.name or entry.key) .. ".")
          Window.ShowTab(2)
        else
          print(PREFIX .. "Pawn import failed: " .. tostring(imported))
        end
      end)
      y = y - 25
    end
  end
  left:SetHeight(math.max(610, -y + 36))

  local scroll, editor = createScroll(page, 250, -48, 455, 610)
  local selectedScale = selected and C.Repository():Get(selected)
  if selectedScale then
    local bottom = addScaleEditor(editor, selectedScale, 0, 0, 410)
    editor:SetHeight(math.max(610, -bottom + 24))
  else
    local empty = font(editor, "GameFontHighlight", "Create or import a scale to begin.")
    empty:SetPoint("TOPLEFT", 0, 0)
  end
end

local function showCore(content)
  local page = clearContent(content)
  local S = XIVEquip.Settings
  local C = Config()
  local title = font(page, "GameFontNormalLarge", "XIVEquip Core")
  title:SetPoint("TOPLEFT", 0, 0)

  local mode = font(page, "GameFontNormal", "Planner mode: " .. tostring(S:GetPlannerMode()))
  mode:SetPoint("TOPLEFT", 4, -32)

  local legacy = button(page, "Use Legacy", 110, 24)
  legacy:SetPoint("TOPLEFT", 4, -58)
  legacy:SetScript("OnClick", function()
    S:SetPlannerMode("legacy")
    Window.ShowTab(3)
  end)

  local native = button(page, "Use Native", 110, 24)
  native:SetPoint("LEFT", legacy, "RIGHT", 10, 0)
  native:SetScript("OnClick", function()
    S:SetPlannerMode("native")
    Window.ShowTab(3)
  end)

  if not C then return end
  local specID = currentSpecID()
  local selection = specID and C.GetSpecSelection(specID)
  local specName = currentSpecName() or (specID and ("Spec " .. tostring(specID)) or "unknown")
  local specText = "Current specialization: " .. tostring(specName)
  if selection then
    local sourceLabel, scaleLabel = C.SelectionDisplay(specID, selection, pawnAdapter().ListScales())
    specText = specText .. "  |  Source: " .. tostring(sourceLabel) .. "  |  Scale: " .. tostring(scaleLabel)
  end
  local specLine = font(page, "GameFontHighlight", specText)
  specLine:SetPoint("TOPLEFT", 4, -100)
  specLine:SetWidth(660)

  local sourceTitle = font(page, "GameFontNormal", "Native weight source")
  sourceTitle:SetPoint("TOPLEFT", 4, -138)

  local builtin = button(page, "Use Built-in Default", 165, 24)
  builtin:SetPoint("TOPLEFT", 4, -164)
  builtin:SetScript("OnClick", function()
    if specID then C.SetSpecSelection(specID, "default", nil) end
    Window.ShowTab(3)
  end)

  local generated = button(page, "Customize Spec Scale", 170, 24)
  generated:SetPoint("LEFT", builtin, "RIGHT", 10, 0)
  generated:SetScript("OnClick", function()
    if specID then
      C.EnsureSpecScale(specID)
      C.SetSpecSelection(specID, "manual", C.GeneratedScaleID(specID))
    end
    Window.ShowTab(3)
  end)

  local _, manualPane = createScroll(page, 4, -204, 330, 360)
  local y = 0
  local manualTitle = font(manualPane, "GameFontNormalSmall", "Manual scales")
  manualTitle:SetPoint("TOPLEFT", 0, y)
  y = y - 24
  for _, scale in ipairs(listScales()) do
    local use = button(manualPane, "Use", 50, 22)
    use:SetPoint("TOPLEFT", 0, y)
    use:SetScript("OnClick", function()
      if specID then C.SetSpecSelection(specID, "manual", scale.id) end
      Window.ShowTab(3)
    end)
    local label = font(manualPane, "GameFontHighlightSmall", tostring(scale.name or scale.id))
    label:SetPoint("LEFT", use, "RIGHT", 8, 0)
    label:SetWidth(236)
    y = y - 25
  end
  manualPane:SetHeight(math.max(360, -y + 28))

  local _, pawnPane = createScroll(page, 365, -204, 330, 360)
  local pawnY = 0
  local pawnTitle = font(pawnPane, "GameFontNormalSmall", "Pawn scales")
  pawnTitle:SetPoint("TOPLEFT", 0, pawnY)
  pawnY = pawnY - 24
  local pawnEntries = pawnAdapter().ListScales()
  if #pawnEntries == 0 then
    local none = font(pawnPane, "GameFontDisableSmall", "No active Pawn scales found.")
    none:SetPoint("TOPLEFT", 0, pawnY)
  else
    for _, entry in ipairs(pawnEntries) do
      local use = button(pawnPane, "Use", 50, 22)
      use:SetPoint("TOPLEFT", 0, pawnY)
      use:SetScript("OnClick", function()
        if specID then C.SetSpecSelection(specID, "pawn", entry.key or entry.name) end
        Window.ShowTab(3)
      end)
      local label = font(pawnPane, "GameFontHighlightSmall", tostring(entry.name or entry.key))
      label:SetPoint("LEFT", use, "RIGHT", 8, 0)
      label:SetWidth(236)
      pawnY = pawnY - 25
    end
  end
  pawnPane:SetHeight(math.max(360, -pawnY + 28))
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

  local frame = CreateFrame("Frame", WINDOW_NAME, UIParent, "BasicFrameTemplateWithInset")
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
  registerEscapeClose(WINDOW_NAME)
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
