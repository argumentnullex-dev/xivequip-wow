-- UI.lua
local addonName, XIVEquip      = ...

-- Declare the WoW globals used in this file for the language server.
-- These annotations don't evaluate anything at runtime; they only help the LSP.
---@type GameTooltipFrame
---@type PaperDollFrameClass
---@type CharacterFrameClass
---@type Frame
---@type Frame
---@type table
---@type table
---@type fun(...): boolean
---@type fun(...)
---@type fun(...)
---@type GameTooltipFrame
local GameTooltip              = _G.GameTooltip or GameTooltip
---@type PaperDollFrameClass
local PaperDollFrame           = _G.PaperDollFrame or PaperDollFrame or
    _G.CharacterFrame and _G.CharacterFrame.PaperDollFrame
---@type CharacterFrameClass
local CharacterFrame           = _G.CharacterFrame or CharacterFrame
---@type Frame
local UIParent                 = _G.UIParent or UIParent
---@type Frame
local CharacterFramePortrait   = _G.CharacterFramePortrait or CharacterFramePortrait
---@type table
local C_Item                   = _G.C_Item or C_Item
---@type table
local C_Timer                  = _G.C_Timer or C_Timer
---@type fun(...): boolean
local InCombatLockdown         = _G.InCombatLockdown or InCombatLockdown
---@type fun(...)
local GetItemStats             = _G.GetItemStats or GetItemStats
---@type fun(...)
local GetDetailedItemLevelInfo = _G.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo

XIVEquip                       = XIVEquip or {}
XIVEquip.UI                    = XIVEquip.UI or {}
local L                        = XIVEquip.L or {}

-- Fallback strings
L.ButtonTooltip                = L.ButtonTooltip or "Equip Recommended Gear"

-- Button textures
local TEX_ENABLED              = "Interface\\AddOns\\XIVEquip\\Assets\\icon_blue_128.tga"
local TEX_DISABLED             = "Interface\\AddOns\\XIVEquip\\Assets\\icon_white_128.tga"

---@type Frame
local btn

-- Map Blizzard stat tokens -> Pawn keys and pretty text
local STAT_TO_PAWN             = {
  ITEM_MOD_CRIT_RATING_SHORT      = { key = "CritRating", label = "Crit" },
  ITEM_MOD_HASTE_RATING_SHORT     = { key = "HasteRating", label = "Haste" },
  ITEM_MOD_MASTERY_RATING_SHORT   = { key = "MasteryRating", label = "Mastery" },
  ITEM_MOD_VERSATILITY            = { key = "Versatility", label = "Vers" },
  ITEM_MOD_LIFESTEAL_SHORT        = { key = "Leech", label = "Leech" },
  ITEM_MOD_AVOIDANCE_RATING_SHORT = { key = "Avoidance", label = "Avoid" },
  ITEM_MOD_SPEED_RATING_SHORT     = { key = "MovementSpeed", label = "Speed" },
}

-- GetBoEText: Gets a "BoE" string for item links if necessary.
local function GetBoEText(itemLink, itemLoc)
  if type(itemLink) ~= "string" or itemLink == "" then return "" end
  local bindType = select(14, GetItemInfo(itemLink))
  if bindType == 2 then -- LE_ITEM_BIND_ON_EQUIP
    -- Only show [BoE] if the specific item is not yet bound.
    local bound = false
    if itemLoc and C_Item and type(C_Item.IsBound) == "function" then
      local ok, v = pcall(C_Item.IsBound, itemLoc)
      bound = ok and v or false
    end
    if not bound then
      return " |cffff8800[BoE]|r"
    end
  end
  return ""
end

local GetItemStatsCompat =
    (type(GetItemStats) == "function" and GetItemStats) or
    (C_Item and C_Item.GetItemStats) or
    -- [XIVEquip-AUTO] No-op placeholder callback used as a safe default.
    function() return nil end

-- computeStatDiff: UI wiring: compute stat diff.
local function computeStatDiff(oldLink, newLink)
  local get = GetItemStatsCompat
  local diff = {}
  if not get then return diff end
  local a = get(oldLink) or {}
  local b = get(newLink) or {}
  -- union of keys
  local seen = {}
  for k in pairs(a) do seen[k] = true end
  for k in pairs(b) do seen[k] = true end

  for k in pairs(seen) do
    local delta = (b[k] or 0) - (a[k] or 0)
    if delta ~= 0 then
      diff[k] = delta
    end
  end
  return diff
