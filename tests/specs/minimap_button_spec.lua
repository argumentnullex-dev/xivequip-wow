local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function join(...) return table.concat({ ... }, sep) end

local function loadMinimap(addon)
  local chunk = assert(loadfile(join(root, "XIVEquip", "UI", "MinimapButton.lua")))
  chunk("XIVEquip", addon)
end

local function texture()
  return {
    SetSize = function() end,
    SetPoint = function() end,
    SetTexture = function() end,
    SetTexCoord = function() end,
    SetBlendMode = function() end,
    ClearAllPoints = function() end,
  }
end

local function frame()
  local f = { scripts = {}, textures = {} }
  function f:SetSize() end
  function f:SetFrameStrata() end
  function f:RegisterForClicks() end
  function f:RegisterForDrag() end
  function f:CreateTexture()
    local t = texture()
    self.textures[#self.textures + 1] = t
    return t
  end
  function f:SetHighlightTexture() end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:ClearAllPoints() self.cleared = true end
  function f:SetPoint(...) self.point = { ... } end
  function f:Show() self.visible = true end
  function f:Hide() self.visible = false end
  return f
end

local function harness()
  local calls = { equip = 0, settings = 0, preview = 0, tooltip = {} }
  local created
  _G.Minimap = {
    GetWidth = function() return 174 end,
    GetCenter = function() return 0, 0 end,
  }
  _G.UIParent = { GetEffectiveScale = function() return 1 end }
  _G.GetCursorPosition = function() return 100, 100 end
  _G.MouseIsOver = function() return true end
  _G.IsShiftKeyDown = function() return false end
  _G.GameTooltip = {
    SetOwner = function() end,
    ClearLines = function() calls.tooltip = {} end,
    AddLine = function(_, line) calls.tooltip[#calls.tooltip + 1] = line end,
    Show = function() calls.tooltipShown = true end,
    Hide = function() calls.tooltipHidden = true end,
  }
  _G.CreateFrame = function()
    created = frame()
    return created
  end

  local addon = {
    UI = {
      SettingsWindow = {
        Toggle = function() calls.settings = calls.settings + 1 end,
      },
      RenderEquipPreviewTooltip = function(_, anchor)
        calls.preview = calls.preview + 1
        calls.previewAnchor = anchor
      end,
    },
    Settings = {
      GetMinimapAngle = function() return 220 end,
      SetMinimapAngle = function(_, angle) calls.angle = angle end,
      GetMinimapHidden = function() return false end,
    },
    EquipBestGear = function() calls.equip = calls.equip + 1 end,
  }
  loadMinimap(addon)
  local button = addon.UI.MinimapButton.Create()
  return addon, calls, button or created
end

test("left click equips and right click opens config", function()
  local _, calls, button = harness()

  button.scripts.OnClick(button, "LeftButton")
  button.scripts.OnClick(button, "RightButton")

  A.equal(calls.equip, 1)
  A.equal(calls.settings, 1)
end)

test("hover documents minimap button actions", function()
  local _, calls, button = harness()

  button.scripts.OnEnter(button)

  local text = table.concat(calls.tooltip, "\n")
  A.truthy(text:find("Left Click - Equip Best", 1, true))
  A.truthy(text:find("Right Click - Open Config", 1, true))
  A.truthy(text:find("Hold Shift - Preview recommendations", 1, true))
end)

test("shift hover renders the shared equip preview", function()
  local _, calls, button = harness()
  _G.IsShiftKeyDown = function() return true end

  button.scripts.OnEnter(button)

  A.equal(calls.preview, 1)
  A.equal(calls.previewAnchor, "ANCHOR_LEFT")
end)

test("drag restores shift-hover update handling", function()
  local _, _, button = harness()

  button.scripts.OnDragStart(button)
  A.equal(button.scripts.OnUpdate ~= nil, true)
  button.scripts.OnDragStop(button)
  A.equal(button.scripts.OnUpdate ~= nil, true)
end)

return tests
