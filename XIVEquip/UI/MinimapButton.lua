-- UI/MinimapButton.lua
local addonName, XIVEquip = ...
XIVEquip.UI = XIVEquip.UI or {}
XIVEquip.UI.MinimapButton = XIVEquip.UI.MinimapButton or {}

local Button = XIVEquip.UI.MinimapButton
local ICON = "Interface\\AddOns\\XIVEquip\\Assets\\icon_blue_128"
local BUTTON_RADIUS = 92
local BUTTON_SIZE = 31
local BORDER_SIZE = 50
local BACKGROUND_SIZE = 24
local ICON_SIZE = 18

local function settingsApi() return XIVEquip.Settings end

local function minimapPoint(angle)
  local rad = math.rad(tonumber(angle) or 220)
  return math.cos(rad) * BUTTON_RADIUS, math.sin(rad) * BUTTON_RADIUS
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
  btn:SetScript("OnClick", function()
    if XIVEquip.UI.SettingsWindow and XIVEquip.UI.SettingsWindow.Toggle then
      XIVEquip.UI.SettingsWindow.Toggle()
    end
  end)
  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", updateAngle)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    Button.Refresh()
  end)
  btn:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine("XIVEquip")
      GameTooltip:AddLine("Open settings", 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end
  end)
  btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  Button.Frame = btn
  Button.Refresh()
  return btn
end