end

-- Optional: turn raw deltas into *weighted* deltas using a values table
local function weightDeltas(rawDiff, values)
  if type(values) ~= "table" then return nil end
  local weighted, total = {}, 0
  for blizzKey, amt in pairs(rawDiff or {}) do
    local map = STAT_TO_PAWN[blizzKey]
    if map then
      local w = values[map.key]
      if w then
        local contrib = amt * w
        weighted[map.key] = (weighted[map.key] or 0) + contrib
        total = total + contrib
      end
    end
  end
  return weighted, total
end

-- Retail item level (works on links)
-- [XIVEquip-AUTO] GetIlvl: Returns ilvl.
local function GetIlvl(link)
  if type(GetDetailedItemLevelInfo) == "function" then
    local ok, v = pcall(GetDetailedItemLevelInfo, link)
    if ok then return v end
  end
  local _, _, _, ilvl = GetItemInfo(link)
  return ilvl
end

-- If PlanBest didn't populate deltas, compute them now
-- [XIVEquip-AUTO] ensureDeltas: Helper for UI module.
local function ensureDeltas(c)
  -- score delta (Pawn helpers from Pawn.lua)
  if c.deltaScore == nil then
    local newV
    local oldV
    if XIVEquip.Pawn and type(XIVEquip.Pawn.ScoreItemLink) == "function" then
      newV = select(1, XIVEquip.Pawn.ScoreItemLink(c.newLink))
      oldV = select(1, XIVEquip.Pawn.ScoreItemLink(c.oldLink))
    else
      newV = XIVEquip.PawnScoreLinkAuto and select(1, XIVEquip.PawnScoreLinkAuto(c.newLink))
      oldV = XIVEquip.PawnScoreLinkAuto and select(1, XIVEquip.PawnScoreLinkAuto(c.oldLink))
    end
    if oldV == nil then oldV = 0 end
    if type(newV) == "number" and type(oldV) == "number" then
      c.deltaScore = newV - oldV
    end
  end
  -- ilvl delta
  if c.deltaIlvl == nil then
    local newI = GetIlvl(c.newLink)
    local oldI = GetIlvl(c.oldLink)
    if oldI == nil then oldI = 0 end
    if type(newI) == "number" and type(oldI) == "number" then
      c.deltaIlvl = (newI - oldI)
    end
  end
end

-- only silence the LOGIN banner during preview; never touch Equip prints
-- [XIVEquip-AUTO] withLoginSilenced: Helper for UI module.
local function withLoginSilenced(fn)
  local S = XIVEquip.Settings
  local prev = S and S.GetMessage and S:GetMessage("Login")
  if S and S.SetMessage then S:SetMessage("Login", false) end
  local ok, err = xpcall(fn, geterrorhandler())
  if S and S.SetMessage then S:SetMessage("Login", prev == true) end
  return ok, err
end

local function nativeScaleHeader(result)
  local config = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config
  local scale = result and result.weights
  if config and config.ResolvedScaleDisplayLabel and scale then
    return config.ResolvedScaleDisplayLabel(scale)
  end
  local specIndex = GetSpecialization and GetSpecialization()
  local specID = specIndex and GetSpecializationInfo and select(1, GetSpecializationInfo(specIndex))
  local runtime = XIVEquip.Planning and XIVEquip.Planning.Runtime and XIVEquip.Planning.Runtime.Live
      and XIVEquip.Planning.Runtime.Live() or nil
  local resolved = config and specID and config.ResolveResultForSpec(specID, runtime)
  if runtime and runtime.Close then runtime.Close() end
  return config and config.ResolvedScaleDisplayLabel and config.ResolvedScaleDisplayLabel(resolved and resolved.scale)
      or "Default | current specialization"
end

local PREVIEW_CACHE_SECONDS = 30
local PREVIEW_PENDING_CACHE_SECONDS = 1
local previewCache = { expires = 0 }

