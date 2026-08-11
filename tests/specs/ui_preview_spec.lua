local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function join(...) return table.concat({ ... }, sep) end

local function loadUI(addon)
  local chunk = assert(loadfile(join(root, "XIVEquip", "UI", "UI.lua")))
  chunk("XIVEquip", addon)
end

local function frame()
  local f = { scripts = {} }
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:HookScript() end
  function f:RegisterEvent() end
  function f:RegisterForDrag() end
  function f:SetSize() end
  function f:SetFrameStrata() end
  function f:SetFrameLevel() end
  function f:GetFrameLevel() return 1 end
  function f:SetClampedToScreen() end
  function f:SetMovable() end
  function f:SetBackdrop() end
  function f:SetBackdropColor() end
  function f:SetBackdropBorderColor() end
  function f:SetNormalTexture() end
  function f:SetPushedTexture() end
  function f:SetDisabledTexture() end
  function f:SetHighlightTexture() end
  function f:CreateTexture()
    return {
      SetAllPoints = function() end,
      SetTexture = function() end,
      SetVertexColor = function() end,
    }
  end
  function f:ClearAllPoints() end
  function f:SetPoint() end
  function f:Show() end
  function f:Hide() end
  function f:GetParent() return self.parent end
  function f:SetParent(parent) self.parent = parent end
  function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
  function f:GetName() return "FakeFrame" end
  function f:StartMoving() end
  function f:StopMovingOrSizing() end
  function f:Disable() end
  function f:Enable() end
  return f
end

local function newHarness(overrides)
  overrides = overrides or {}
  local calls = { plan = {}, pawnScores = 0 }
  local eventFrame, button
  local paperDoll = frame()
  paperDoll.GetName = function() return "PaperDollFrame" end
  paperDoll.IsShown = function() return true end

  _G.PaperDollFrame = paperDoll
  _G.CharacterFrame = nil
  _G.UIParent = frame()
  _G.CharacterFramePortrait = nil
  _G.C_Item = {}
  _G.GetItemInfo = function() return nil end
  _G.C_Timer = { After = function(_, fn) fn() end }
  _G.InCombatLockdown = function() return false end
  _G.MouseIsOver = function() return true end
  _G.GetTime = function() return overrides.now or 100 end
  _G.geterrorhandler = function()
    return function(err) error(err, 0) end
  end
  _G.GameTooltip = {
    SetOwner = function() end,
    ClearLines = function() end,
    AddLine = function(_, line) calls.tooltipLines[#calls.tooltipLines + 1] = line end,
    Show = function() end,
    Hide = function() end,
  }
  calls.tooltipLines = {}
  _G.CreateFrame = function(_, name, parent)
    local f = frame()
    f.parent = parent
    if name == "XIVEquipButton" then button = f else eventFrame = f end
    return f
  end

  local addon = {
    L = { ButtonTooltip = "Equip Recommended Gear" },
    Settings = {
      GetMessage = function(_, key)
        if key == "Preview" then return true end
        return true
      end,
      SetMessage = function() end,
    },
    Gear = {
      PlanBest = function(_)
        calls.plan[#calls.plan + 1] = true
        if overrides.planReturn then return overrides.planReturn(calls) end
        return {}, false, {}, {
          weights = { resolution = { sourceLabel = "Default", scaleLabel = "Retribution" } },
        }
      end,
    },
    Pawn = {
      ScoreItemLink = function()
        calls.pawnScores = calls.pawnScores + 1
        return 999
      end,
    },
    XIVWeights = {
      Config = {
        ResolvedScaleDisplayLabel = function(scale)
          local resolution = scale.resolution
          return resolution.sourceLabel .. " | " .. resolution.scaleLabel
        end,
      },
    },
  }

  loadUI(addon)
  eventFrame.scripts.OnEvent(eventFrame, "PLAYER_LOGIN")
  return addon, calls, button
end

test("hover preview uses the native planner once", function()
  local _, calls, button = newHarness()

  button.scripts.OnEnter(button)

  A.equal(#calls.plan, 1)
end)

test("hover preview shows the compact source and scale header", function()
  local _, calls, button = newHarness({
    planReturn = function()
      return {}, false, {}, {
        weights = { resolution = { sourceLabel = "Default", scaleLabel = "Retribution" } },
      }
    end,
  })

  button.scripts.OnEnter(button)

  local header = table.concat(calls.tooltipLines, "\n")
  A.truthy(header:find("Default | Retribution", 1, true))
  A.falsy(header:find("Planner:", 1, true))
  A.falsy(header:find("Source:", 1, true))
end)

test("hover preview preserves explicit zero score deltas instead of recomputing with Pawn", function()
  local _, calls, button = newHarness({
    planReturn = function()
      return {
        {
          slotName = "Ring 1",
          oldLink = "|Hitem:101::::::::::::|h[old]|h",
          newLink = "|Hitem:201::::::::::::|h[new]|h",
          deltaScore = 0,
          deltaIlvl = 0,
        },
      }, false, {}, {
        weights = { resolution = { sourceLabel = "Default", scaleLabel = "Retribution" } },
      }
    end,
  })

  button.scripts.OnEnter(button)

  A.equal(calls.pawnScores, 0)
end)

test("hover preview reuses a short-lived native plan cache", function()
  local _, calls, button = newHarness()

  button.scripts.OnEnter(button)
  button.scripts.OnEnter(button)

  A.equal(#calls.plan, 1)
end)

test("hover preview does not schedule planning when preview messages are disabled", function()
  local addon, calls, button = newHarness()
  addon.Settings.GetMessage = function(_, key)
    if key == "Preview" then return false end
    return true
  end

  button.scripts.OnEnter(button)

  A.equal(#calls.plan, 0)
end)

return tests
