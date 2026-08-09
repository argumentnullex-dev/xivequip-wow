-- UI/MinimapButton.lua
local addonName, XIVEquip = ...
XIVEquip.UI = XIVEquip.UI or {}
XIVEquip.UI.MinimapButton = XIVEquip.UI.MinimapButton or {}

local Button = XIVEquip.UI.MinimapButton
local ICON = "Interface\\AddOns\\XIVEquip\\Assets\\icon_blue_128"

local function settingsApi() return XIVEquip.Settings end

local function minimapPoint(angle)
  local rad = math.rad(tonumber(angle) or 220)
  return math.cos(rad) * 80, math.sin(rad) * 80
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
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")

  local tex = btn:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  tex:SetTexture(ICON)

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