local function nowSeconds()
  if type(GetTime) == "function" then return GetTime() end
  if type(time) == "function" then return time() end
  return 0
end

local function previewEnabled()
  local settings = XIVEquip.Settings
  if settings and type(settings.GetMessage) == "function" then
    return settings:GetMessage("Preview") ~= false
  end
  return true
end

local function computePreview()
  local changes, pending, weaponPlan, tooltipHeader

  withLoginSilenced(function()
    local result, planFailure
    if XIVEquip.Gear and XIVEquip.Gear.PlanBest then
      changes, pending, _, result, planFailure = XIVEquip.Gear:PlanBest()
    else
      changes, pending = {}, false
    end
    if planFailure then
      tooltipHeader = "Planner failed"
      changes, pending = {}, false
    else
      tooltipHeader = nativeScaleHeader(result)
    end
  end)

  return {
    changes = changes,
    pending = pending,
    weaponPlan = weaponPlan,
    tooltipHeader = tooltipHeader,
  }
end

local function renderPreview(owner, anchor, payload)
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine(L.ButtonTooltip, 0.2, 0.8, 1.0)

  if InCombatLockdown() then
    GameTooltip:AddLine("|cffaaaaaa(Disabled in combat)|r")
    GameTooltip:Show()
    return false
  end

  if not previewEnabled() then
    GameTooltip:Show()
    return false
  end

  local changes = payload and payload.changes
  local pending = payload and payload.pending
  local weaponPlan = payload and payload.weaponPlan
  local tooltipHeader = payload and payload.tooltipHeader

  if tooltipHeader and tooltipHeader ~= "" then
    GameTooltip:AddLine("|cffffd200" .. tooltipHeader .. "|r")
  end

  if not payload then
    GameTooltip:AddLine("|cffaaaaaaCalculating recommendations...|r")
    GameTooltip:Show()
    return true
  end

  if pending then
    GameTooltip:AddLine("|cffFFD100Loading item data…|r")
  end

  if (not changes or #changes == 0) and not weaponPlan then
    GameTooltip:AddLine("|cffaaaaaaNo upgrades.|r")
  else
    for _, c in ipairs(changes or {}) do
      GameTooltip:AddLine(string.format("|cffdddddd%s|r", c.slotName or " "))

      ensureDeltas(c)

      local dIlvl   = c.deltaIlvl or 0
      local raw     = computeStatDiff(c.oldLink, c.newLink) or {}
      local values  = c.scaleValues
      local _, wsum = weightDeltas(raw, values)
      local link    = c.newLink or ""
      GameTooltip:AddLine(string.format(
        "  %s%s  |cff7fff7f%+.1f score|r  |cff7fbfff%+d ilvl|r",
        link, GetBoEText(link, c.newLoc), c.deltaScore or 0, dIlvl))

      local rows = {}
      for blizzKey, delta in pairs(raw) do
        local map = STAT_TO_PAWN[blizzKey]
        if map and delta ~= 0 then rows[#rows + 1] = { label = map.label, d = delta } end
      end
      table.sort(rows, function(a, b) return math.abs(a.d) > math.abs(b.d) end)

      for i, row in ipairs(rows) do
        if i > 8 then
          GameTooltip:AddLine("     |cffaaaaaa(…more)|r"); break
        end
        local color = row.d > 0 and "|cff7fff7f" or "|cffff3a3a"
        GameTooltip:AddLine(string.format("     %s%+d %s|r", color, row.d, row.label))
      end

      if wsum and wsum ~= 0 then
        local color = wsum > 0 and "|cff7fff7f" or "|cffff3a3a"
        GameTooltip:AddLine(string.format("     %s%+.1f weighted|r", color, wsum))
      end
    end

    if weaponPlan then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("|cffddddddWeapons|r")
      GameTooltip:AddLine("  " .. weaponPlan.newText)
    end
  end

  local potentials = (XIVEquip.Gear and XIVEquip.Gear.GetSocketPotential and XIVEquip.Gear:GetSocketPotential()) or {}
  if type(potentials) == "table" and #potentials > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffddddddPotential socket upgrades|r")
    for _, r in ipairs(potentials) do
      local assumed = string.format("+%d %s", tonumber(r.assumedAmount) or 10,
        tostring(r.assumedStat or "best secondary"))
      local delta = tonumber(r.potentialDeltaScore) or 0
      GameTooltip:AddLine(string.format("  %s |cffaaaaaa(%s, potential %+0.1f score)|r", tostring(r.link or ""),
        assumed, delta))
    end
  end

  local boes = (XIVEquip.Gear and XIVEquip.Gear.GetBoEReminders and XIVEquip.Gear:GetBoEReminders()) or {}
  if type(boes) == "table" and #boes > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffddddddBind-on-Equip reminders|r")
    for _, r in ipairs(boes) do
      GameTooltip:AddLine(string.format("  %s |cffffaa66([BoE] equip the piece manually)|r", tostring(r.link or "")))
    end
  end

  GameTooltip:Show()
  return false
end

local function showEquipPreviewTooltip(owner, anchor)
  -- Preview must never enter the planner while protected actions are
  -- locked or when the user has disabled preview messages.
  if InCombatLockdown() or not previewEnabled() then
    renderPreview(owner, anchor, nil)
    return
  end

  local now = nowSeconds()
  if previewCache.payload and (previewCache.expires or 0) > now then
    renderPreview(owner, anchor, previewCache.payload)
    return
  end

  local payload = computePreview()
  previewCache.payload = payload
  -- Pending item data should be visible immediately, but it gets a much
  -- shorter lifetime so the next hover can retry once the client resolves
  -- the missing item information. No background planner pass is required.
  previewCache.expires = nowSeconds()
      + (payload.pending and PREVIEW_PENDING_CACHE_SECONDS or PREVIEW_CACHE_SECONDS)
  renderPreview(owner, anchor, payload)
end

function XIVEquip.UI.ClearPreviewCache()
  previewCache.payload = nil
  previewCache.expires = 0
end

XIVEquip.UI.RenderEquipPreviewTooltip = showEquipPreviewTooltip

-- Use saved button position if present, otherwise sensible defaults near the portrait
-- [XIVEquip-AUTO] anchorButton: Helper for UI module.
local function anchorButton()
  if not btn then return end
  btn:ClearAllPoints()

  local S = _G.XIVEquip_Settings
  local pos = S and S.ButtonPos
  if pos and pos.point and pos.rel and pos.relPoint then
    local rel = _G[tostring(pos.rel)] or PaperDollFrame or CharacterFrame or UIParent
    btn:SetPoint(pos.point, rel, pos.relPoint, tonumber(pos.x) or 0, tonumber(pos.y) or 0)
  else
    local portrait = _G.CharacterFramePortrait
    if portrait then
      btn:SetPoint("LEFT", portrait, "RIGHT", 305, -22.5)
    elseif CharacterFrame then
      btn:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 300, -38)
    else
      btn:SetPoint("CENTER", UIParent, "CENTER", -180, -120)
    end
  end

  btn:Show()
end

-- saveButtonPosition: UI wiring: save button position.
local function saveButtonPosition()
  if not btn then return end
  local point, rel, relPoint, x, y = btn:GetPoint(1)
  _G.XIVEquip_Settings = _G.XIVEquip_Settings or {}
  _G.XIVEquip_Settings.ButtonPos = {
    point = point,
    rel = rel and rel:GetName() or "PaperDollFrame",
    relPoint = relPoint,
    x = x,
    y = y
  }
end

-- createButton: UI wiring: create button.
local function createButton()
  if btn then return end
  local parent = PaperDollFrame or CharacterFrame or UIParent

  btn = CreateFrame("Button", "XIVEquipButton", parent, "BackdropTemplate")
  btn:SetSize(26, 26)
  btn:SetFrameStrata("DIALOG")
  if parent.GetFrameLevel then btn:SetFrameLevel(parent:GetFrameLevel() + 20) end
  btn:SetClampedToScreen(true)
  btn:SetMovable(true)
  btn:RegisterForDrag("LeftButton")
  -- Callback used in UI.lua to run inline logic.
  btn:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
  -- Callback used in UI.lua to run inline logic.
  btn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing(); saveButtonPosition(); anchorButton()
  end)

  btn:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  btn:SetBackdropColor(0.15, 0.15, 0.15, 0.85)
  btn:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)

  btn:SetNormalTexture(TEX_ENABLED)
  btn:SetPushedTexture(TEX_ENABLED)
  btn:SetDisabledTexture(TEX_DISABLED)
  local hi = btn:CreateTexture(nil, "HIGHLIGHT")
  hi:SetAllPoints(true)
  hi:SetTexture("Interface\\Buttons\\WHITE8x8")
  hi:SetVertexColor(1, 1, 1, 0.12)
  btn:SetHighlightTexture(hi)

  -- helper to get a stable key for a *physical* item instance (GUID preferred)
  -- [XIVEquip-AUTO] instanceKeyFromChange: Helper for UI module.
  local function instanceKeyFromChange(c)
    if c and c.newLoc and C_Item and C_Item.GetItemGUID then
      local ok, guid = pcall(C_Item.GetItemGUID, c.newLoc)
      if ok and guid and guid ~= "" then return guid end
    end
    local id = c and c.newLink and tonumber(c.newLink:match("|Hitem:(%d+)"))
    local bag = c and c.newLoc and c.newLoc.bagID or -1
    local slot = c and c.newLoc and c.newLoc.slotIndex or -1
    return table.concat({ id or 0, bag, slot }, ":")
  end

  -- PREVIEW TOOLTIP (no equipping, no chat spam)
  -- [XIVEquip-AUTO] Callback: Callback used by UI.lua to respond to a timer/event/script hook.
  btn:SetScript("OnEnter", function(self)
    showEquipPreviewTooltip(self, "ANCHOR_RIGHT")
  end)

  -- Callback used in UI.lua to run inline logic.
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Callback used in UI.lua to run inline logic.
  btn:SetScript("OnClick", function()
    if XIVEquip.UI and XIVEquip.UI.ClearPreviewCache then XIVEquip.UI.ClearPreviewCache() end
    if XIVEquip and XIVEquip.EquipBestGear then
      XIVEquip:EquipBestGear()
    end
  end)

  -- Disable during combat
  btn:RegisterEvent("PLAYER_REGEN_DISABLED")
  btn:RegisterEvent("PLAYER_REGEN_ENABLED")
  -- Callback used in UI.lua to run inline logic.
  btn:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then self:Disable() else self:Enable() end
  end)

  anchorButton()
  C_Timer.After(0, anchorButton)
