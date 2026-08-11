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

local tabs = { "Config", "Scales" }

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

local function textColor(fontString, r, g, b)
  if fontString and fontString.SetTextColor then fontString:SetTextColor(r, g, b) end
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
  local page = frame.page
  if not page then
    page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints(frame)
    frame.page = page
  end
  if page.GetChildren then
    local children = { page:GetChildren() }
    for _, child in ipairs(children) do child:Hide() end
  end
  page:Show()
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

local function uiRuntime()
  if XIVEquip.Planning and XIVEquip.Planning.Runtime and XIVEquip.Planning.Runtime.Live then
    return XIVEquip.Planning.Runtime.Live()
  end
  return {
    UnitClass = function(unit) return UnitClass and UnitClass(unit) end,
    UnitName = function(unit) return UnitName and UnitName(unit) end,
    GetRealmName = function() return GetRealmName and GetRealmName() end,
  }
end

local function currentState()
  local C, Profiles = Config(), XIVEquip.Profiles and XIVEquip.Profiles.Config
  local runtime = uiRuntime()
  local context = Profiles and Profiles.CurrentContext and Profiles.CurrentContext(runtime) or {}
  local specID = currentSpecID()
  local classFile = context.classFile or currentClassFile()
  local profile = Profiles and classFile and context.characterKey
      and Profiles.GetForCharacter(context.characterKey, classFile) or nil
  return C, Profiles, runtime, context, specID, classFile, profile
end

local function panel(parent, x, y, width, height)
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  frame:SetSize(width, height)
  frame:SetPoint("TOPLEFT", x, y)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.04, 0.06, 0.08, 0.94)
    frame:SetBackdropBorderColor(0.25, 0.31, 0.36, 0.9)
  end
  return frame
end

local function sectionTitle(parent, text, x, y)
  local title = font(parent, "GameFontNormal", text)
  textColor(title, 1, 0.82, 0.1)
  title:SetPoint("TOPLEFT", x, y)
  return title
end

local function dropdown(parent, width)
  local menu = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(width, menu) end
  return menu
end

