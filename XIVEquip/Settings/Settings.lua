-- Settings/Settings.lua
local addon, XIVEquip = ...
XIVEquip = XIVEquip or {}
local L = (XIVEquip and XIVEquip.L) or {}

-- LSP helper types for this file
---@class SettingsPanel: Frame
---@field name string

-- LSP annotations for UI widgets and helpers
---@type fun(frameType: string, name: string?, parent: table?, template: string?): Frame
-- (don't shadow the global CreateFrame at file scope; use the global at call time)

---@type fun(frame: Frame, w: number)
local UIDropDownMenu_SetWidth = _G.UIDropDownMenu_SetWidth or UIDropDownMenu_SetWidth
---@type fun(frame: Frame, fn: fun(self: Frame, level: number))
local UIDropDownMenu_Initialize = _G.UIDropDownMenu_Initialize or UIDropDownMenu_Initialize
---@type fun(): table
local UIDropDownMenu_CreateInfo = _G.UIDropDownMenu_CreateInfo or UIDropDownMenu_CreateInfo
---@type fun(frame: Frame, text: string)
local UIDropDownMenu_SetText = _G.UIDropDownMenu_SetText or UIDropDownMenu_SetText
---@type fun(info: table, level: number)
local UIDropDownMenu_AddButton = _G.UIDropDownMenu_AddButton or UIDropDownMenu_AddButton

---@class FontString: Frame
---@field SetText fun(self: FontString, text: string)
---@field SetPoint fun(self: FontString, point: string, ...: any)
---@field SetWidth fun(self: FontString, w: number)
---@field SetJustifyH fun(self: FontString, h: string)

---@class CheckButton: Frame
---@field SetChecked fun(self: CheckButton, v: boolean)
---@field GetChecked fun(self: CheckButton): boolean
---@field SetScript fun(self: CheckButton, script: string, fn: fun(self: CheckButton))

-- Return map of comparer internal names -> display labels
-- [XIVEquip-AUTO] comparerNames: Helper for Settings module.
local function comparerNames()
    local list = { ["default"] = L.Settings_Default or "Auto (Pawn → ilvl)" }
    if XIVEquip.Comparers and XIVEquip.Comparers.All then
        for name, cmp in pairs(XIVEquip.Comparers:All()) do
            list[name] = (cmp and cmp.Label) or name
        end
    end
    return list
end

local function getMessage(settingsApi, fallback, key)
    if settingsApi and settingsApi.GetMessage then
        return settingsApi:GetMessage(key)
    end
    return fallback and fallback.Messages and fallback.Messages[key] == true
end

local function getAutomation(settingsApi, fallback, key)
    if settingsApi and settingsApi.GetAutomation then
        return settingsApi:GetAutomation(key)
    end
    return fallback and fallback.Automation and fallback.Automation[key] == true
end

local plannerNames = {
    legacy = "Legacy",
    native = "Native 2.0",
}

local function getPlannerMode(settingsApi, fallback)
    if settingsApi and settingsApi.GetPlannerMode then
        return settingsApi:GetPlannerMode()
    end
    return (fallback and fallback.Planner and fallback.Planner.Mode) or "legacy"
end

-- BuildSettingsPanel: Settings handling: build settings panel.
local function BuildSettingsPanel()
    local s = XIVEquip_Settings
    local settingsApi = XIVEquip.Settings
    if settingsApi and settingsApi.Initialize then settingsApi:Initialize() end
    local panel = CreateFrame("Frame")
    ---@cast panel SettingsPanel
    panel.name = L.Settings_Title or "XIVEquip"

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L.Settings_Title or "XIVEquip")

    -- Description
    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    desc:SetText(L.Settings_Desc or "FFXIV-style Equip Recommended Gear. Prefers Pawn scales; falls back to item level.")

    -- Comparer dropdown
    local dd = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -16, -16)
    UIDropDownMenu_SetWidth(dd, 220)

    local names = comparerNames()
    -- Callback used in Settings.lua to run inline logic.
    UIDropDownMenu_Initialize(dd, function(self, level)
        local info
        for value, label in pairs(names) do
            info = UIDropDownMenu_CreateInfo()
            info.text = label
            -- info.func: Settings handling: func.
            info.func = function()
                if settingsApi and settingsApi.SetComparerName then
                    settingsApi:SetComparerName(value)
                else
                    s.Comparer = s.Comparer or {}
                    s.Comparer.Selected = value
                end
                if XIVEquip.Comparers and XIVEquip.Comparers.Initialize then
                    XIVEquip.Comparers:Initialize()
                end
                UIDropDownMenu_SetText(dd, label)
            end
            local selected = (settingsApi and settingsApi.GetComparerName and settingsApi:GetComparerName())
                or (s.Comparer and s.Comparer.Selected)
                or "default"
            info.checked = (selected == value)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    do
        local cur = (settingsApi and settingsApi.GetComparerName and settingsApi:GetComparerName())
            or (s.Comparer and s.Comparer.Selected)
            or "default"
        UIDropDownMenu_SetText(dd, names[cur] or (L.Settings_Default or "Auto (Pawn → ilvl)"))
    end
    local ddLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ddLabel:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    ddLabel:SetText(L.Settings_ActiveLabel or "Active comparer")

    -- Planner dropdown
    local ddPlanner = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    ddPlanner:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -18)
    UIDropDownMenu_SetWidth(ddPlanner, 160)
    UIDropDownMenu_Initialize(ddPlanner, function(self, level)
        local info
        for _, value in ipairs({ "legacy", "native" }) do
            info = UIDropDownMenu_CreateInfo()
            info.text = plannerNames[value]
            info.func = function()
                if settingsApi and settingsApi.SetPlannerMode then
                    settingsApi:SetPlannerMode(value)
                else
                    s.Planner = s.Planner or {}
                    s.Planner.Mode = value
                end
                UIDropDownMenu_SetText(ddPlanner, plannerNames[value])
            end
            info.checked = (getPlannerMode(settingsApi, s) == value)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(ddPlanner, plannerNames[getPlannerMode(settingsApi, s)] or plannerNames.legacy)

    local plannerLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    plannerLabel:SetPoint("BOTTOMLEFT", ddPlanner, "TOPLEFT", 16, 4)
    plannerLabel:SetText(L.Settings_PlannerMode or "Planner mode")

    -- Messages: login
    local cbLogin = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    ---@cast cbLogin CheckButton
    cbLogin:SetPoint("TOPLEFT", ddPlanner, "BOTTOMLEFT", 18, -16)
    cbLogin.Text:SetText(L.Settings_LoginMsgs or "Show login message")
    cbLogin:SetChecked(getMessage(settingsApi, s, "Login"))
    -- Callback used in Settings.lua to run inline logic.
    cbLogin:SetScript("OnClick", function(self)
        if settingsApi and settingsApi.SetMessage then
            settingsApi:SetMessage("Login", self:GetChecked())
        else
            s.Messages.Login = self:GetChecked()
        end
    end)

    -- Messages: equip
    local cbEquip = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    ---@cast cbEquip CheckButton
    cbEquip:SetPoint("TOPLEFT", cbLogin, "BOTTOMLEFT", 0, -8)
    cbEquip.Text:SetText(L.Settings_EquipMsgs or "Show equip messages")
    cbEquip:SetChecked(getMessage(settingsApi, s, "Equip"))
    -- Callback used in Settings.lua to run inline logic.
    cbEquip:SetScript("OnClick", function(self)
        if settingsApi and settingsApi.SetMessage then
            settingsApi:SetMessage("Equip", self:GetChecked())
        else
            s.Messages.Equip = self:GetChecked()
        end
    end)

    -- Debug checkbox
    local cbDebug = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    ---@cast cbDebug CheckButton
    cbDebug:SetPoint("TOPLEFT", cbEquip, "BOTTOMLEFT", 0, -8)
    cbDebug.Text:SetText(L.Settings_Debug or "Enable debug logging")
    cbDebug:SetChecked(settingsApi and settingsApi.GetDebugEnabled and settingsApi:GetDebugEnabled() or false)
    -- Callback used in Settings.lua to run inline logic.
    cbDebug:SetScript("OnClick", function(self)
        if settingsApi and settingsApi.SetDebugEnabled then
            settingsApi:SetDebugEnabled(self:GetChecked())
        else
            s.Debug = self:GetChecked() and true or false
        end
    end)

    -- Auto-equip on spec change (NEW)
    local cbAuto = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    ---@cast cbAuto CheckButton
    cbAuto:SetPoint("TOPLEFT", cbDebug, "BOTTOMLEFT", 0, -8)
    cbAuto.Text:SetText(L.Settings_AutoSpecEquip or "Auto-equip on spec change")
    cbAuto:SetChecked(getAutomation(settingsApi, s, "SpecEquip"))
    -- Callback used in Settings.lua to run inline logic.
    cbAuto:SetScript("OnClick", function(self)
        if settingsApi and settingsApi.SetAutomation then
            settingsApi:SetAutomation("SpecEquip", self:GetChecked())
        else
            s.Automation = s.Automation or {}
            s.Automation.SpecEquip = self:GetChecked() and true or false
        end
    end)

    -- Auto-save spec equipment set after a verified equip change
    local cbAutoSave = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    ---@cast cbAutoSave CheckButton
    cbAutoSave:SetPoint("TOPLEFT", cbAuto, "BOTTOMLEFT", 0, -8)
    cbAutoSave.Text:SetText(L.Settings_AutoSpecSaveSet or "Auto-save spec equipment set after equip")
    cbAutoSave:SetChecked(getAutomation(settingsApi, s, "SaveSpecSet"))
    cbAutoSave:SetScript("OnClick", function(self)
        if settingsApi and settingsApi.SetAutomation then
            settingsApi:SetAutomation("SaveSpecSet", self:GetChecked())
        else
            s.Automation = s.Automation or {}
            s.Automation.SaveSpecSet = self:GetChecked() and true or false
        end
    end)

    -- Footer / license (anchor fixed; ddBias was undefined)
    local lic = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    lic:SetPoint("TOPLEFT", cbAutoSave, "BOTTOMLEFT", 16, -14)
    lic:SetWidth(520)
    lic:SetJustifyH("LEFT")
    lic:SetText(L.Settings_License or "Inspired by FFXIV. Pawn © their authors.")

    -----------------------------------------------------------------------------
    -- Macro helper (create a /xivequip macro with the addon icon and expose a
    -- draggable button in settings).
    -----------------------------------------------------------------------------

    ---@return integer|nil
    local function FindMacroIdByName(name)
        if not C_Macro or not C_Macro.GetMacroName then return nil end
        -- 120 is the documented max (global+character) macro slots.
        for i = 1, 120 do
            if C_Macro.GetMacroName(i) == name then
                return i
            end
        end
        return nil
    end

    ---@return integer|nil
    local function EnsureXIVEquipMacro()
        if InCombatLockdown() then
            if UIErrorsFrame then UIErrorsFrame:AddMessage("XIVEquip: Can't create macros in combat.") end
            return nil
        end

        local macroName = "XIVEquip"
        local macroText = "/xivequip"
        local iconPath  = "Interface\\AddOns\\XIVEquip\\Assets\\icon_blue_128" -- .tga

        local macroId   = FindMacroIdByName(macroName)
        if macroId then
            s.MacroID = macroId
            return macroId
        end

        if not CreateMacro then
            if UIErrorsFrame then UIErrorsFrame:AddMessage("XIVEquip: CreateMacro API unavailable.") end
            return nil
        end

        -- iconPath is supported by the macro system (same format as #showtooltip).
        macroId = CreateMacro(macroName, iconPath, macroText, nil)
        if macroId then
            s.MacroID = macroId
        end
        return macroId
    end

    -- Create Macro button
    local createMacroBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    createMacroBtn:SetPoint("TOPLEFT", lic, "BOTTOMLEFT", 0, -10)
    createMacroBtn:SetSize(170, 22)
    createMacroBtn:SetText(L.Settings_CreateMacro or "Create /xivequip Macro")

    -- Draggable macro icon button (hidden until we have a macro)
    local macroBtn = CreateFrame("Button", nil, panel)
    macroBtn:SetPoint("LEFT", createMacroBtn, "RIGHT", 10, 0)
    macroBtn:SetSize(32, 32)
    macroBtn:EnableMouse(true)
    macroBtn:RegisterForClicks("LeftButtonUp")
    macroBtn:RegisterForDrag("LeftButton")
    macroBtn:SetMovable(false)
    macroBtn:Hide()

    local macroTex = macroBtn:CreateTexture(nil, "ARTWORK")
    macroTex:SetAllPoints(true)
    macroTex:SetTexture("Interface\\AddOns\\XIVEquip\\Assets\\icon_blue_128.tga")

    local macroBorder = macroBtn:CreateTexture(nil, "BORDER")
    macroBorder:SetAllPoints(true)
    macroBorder:SetAtlas("UI-HUD-ActionBar-IconFrame", true)

    local function RefreshMacroButton()
        local id = s.MacroID or FindMacroIdByName("XIVEquip")
        if id and id ~= 0 then
            s.MacroID = id
            macroBtn:Show()
        else
            macroBtn:Hide()
        end
    end

    local function PickupXIVEquipMacro(owner)
        local id = (s.MacroID and s.MacroID ~= 0) and s.MacroID or FindMacroIdByName("XIVEquip")
        if not id then
            id = EnsureXIVEquipMacro()
        end
        if not id then return end
        if InCombatLockdown() then
            if UIErrorsFrame then UIErrorsFrame:AddMessage("XIVEquip: Can't pick up macros in combat.") end
            return
        end
        if PickupMacro then
            PickupMacro(id)
        end
        if GameTooltip and owner then
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L.Settings_DropMacroTooltip or "Drag this to your action bar.", 1, 1, 1)
            GameTooltip:Show()
        end
    end

    createMacroBtn:SetScript("OnClick", function()
        EnsureXIVEquipMacro()
        RefreshMacroButton()
        -- Match MogMount: immediately put it on the cursor for quick drop.
        PickupXIVEquipMacro(createMacroBtn)
    end)

    macroBtn:SetScript("OnDragStart", function(self)
        PickupXIVEquipMacro(self)
    end)
    macroBtn:SetScript("OnClick", function(self)
        PickupXIVEquipMacro(self)
    end)
    macroBtn:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("XIVEquip", 1, 1, 1)
            GameTooltip:AddLine(L.Settings_DropMacroTooltip or "Drag this to your action bar.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end
    end)
    macroBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- Initialize visibility if the macro already exists.
    RefreshMacroButton()

    return panel
end

-- Register & defaults
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
-- Callback used in Settings.lua to run inline logic.
f:SetScript("OnEvent", function(_, e, name)
    if e == "ADDON_LOADED" and name == addon then
        XIVEquip_Settings  = XIVEquip_Settings or {}
        local s            = XIVEquip_Settings

        if XIVEquip.Settings and XIVEquip.Settings.Initialize then
            XIVEquip.Settings:Initialize()
        end

        if Settings and Settings.RegisterCanvasLayoutCategory then
            local panel = BuildSettingsPanel()
            local category = Settings.RegisterCanvasLayoutCategory(panel, L.Settings_Title or "XIVEquip")
            category.ID = "XIVEquip_Settings"
            Settings.RegisterAddOnCategory(category)
        end
    end
end)