end

-- Show only on the Character (PaperDoll) tab
-- [XIVEquip-AUTO] onPaperDollShow: Helper for UI module.
local function onPaperDollShow()
  createButton()
  if btn and PaperDollFrame and btn:GetParent() ~= PaperDollFrame then
    btn:SetParent(PaperDollFrame)
  end
  anchorButton()
end
-- onPaperDollHide: UI wiring: on paper doll hide.
local function onPaperDollHide()
  if btn then btn:Hide() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
-- Callback used in UI.lua to run inline logic.
f:SetScript("OnEvent", function(_, event)
  if event ~= "PLAYER_LOGIN" then
    if XIVEquip.UI and XIVEquip.UI.ClearPreviewCache then XIVEquip.UI.ClearPreviewCache() end
    return
  end

  if XIVEquip.Settings and XIVEquip.Settings.Initialize then XIVEquip.Settings:Initialize() end
  if XIVEquip.UI and XIVEquip.UI.MinimapButton and XIVEquip.UI.MinimapButton.Create then
    XIVEquip.UI.MinimapButton.Create()
  end

  if PaperDollFrame then
    if not PaperDollFrame.__XIVEquipHook then
      PaperDollFrame:HookScript("OnShow", onPaperDollShow)
      PaperDollFrame:HookScript("OnHide", onPaperDollHide)
      PaperDollFrame.__XIVEquipHook = true
    end
    if PaperDollFrame:IsShown() then onPaperDollShow() end
  elseif CharacterFrame then
    if not CharacterFrame.__XIVEquipHook then
      CharacterFrame:HookScript("OnShow", onPaperDollShow)
      CharacterFrame:HookScript("OnHide", onPaperDollHide)
      CharacterFrame.__XIVEquipHook = true
    end
    if CharacterFrame:IsShown() then onPaperDollShow() end
  end
end)
