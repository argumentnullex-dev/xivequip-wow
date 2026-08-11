-- UI/MinimapButton.lua
local addonName, XIVEquip = ...
XIVEquip.UI = XIVEquip.UI or {}
XIVEquip.UI.MinimapButton = XIVEquip.UI.MinimapButton or {}

local Button = XIVEquip.UI.MinimapButton
local ICON = "Interface\\AddOns\\XIVEquip\\Assets\\icon_blue_128"
local BUTTON_EDGE_OFFSET = 5
local BUTTON_SIZE = 31
local BORDER_SIZE = 50
local BACKGROUND_SIZE = 24
local ICON_SIZE = 18

local function settingsApi() return XIVEquip.Settings end

local function showHelpTooltip(btn)
  if not GameTooltip then return end
  GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine("XIVEquip")
  GameTooltip:AddLine("Left Click - Equip Best", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Right Click - Open Config", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Hold Shift - Preview recommendations", 0.8, 0.8, 0.8)
  GameTooltip:Show()
end

local function showTooltip(btn)
  if IsShiftKeyDown and IsShiftKeyDown()
      and XIVEquip.UI and XIVEquip.UI.RenderEquipPreviewTooltip then
    XIVEquip.UI.RenderEquipPreviewTooltip(btn, "ANCHOR_LEFT")
  else
    showHelpTooltip(btn)
  end
end

local function hoverUpdate(self)
  local shifted = IsShiftKeyDown and IsShiftKeyDown() or false
  if self._xiveShifted ~= shifted and MouseIsOver and MouseIsOver(self) then
    self._xiveShifted = shifted
    showTooltip(self)
  end
end

local function minimapPoint(angle)
  local rad = math.rad(tonumber(angle) or 220)
  local radius = ((Minimap and Minimap.GetWidth and Minimap:GetWidth() or 174) / 2) + BUTTON_EDGE_OFFSET
  return math.cos(rad) * radius, math.sin(rad) * radius
end

local function place(btn)
  local S = settingsApi()
  local x, y = minimapPoint(S and S:GetMinimapAngle() or 220)
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function updateAngle(btn)
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  px, py = px / scale, py / scale
  local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
  local angle = math.deg(atan2(py - my, px - mx))
  local S = settingsApi()
  if S then S:SetMinimapAngle(angle) end
  place(btn)
end

function Button.Refresh()
  local btn = Button.Frame
  if not btn then return end
  local S = settingsApi()
  if S and S:GetMinimapHidden() then btn:Hide() else btn:Show() end
  place(btn)
end

function Button.Create()
  if Button.Frame or not Minimap then return Button.Frame end
  local btn = CreateFrame("Button", "XIVEquipMinimapButton", Minimap)
  btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  btn:SetFrameStrata("MEDIUM")
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")

  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetSize(BORDER_SIZE, BORDER_SIZE)
  border:SetPoint("TOPLEFT", 0, 0)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  local background = btn:CreateTexture(nil, "BACKGROUND")
  background:SetSize(BACKGROUND_SIZE, BACKGROUND_SIZE)
  background:SetPoint("CENTER", 0, 0)
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("CENTER", 0, 0)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  btn.Icon = icon

  local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  highlight:SetPoint("CENTER", 0, 0)
  highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  highlight:SetBlendMode("ADD")
  btn:SetHighlightTexture(highlight)

  btn:SetScript("OnMouseDown", function(self)
    if self.Icon then
      self.Icon:ClearAllPoints()
      self.Icon:SetPoint("CENTER", 1, -1)
    end
  end)
  btn:SetScript("OnMouseUp", function(self)
    if self.Icon then
      self.Icon:ClearAllPoints()
      self.Icon:SetPoint("CENTER", 0, 0)
    end
  end)
  btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" and XIVEquip.UI.SettingsWindow and XIVEquip.UI.SettingsWindow.Toggle then
      XIVEquip.UI.SettingsWindow.Toggle()
    elseif button == "LeftButton" and XIVEquip.EquipBestGear then
      XIVEquip:EquipBestGear()
    end
  end)
  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", updateAngle)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", hoverUpdate)
    Button.Refresh()
  end)
  btn:SetScript("OnEnter", function(self)
    showTooltip(self)
  end)
  btn:SetScript("OnUpdate", hoverUpdate)
  btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  Button.Frame = btn
  Button.Refresh()
  return btn
end