local function setDropdown(menu, items, selected, onSelect)
  if not UIDropDownMenu_Initialize then return end
  local selectedLabel
  for _, item in ipairs(items or {}) do
    if item.value == selected then selectedLabel = item.label end
  end
  UIDropDownMenu_Initialize(menu, function()
    for _, item in ipairs(items or {}) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = item.label
      info.value = item.value
      info.checked = item.value == selected
      info.disabled = item.disabled == true
      info.func = function()
        if not item.disabled and onSelect then onSelect(item.value) end
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  UIDropDownMenu_SetSelectedValue(menu, selected)
  UIDropDownMenu_SetText(selectedLabel or "Select", menu)
end

local function specItems()
  local rows = specRows()
  local out = {}
  for _, spec in ipairs(rows) do
    out[#out + 1] = { value = tonumber(spec.id), label = tostring(spec.name or spec.id) }
  end
  return out
end

local function manualScalesForSpec(C, specID)
  local out = {}
  if not (C and specID) then return out end
  for _, scale in ipairs(C.ListManualScales()) do
    if C.GetScaleSpecID(scale) == tonumber(specID) then out[#out + 1] = scale end
  end
  table.sort(out, function(a, b) return tostring(a.name or a.id) < tostring(b.name or b.id) end)
  return out
end

local function uniqueScaleName(C, specID, base)
  local wanted = tostring(base or "Custom Scale")
  local used = {}
  for _, scale in ipairs(manualScalesForSpec(C, specID)) do
    used[string.lower(tostring(scale.name or ""))] = true
  end
  if not used[string.lower(wanted)] then return wanted end
  local suffix = 2
  while used[string.lower(wanted .. " " .. tostring(suffix))] do suffix = suffix + 1 end
  return wanted .. " " .. tostring(suffix)
end

local function integrationItems(C, providerID, runtime, specID)
  local out = { { value = "", label = "Automatic provider scale" } }
  local registry = C and C.ListIntegrations and C.ListIntegrations()
  local entry
  for _, candidate in ipairs(registry or {}) do
    if candidate.id == providerID then entry = candidate break end
  end
  local context = { runtime = runtime, specID = specID }
  local available = entry ~= nil
  if available and entry.IsAvailable then
    local ok, value = pcall(entry.IsAvailable, context)
    available = ok and value == true
  end
  local guessed
  if available and entry and entry.Resolve then
    local ok, resolved = pcall(entry.Resolve, context)
    if ok and resolved then guessed = resolved.name or (resolved.meta and resolved.meta.specName) end
  end
  out[1].label = guessed and ("Automatic: " .. tostring(guessed)) or "Automatic provider scale"
  local rows = entry and entry.ListScales and entry.ListScales(context) or {}
  for _, row in ipairs(rows or {}) do
    out[#out + 1] = { value = row.key or row.name, label = row.name or row.key or "Unnamed scale" }
  end
  return out
end

local function addGeneralSettings(parent, x, y, width)
  local S = XIVEquip.Settings
  local box = panel(parent, x, y, width, 158)
  sectionTitle(box, "General Settings", 14, -14)
  local rows = {
    { "Show login message", function() return S:GetMessage("Login") end, function(v) S:SetMessage("Login", v) end },
    { "Show equip messages", function() return S:GetMessage("Equip") end, function(v) S:SetMessage("Equip", v) end },
    { "Auto-equip on spec change", function() return S:GetAutomation("SpecEquip") end, function(v) S:SetAutomation("SpecEquip", v) end },
    { "Auto-save equipment set after equip", function() return S:GetAutomation("SaveSpecSet") end, function(v) S:SetAutomation("SaveSpecSet", v) end },
    { "Show minimap button", function() return not S:GetMinimapHidden() end, function(v)
      S:SetMinimapHidden(v ~= true)
      if XIVEquip.UI.MinimapButton and XIVEquip.UI.MinimapButton.Refresh then XIVEquip.UI.MinimapButton.Refresh() end
    end },
    { "Debug logging", function() return S:GetDebugEnabled() end, function(v) S:SetDebugEnabled(v) end },
  }
  local left, right = 14, math.floor(width / 2) + 6
  for i, row in ipairs(rows) do
    local column = i <= 3 and left or right
    local rowIndex = i <= 3 and i or i - 3
    local cb = checkbox(box, row[1], row[2](), row[3])
    cb:SetPoint("TOPLEFT", column, -38 - ((rowIndex - 1) * 29))
  end
  local macro = button(box, "Create Macro", 150, 22)
  macro:SetPoint("BOTTOMRIGHT", -12, 12)
  macro:SetScript("OnClick", createEquipMacro)
  return box
end

local function confirmDeleteProfile(profile, usage, onConfirm)
  if not profile then return end
  if not StaticPopupDialogs or not StaticPopup_Show then
    onConfirm()
    return
  end
  local dialogName = "XIVEquip_DELETE_PROFILE"
  StaticPopupDialogs[dialogName] = {
    text = 'Delete profile "%s"?\n\nThis Profile is used by %d characters.\nThose characters will return to the class Default Profile.',
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function() onConfirm() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
  }
  StaticPopup_Show(dialogName, tostring(profile.name or profile.id), tonumber(usage and usage.count) or 0)
end

local function showProfileDialog()
  local C, Profiles, runtime, context, _, classFile, selected = currentState()
  if not Profiles or not classFile then return end
  local frame = Window.ProfileDialog
  if not frame then
    frame = CreateFrame("Frame", "XIVEquipProfileDialog", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(570, 390)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    registerEscapeClose("XIVEquipProfileDialog")
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
    title:SetText("Manage Profiles")
    Window.ProfileDialog = frame
  end
  local profiles = Profiles.List(classFile)
  local profileKeyParts = { tostring(classFile), tostring(Window.SelectedProfileID or (selected and selected.id) or "") }
  for _, item in ipairs(profiles) do profileKeyParts[#profileKeyParts + 1] = tostring(item.id) .. ":" .. tostring(item.name) end
  local profileKey = table.concat(profileKeyParts, "|")
  if frame._viewKey == profileKey then frame:Show(); return end
  frame._viewKey = profileKey
  local body = frame.body
  if not body then
    body = CreateFrame("Frame", nil, frame)
    body:SetAllPoints(frame)
    frame.body = body
  end
  if body.GetChildren then
    local children = { body:GetChildren() }
    for _, child in ipairs(children) do child:Hide() end
  end
  selected = selected or profiles[1]
  local listTitle = sectionTitle(body, "Profiles for " .. tostring(classFile), 18, -42)
  local list = CreateFrame("Frame", nil, body)
  list:SetPoint("TOPLEFT", 16, -66)
  list:SetSize(230, 255)
  for index, profile in ipairs(profiles) do
    local pick = button(list, tostring(profile.name), 215, 24)
    pick:SetPoint("TOPLEFT", 0, -((index - 1) * 29))
    if selected and selected.id == profile.id then pick:Disable() end
    pick:SetScript("OnClick", function() showProfileDialog() end)
    pick:SetScript("OnClick", function()
      Window.SelectedProfileID = profile.id
      showProfileDialog()
    end)
  end
  local detail = panel(body, 260, -36, 290, 285)
  sectionTitle(detail, "Profile Details", 14, -16)
  local selectedProfile
  for _, profile in ipairs(profiles) do if profile.id == Window.SelectedProfileID then selectedProfile = profile end end
  selectedProfile = selectedProfile or selected or profiles[1]
  local name = font(detail, "GameFontHighlight", selectedProfile and selectedProfile.name or "Default")
  name:SetPoint("TOPLEFT", 16, -48)
  local usage = Profiles.Usage(classFile, selectedProfile and selectedProfile.id)
  local used = font(detail, "GameFontHighlightSmall", "Used by " .. tostring(usage and usage.count or 0) .. " characters")
  used:SetPoint("TOPLEFT", 16, -72)
  local use = button(detail, "Use for this character", 160, 22)
  use:SetPoint("TOPLEFT", 16, -102)
  use:SetScript("OnClick", function()
    if selectedProfile and context.characterKey then
      Profiles.AssignCharacter(context.characterKey, classFile, selectedProfile.id)
      frame:Hide()
      Window.ShowTab(1)
    end
  end)
  local nameBox = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
  nameBox:SetSize(190, 22)
  nameBox:SetPoint("TOPLEFT", 16, -148)
  nameBox:SetAutoFocus(false)
  nameBox:SetText("")
  local new = button(detail, "New", 70, 22)
  new:SetPoint("TOPLEFT", 16, -184)
  new:SetScript("OnClick", function()
    local created = Profiles.Create(classFile, nameBox:GetText())
    if created then Window.SelectedProfileID = created.id; showProfileDialog() else print(PREFIX .. "Profile name is required and must be unique.") end
  end)
  local duplicate = button(detail, "Duplicate", 82, 22)
  duplicate:SetPoint("LEFT", new, "RIGHT", 8, 0)
  duplicate:SetScript("OnClick", function()
    if selectedProfile then
      local created = Profiles.Duplicate(classFile, selectedProfile.id, nameBox:GetText())
      if created then Window.SelectedProfileID = created.id; showProfileDialog() else print(PREFIX .. "Profile name is required and must be unique.") end
    end
  end)
  local rename = button(detail, "Rename", 70, 22)
  rename:SetPoint("TOPLEFT", 16, -220)
  rename:SetScript("OnClick", function()
    if selectedProfile and Profiles.Rename(classFile, selectedProfile.id, nameBox:GetText()) then showProfileDialog() end
  end)
  local delete = button(detail, "Delete", 70, 22)
  delete:SetPoint("LEFT", rename, "RIGHT", 8, 0)
  delete:SetScript("OnClick", function()
    if selectedProfile then
      confirmDeleteProfile(selectedProfile, usage, function()
        local ok, reason = Profiles.Delete(classFile, selectedProfile.id)
        if not ok then print(PREFIX .. "Cannot delete profile: " .. tostring(reason)) end
        Window.SelectedProfileID = nil
        showProfileDialog()
      end)
    end
  end)
  local close = button(body, "Close", 80, 22)
  close:SetPoint("BOTTOMRIGHT", -18, 16)
  close:SetScript("OnClick", function() frame:Hide() end)
  frame:Show()
end

local function showConfig(content)
  local C, Profiles, runtime, context, specID, classFile, profile = currentState()
  local resolved = C and specID and C.ResolveResultForSpec and C.ResolveResultForSpec(specID, runtime)
  local manual = profile and profile.manual or {}
  local viewKey = table.concat({
    "config", tostring(classFile), tostring(specID), tostring(profile and profile.id or ""),
    tostring(profile and profile.automatic), tostring(manual.mode),
    tostring(manual.integration and manual.integration.provider),
    tostring(resolved and resolved.fallback), tostring(resolved and resolved.fallbackReason),
  }, "|")
  if content.page and content.page._viewKey == viewKey then content.page:Show(); return end
  local page = clearContent(content)
  page._viewKey = viewKey
  local defaults = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Builtin and XIVEquip.XIVWeights.Builtin.Defaults
  local logo = page:CreateTexture(nil, "ARTWORK")
  logo:SetSize(64, 64)
  logo:SetPoint("TOPLEFT", 4, -2)
  logo:SetTexture("Interface\\AddOns\\XIVEquip\\Assets\\icon_blue_128")
  local version = GetAddOnMetadata and GetAddOnMetadata(addonName, "Version") or "2.0"
  local brand = font(page, "GameFontNormal", "XIVEquip")
  brand:SetPoint("TOPLEFT", 8, -70)
  local versionText = font(page, "GameFontDisableSmall", "v" .. tostring(version or "unknown"))
  versionText:SetPoint("TOPLEFT", 8, -88)

  local className = UnitClass and UnitClass("player") or classFile or "Unknown class"
  local characterName = context and context.characterKey or (UnitName and UnitName("player")) or "Current character"
  local specName = (C and C.SpecName and C.SpecName(specID)) or currentSpecName() or "Unknown specialization"
  local header = font(page, "GameFontNormalLarge", tostring(characterName) .. " | " .. tostring(className) .. " | " .. tostring(specName))
  header:SetPoint("TOPLEFT", 98, -16)
  header:SetWidth(590)
  local fallbackSelection
  if not resolved and C and C.SelectionDisplay then
    fallbackSelection = C.GetSpecSelection and C.GetSpecSelection(specID)
  end
  local resolution = resolved and resolved.scale and resolved.scale.resolution
  local sourceLine = resolution
      and (tostring(resolution.sourceLabel) .. " | " .. tostring(resolution.scaleLabel)
        .. (resolved.fallback and " (Fallback)" or ""))
      or "Default | " .. tostring(specName)
  if fallbackSelection then
    local sourceLabel, scaleLabel = C.SelectionDisplay(specID, fallbackSelection, pawnAdapter().ListScales())
    sourceLine = tostring(sourceLabel) .. " | " .. tostring(scaleLabel)
  end
  local effective = font(page, "GameFontHighlight", sourceLine)
  effective:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
  textColor(effective, 0.4, 1, 0.4)
  if resolved and resolved.fallback then textColor(effective, 1, 0.55, 0.2) end
  if resolved and resolved.fallback then
    local provider = resolved.selection and resolved.selection.provider
    local providerLabel = provider and tostring(provider) or "selected Integration"
    for _, entry in ipairs(C and C.ListIntegrations and C.ListIntegrations() or {}) do
      if entry.id == provider then providerLabel = entry.label or entry.id end
    end
    local reason = resolved.fallbackReason and (" (" .. tostring(resolved.fallbackReason) .. ")") or ""
    local warning = font(page, "GameFontDisableSmall", "Fallback: " .. providerLabel
      .. " has no suitable " .. tostring(specName) .. " scale. Using Default" .. reason .. ".")
    warning:SetPoint("TOPLEFT", effective, "BOTTOMLEFT", 0, -4)
    warning:SetWidth(620)
    textColor(warning, 1, 0.65, 0.25)
  end

  local profilePanel = panel(page, 0, -112, 700, 82)
  sectionTitle(profilePanel, "Profile", 14, -14)
  local profileItems = {}
  for _, item in ipairs(Profiles and classFile and Profiles.List(classFile) or {}) do
    profileItems[#profileItems + 1] = { value = item.id, label = item.name }
  end
  local profileMenu = dropdown(profilePanel, 170)
  profileMenu:SetPoint("TOPLEFT", 74, -25)
  setDropdown(profileMenu, profileItems, profile and profile.id, function(value)
    if context and context.characterKey then Profiles.AssignCharacter(context.characterKey, classFile, value) end
    Window.ShowTab(1)
  end)
  local manage = button(profilePanel, "Manage", 78, 22)
  manage:SetPoint("LEFT", profileMenu, "RIGHT", 4, 0)
  manage:SetScript("OnClick", showProfileDialog)
  local usage = Profiles and profile and Profiles.Usage(classFile, profile.id)
  local used = font(profilePanel, "GameFontDisableSmall", "Used by " .. tostring(usage and usage.count or 0) .. " characters")
  used:SetPoint("LEFT", manage, "RIGHT", 12, 0)
  local auto = checkbox(profilePanel, "Automatic", profile and profile.automatic ~= false, function(value)
    if profile then Profiles.SetAutomatic(profile, value); Window.ShowTab(1) end
  end)
  auto:SetPoint("TOPLEFT", 444, -23)

  local modePanel = panel(page, 0, -202, 700, 188)
  sectionTitle(modePanel, "Scale Selection", 14, -14)
  local mode = profile and profile.manual and string.lower(tostring(profile.manual.mode or "default")) or "default"
  local modes = {
    { id = "default", label = "Default", note = "Use the built-in scale for each specialization." },
    { id = "custom", label = "Custom", note = "Use editable custom scales with per-spec overrides." },
    { id = "integration", label = "Integration", note = "Use an installed provider such as Pawn." },
  }
  for index, item in ipairs(modes) do
    local active = profile and profile.automatic == false and mode == item.id
    local choice = button(modePanel, (active and "[Active] " or "") .. item.label, 126, 24)
    choice:SetPoint("TOPLEFT", 14 + ((index - 1) * 150), -42)
    if profile and profile.automatic ~= false then choice:Disable() end
    choice:SetScript("OnClick", function()
      if profile then Profiles.SetManualMode(profile, item.id); Window.ShowTab(1) end
    end)
    local note = font(modePanel, "GameFontDisableSmall", item.note)
    note:SetPoint("TOPLEFT", choice, "BOTTOMLEFT", 0, -6)
    note:SetWidth(130)
  end
  if profile and profile.automatic ~= false then
    local recommendation = font(modePanel, "GameFontHighlightSmall", "Recommended. XIVEquip chooses the best supported source automatically.")
    recommendation:SetPoint("TOPLEFT", 14, -94)
    textColor(recommendation, 0.4, 1, 0.4)
  end
  local integrationProvider = profile and profile.manual and profile.manual.integration and profile.manual.integration.provider or "pawn"
  if profile and profile.automatic == false and mode == "integration" then
    local providerLabel = font(modePanel, "GameFontHighlightSmall", "Provider")
    providerLabel:SetPoint("TOPLEFT", 14, -112)
    local providerItems = {}
    for _, entry in ipairs(C and C.ListIntegrations and C.ListIntegrations() or {}) do
      local available = true
      if entry.IsAvailable then
        local ok, value = pcall(entry.IsAvailable, { runtime = runtime, specID = specID })
        available = ok and value == true
      end
      providerItems[#providerItems + 1] = {
        value = entry.id,
        label = (entry.label or entry.id) .. (available and "" or " (Unavailable)"),
        disabled = not available,
      }
    end
    local providerMenu = dropdown(modePanel, 150)
    providerMenu:SetPoint("TOPLEFT", 70, -102)
    setDropdown(providerMenu, providerItems, integrationProvider, function(value)
      Profiles.SetIntegrationProvider(profile, value); Window.ShowTab(1)
    end)
  end

  local specs = defaults and defaults.SpecsForClass(classFile) or {}
  local mapPanel = panel(page, 0, -400, 700, 132)
  local mappingTitle = mode == "custom" and "Per-specialization Custom scales"
      or "Per-specialization Integration scales"
  sectionTitle(mapPanel, mappingTitle, 14, -14)
  local mapY = -42
  for _, spec in ipairs(specs) do
    local label = font(mapPanel, "GameFontHighlightSmall", tostring(spec.name))
    label:SetPoint("TOPLEFT", 14, mapY)
    if profile and profile.automatic == false and mode == "custom" then
      local overrides = profile.manual.customOverrides or {}
      local items = { { value = "", label = "Default" } }
      for _, scale in ipairs(manualScalesForSpec(C, spec.id)) do
        items[#items + 1] = { value = scale.id, label = scale.name or scale.id }
      end
      local menu = dropdown(mapPanel, 190)
      menu:SetPoint("TOPLEFT", 128, mapY + 8)
      setDropdown(menu, items, overrides[spec.id] or "", function(value)
        if value == "" then Profiles.ClearCustomOverride(profile, spec.id) else Profiles.SetCustomOverride(profile, spec.id, value) end
        Window.ShowTab(1)
      end)
    elseif profile and profile.automatic == false and mode == "integration" then
      local overrides = profile.manual.integration.overrides or {}
      local items = integrationItems(C, integrationProvider, runtime, spec.id)
      local menu = dropdown(mapPanel, 190)
      menu:SetPoint("TOPLEFT", 128, mapY + 8)
      setDropdown(menu, items, overrides[spec.id] or "", function(value)
        if value == "" then Profiles.ClearIntegrationOverride(profile, spec.id) else Profiles.SetIntegrationOverride(profile, spec.id, value) end
        Window.ShowTab(1)
      end)
    else
      local value = font(mapPanel, "GameFontDisableSmall", "Default")
      value:SetPoint("TOPLEFT", 128, mapY)
    end
    mapY = mapY - 27
  end
  if not profile or profile.automatic ~= false or mode == "default" then mapPanel:Hide() end

  addGeneralSettings(page, 0, -544, 700)
end

local function jsonEscape(value)
  return tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
end

local function encodeJSON(value, depth)
  depth = depth or 0
  if type(value) == "string" then return '"' .. jsonEscape(value) .. '"' end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  if type(value) ~= "table" then return "null" end
  local keys, array = {}, true
  local count = 0
  for key in pairs(value) do keys[#keys + 1] = key; count = count + 1; if type(key) ~= "number" then array = false end end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  if array then
    for i = 1, #value do out[#out + 1] = encodeJSON(value[i], depth + 1) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  for _, key in ipairs(keys) do out[#out + 1] = encodeJSON(tostring(key)) .. ":" .. encodeJSON(value[key], depth + 1) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function showTextDialog(titleText, bodyText)
  local frame = Window.TextDialog
  if not frame then
    frame = CreateFrame("Frame", "XIVEquipTextDialog", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(620, 470)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    registerEscapeClose("XIVEquipTextDialog")
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
    frame.title = title
    local note = font(frame, "GameFontHighlightSmall", "Select the text and press Ctrl+C. WoW cannot write arbitrary text to the system clipboard directly.")
    note:SetPoint("TOPLEFT", 18, -42)
    note:SetWidth(580)
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -76)
    scroll:SetSize(570, 330)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(548)
    edit:SetHeight(320)
    edit:SetTextInsets(6, 6, 6, 6)
    scroll:SetScrollChild(edit)
    frame.edit = edit
    local close = button(frame, "Close", 80, 22)
    close:SetPoint("BOTTOMRIGHT", -18, 16)
    close:SetScript("OnClick", function() frame:Hide() end)
    Window.TextDialog = frame
  end
  frame.title:SetText(titleText)
  frame.edit:SetText(bodyText or "")
  frame.edit:HighlightText()
  frame:Show()
end

local function showImportDialog(specID, C)
  local frame = Window.ImportDialog
  if not frame then
    frame = CreateFrame("Frame", "XIVEquipImportDialog", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(620, 500)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    registerEscapeClose("XIVEquipImportDialog")
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
    title:SetText("Import Scale")
    local note = font(frame, "GameFontHighlightSmall", "Paste Pawn, Raidbots, SimC, AMR, Wowhead, or XIVEquip JSON, then detect and import it as a Custom scale.")
    note:SetPoint("TOPLEFT", 18, -42)
    note:SetWidth(580)
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -78)
    scroll:SetSize(570, 260)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(548)
    edit:SetHeight(250)
    edit:SetTextInsets(6, 6, 6, 6)
    scroll:SetScrollChild(edit)
    frame.edit = edit
    local nameLabel = font(frame, "GameFontHighlightSmall", "Name")
    nameLabel:SetPoint("TOPLEFT", 18, -350)
    local nameEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    nameEdit:SetSize(300, 22)
    nameEdit:SetPoint("TOPLEFT", 70, -346)
    nameEdit:SetAutoFocus(false)
    frame.nameEdit = nameEdit
    local detected = font(frame, "GameFontHighlightSmall", "Format: paste data and press Detect.")
    detected:SetPoint("TOPLEFT", 18, -382)
    detected:SetWidth(570)
    frame.detected = detected
    local detect = button(frame, "Detect", 76, 22)
    detect:SetPoint("BOTTOMLEFT", 18, 16)
    detect:SetScript("OnClick", function()
      local importer = XIVEquip.XIVWeights.Import and XIVEquip.XIVWeights.Import.Serialized
      local format, reason = importer and importer.Detect(frame.edit:GetText())
      if format then
        frame.detected:SetText("Detected format: " .. tostring(format) .. ". Press Import to create a Custom scale.")
        textColor(frame.detected, 0.4, 1, 0.4)
      else
        frame.detected:SetText("Unable to detect pasted data: " .. tostring(reason or "unknown format"))
        textColor(frame.detected, 1, 0.55, 0.2)
      end
    end)
    frame.detect = detect
    local import = button(frame, "Import", 76, 22)
    import:SetPoint("LEFT", detect, "RIGHT", 8, 0)
    import:SetScript("OnClick", function()
      local importer = XIVEquip.XIVWeights.Import and XIVEquip.XIVWeights.Import.Serialized
      local parsed, reason = importer and importer.Parse(frame.edit:GetText(), frame.specID)
      if not parsed then
        frame.detected:SetText("Import failed: " .. tostring(reason or "invalid scale data"))
        textColor(frame.detected, 1, 0.55, 0.2)
        return
      end
      if parsed.specID and tonumber(parsed.specID) ~= tonumber(frame.specID) then
        frame.detected:SetText("Import is for " .. tostring(C.SpecName(parsed.specID) or parsed.specID)
          .. ". Select that specialization before importing.")
        textColor(frame.detected, 1, 0.55, 0.2)
        return
      end
      local baseName = frame.nameEdit:GetText()
      if tostring(baseName or ""):match("^%s*$") then baseName = parsed.name or ("Imported " .. tostring(parsed.format)) end
      local name = uniqueScaleName(C, frame.specID, baseName)
      local imported, importReason = C.CreateManualScale(uniqueScaleID("manual:import"), name, parsed.weights, frame.specID)
      if not imported then
        frame.detected:SetText("Import failed: " .. tostring(importReason or "could not create scale"))
        textColor(frame.detected, 1, 0.55, 0.2)
        return
      end
      imported.meta = imported.meta or {}
      imported.meta.importedFrom = parsed.format
      imported.source = { kind = "manual", importedFrom = parsed.format, specID = frame.specID }
      C.SaveScale(imported)
      Window.SelectedSpecID = frame.specID
      Window.SelectedScaleID = imported.id
      frame:Hide()
      Window.ShowTab(2)
    end)
    frame.import = import
    local close = button(frame, "Cancel", 80, 22)
    close:SetPoint("LEFT", import, "RIGHT", 8, 0)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.close = close
    registerEscapeClose("XIVEquipImportDialog")
    Window.ImportDialog = frame
  end
  frame.specID = tonumber(specID)
  frame.edit:SetText("")
  frame.nameEdit:SetText("")
  frame.detected:SetText("Format: paste data and press Detect.")
  textColor(frame.detected, 0.9, 0.9, 0.9)
  frame:Show()
end

local function confirmDeleteScale(scale, onConfirm)
  if not scale then return end
  if not StaticPopupDialogs or not StaticPopup_Show then
    onConfirm()
    return
  end
  local dialogName = "XIVEquip_DELETE_SCALE"
  StaticPopupDialogs[dialogName] = {
    text = "Delete scale %s?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function() onConfirm() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
  }
  StaticPopup_Show(dialogName, tostring(scale.name or scale.id))
end

local function showScales(content)
  local C = Config()
  local specs = specItems()
  local defaultSpec = currentSpecID() or (specs[1] and specs[1].value)
  Window.SelectedSpecID = Window.SelectedSpecID or defaultSpec
  local specID = Window.SelectedSpecID
  local scales = manualScalesForSpec(C, specID)
  local selected = Window.SelectedScaleID
  local selectedScale = selected and C.Repository():Get(selected)
  if not selectedScale or C.GetScaleSpecID(selectedScale) ~= tonumber(specID) then selectedScale = scales[1]; selected = selectedScale and selectedScale.id end
  Window.SelectedScaleID = selected
  local viewKey = table.concat({ "scales", tostring(specID), tostring(selected or "") }, "|")
  if content.page and content.page._viewKey == viewKey then content.page:Show(); return end
  local page = clearContent(content)
  page._viewKey = viewKey

  local title = font(page, "GameFontNormalLarge", "Scales")
  title:SetPoint("TOPLEFT", 0, 0)
  local note = font(page, "GameFontHighlightSmall", "Custom scales are editable copies tied to one specialization. Defaults remain immutable.")
  note:SetPoint("TOPLEFT", 0, -28)
  note:SetWidth(680)
  local specMenu = dropdown(page, 150)
  specMenu:SetPoint("TOPLEFT", 0, -54)
  setDropdown(specMenu, specs, specID, function(value)
    Window.SelectedSpecID = tonumber(value); Window.SelectedScaleID = nil; Window.ShowTab(2)
  end)
  local scaleItems = {}
  for _, scale in ipairs(scales) do scaleItems[#scaleItems + 1] = { value = scale.id, label = scale.name or scale.id } end
  local scaleMenu = dropdown(page, 210)
  scaleMenu:SetPoint("LEFT", specMenu, "RIGHT", 6, 0)
  setDropdown(scaleMenu, scaleItems, selected, function(value) Window.SelectedScaleID = value; Window.ShowTab(2) end)
  local new = button(page, "New", 58, 22)
  new:SetPoint("LEFT", scaleMenu, "RIGHT", 8, 0)
  new:SetScript("OnClick", function()
    local scale = C.CreateManualScale(uniqueScaleID("manual"), uniqueScaleName(C, specID, tostring(C.SpecName(specID) or "Custom Scale")), nil, specID)
    if scale then Window.SelectedScaleID = scale.id; Window.ShowTab(2) end
  end)
  local import = button(page, "Import", 64, 22)
  import:SetPoint("LEFT", new, "RIGHT", 4, 0)
  import:SetScript("OnClick", function() showImportDialog(specID, C) end)
  local export = button(page, "Export", 64, 22)
  export:SetPoint("LEFT", import, "RIGHT", 4, 0)
  export:SetScript("OnClick", function()
    if not selectedScale then return end
    local meta = selectedScale.meta or {}
    showTextDialog("Export Scale", encodeJSON({
      format = "xivequip-scale", version = 1, id = selectedScale.id,
      name = selectedScale.name, specID = meta.specID, classFile = meta.classFile,
      specName = meta.specName, weights = selectedScale.weights,
    }))
  end)
  local duplicate = button(page, "Duplicate", 78, 22)
  duplicate:SetPoint("LEFT", export, "RIGHT", 4, 0)
  duplicate:SetScript("OnClick", function()
    if selectedScale then
      local copyScale = C.DuplicateScale(selectedScale.id, uniqueScaleID("manual"), uniqueScaleName(C, specID, tostring(selectedScale.name or "Scale") .. " Copy"))
      if copyScale then Window.SelectedScaleID = copyScale.id; Window.ShowTab(2) end
    end
  end)
  local delete = button(page, "Delete", 62, 22)
  delete:SetPoint("LEFT", duplicate, "RIGHT", 4, 0)
  delete:SetScript("OnClick", function()
    if not selectedScale then return end
    confirmDeleteScale(selectedScale, function()
      local ok = C.DeleteScale(selectedScale.id)
      if ok then Window.SelectedScaleID = nil; Window.ShowTab(2) else print(PREFIX .. "Unable to delete scale.") end
    end)
  end)

  local _, editor = createScroll(page, 0, -92, 700, 548)
  if not selectedScale then
    local empty = font(editor, "GameFontHighlight", "No Custom scale exists for this specialization yet. Use New to start from the Default weights.")
    empty:SetPoint("TOPLEFT", 12, -12)
    editor:SetHeight(548)
    return
  end
  local info = panel(editor, 0, 0, 210, 170)
  sectionTitle(info, "Scale Info", 14, -14)
  local specLine = font(info, "GameFontHighlightSmall", "Specialization: " .. tostring(C.SpecName(specID) or specID))
  specLine:SetPoint("TOPLEFT", 14, -46)
  local based = font(info, "GameFontHighlightSmall", "Based on: Default")
  based:SetPoint("TOPLEFT", 14, -70)
  local status = font(info, "GameFontHighlightSmall", "Autosaved ✓")
  status:SetPoint("TOPLEFT", 14, -102)
  textColor(status, 0.4, 1, 0.4)
  local errorLine = font(info, "GameFontDisableSmall", "")
  errorLine:SetPoint("TOPLEFT", 14, -126)
  errorLine:SetWidth(180)
  local work = {}
  for key, value in pairs(selectedScale.weights or {}) do work[key] = tonumber(value) or 0 end
  local nameLabel = font(editor, "GameFontNormal", "Name")
  nameLabel:SetPoint("TOPLEFT", 232, -10)
  local nameEdit = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
  nameEdit:SetSize(260, 22)
  nameEdit:SetPoint("TOPLEFT", 280, -6)
  nameEdit:SetAutoFocus(false)
  nameEdit:SetText(selectedScale.name or "Custom Scale")
  local function commitName()
    local value = tostring(nameEdit:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local duplicateName = false
    for _, other in ipairs(scales) do
      if other.id ~= selectedScale.id and string.lower(tostring(other.name or "")) == string.lower(value) then duplicateName = true end
    end
    if value == "" or duplicateName then
      errorLine:SetText(value == "" and "Name is required." or "Name already exists for this spec.")
      nameEdit:SetText(selectedScale.name or "Custom Scale")
      return
    end
    selectedScale.name = value
    C.SaveScale(selectedScale)
    errorLine:SetText("")
    status:SetText("Autosaved ✓")
  end
  nameEdit:SetScript("OnEnterPressed", function(self) commitName(); self:ClearFocus() end)
  nameEdit:SetScript("OnEditFocusLost", commitName)

  local y = -48
  local function addWeightRow(feature, label)
    local rowLabel = font(editor, "GameFontHighlightSmall", label)
    rowLabel:SetPoint("TOPLEFT", 232, y)
    local edit = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    edit:SetSize(54, 20)
    edit:SetPoint("TOPLEFT", 352, y + 2)
    edit:SetAutoFocus(false)
    edit:SetText(string.format("%.2f", tonumber(work[feature]) or 0))
    local slider = CreateFrame("Slider", nil, editor, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 418, y + 1)
    slider:SetWidth(190)
    slider:SetMinMaxValues(0, 1)
    slider:SetValueStep(0.1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    for index = 0, 10 do
      local tick = font(editor, "GameFontDisableSmall", "|")
      tick:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", (index * 19) - 1, 4)
    end
    local suppress = true
    local initial = tonumber(work[feature]) or 0
    slider:SetValue(initial)
    suppress = false
    local function restore(value)
      value = tonumber(value) or 0
      work[feature] = value
      selectedScale.weights[feature] = value
      edit:SetText(string.format("%.2f", value))
      suppress = true
      slider:SetValue(value)
      suppress = false
    end
    local function commit(value, source)
      value = tonumber(value)
      if not value or value < 0 or value > 1 then
        errorLine:SetText("Weights must be between 0 and 1.")
        restore(work[feature])
        return
      end
      local prior = work[feature]
      work[feature] = value
      selectedScale.weights[feature] = value
      local valid, message = C.ValidateAuthoredWeights(selectedScale)
      if not valid then
        restore(prior)
        errorLine:SetText(message)
        return
      end
      C.SaveScale(selectedScale)
      errorLine:SetText("")
      status:SetText("Autosaved ✓")
      if source ~= "slider" then
        suppress = true; slider:SetValue(value); suppress = false
      end
    end
    slider:SetScript("OnValueChanged", function(_, value)
      if suppress then return end
      local rounded = math.floor((tonumber(value) or 0) * 10 + 0.5) / 10
      edit:SetText(string.format("%.2f", rounded))
      commit(rounded, "slider")
    end)
    edit:SetScript("OnEnterPressed", function(self) commit(self:GetText(), "edit"); self:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", function(self) commit(self:GetText(), "edit") end)
    y = y - 30
  end
  for _, group in ipairs(featureGroups) do
    local groupLabel = font(editor, "GameFontNormalSmall", group[1])
    groupLabel:SetPoint("TOPLEFT", 232, y)
    textColor(groupLabel, 1, 0.82, 0.1)
    y = y - 22
    for _, feature in ipairs(group[2]) do addWeightRow(feature, featureLabels[feature] or feature) end
    y = y - 6
  end
  editor:SetHeight(math.max(548, -y + 24))
end

local renderers = { showConfig, showScales }

function Window.ShowTab(index)
  local frame = Window.Frame
  if not frame then return end
  if not renderers[index] then index = 1 end
  frame.selectedTab = index
  for i, tab in ipairs(frame.tabs or {}) do
    if i == index then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
  end
  renderers[index](frame.content)
end

function Window.Create()
  if Window.Frame then return Window.Frame end

  local frame = CreateFrame("Frame", WINDOW_NAME, UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(760, 820)
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
      tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
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
