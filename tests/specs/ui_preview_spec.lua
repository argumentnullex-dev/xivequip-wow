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

local function newHarness(mode)
  local calls = { passStarts = 0, passEnds = 0, plan = {}, weapons = 0 }
  local eventFrame, button
  local paperDoll = frame()
  paperDoll.GetName = function() return "PaperDollFrame" end
  paperDoll.IsShown = function() return true end

  _G.PaperDollFrame = paperDoll
  _G.CharacterFrame = nil
  _G.UIParent = frame()
  _G.CharacterFramePortrait = nil
  _G.C_Item = {}
  _G.C_Timer = { After = function(_, fn) fn() end }
  _G.InCombatLockdown = function() return false end
  _G.GameTooltip = {
    SetOwner = function() end,
    ClearLines = function() end,
    AddLine = function() end,
    Show = function() end,
    Hide = function() end,
  }
  _G.CreateFrame = function(_, name, parent)
    local f = frame()
    f.parent = parent
    if name == "XIVEquipButton" then button = f else eventFrame = f end
    return f
  end

  local addon = {
    L = { ButtonTooltip = "Equip Recommended Gear" },
    Settings = {
      GetPlannerMode = function() return mode end,
      GetMessage = function(_, key)
        if key == "Preview" then return true end
        return true
      end,
      SetMessage = function() end,
    },
    Gear = {
      PlanBest = function(_, cmp, opts)
        calls.plan[#calls.plan + 1] = { cmp = cmp, opts = opts }
        return {}, false, {}, { diagnostics = { scoreSource = "Item Level" } }
      end,
    },
    Comparers = {
      StartPass = function()
        calls.passStarts = calls.passStarts + 1
        return { GetActiveTooltipHeader = function() return "Comparer: test" end }, {}
      end,
      EndPass = function() calls.passEnds = calls.passEnds + 1 end,
    },
    Weapons = {
      PlanBest = function()
        calls.weapons = calls.weapons + 1
      end,
    },
  }

  loadUI(addon)
  eventFrame.scripts.OnEvent(eventFrame, "PLAYER_LOGIN")
  return addon, calls, button
end

test("native hover preview uses native planning without legacy comparer or weapon planner", function()
  local _, calls, button = newHarness("native")

  button.scripts.OnEnter(button)

  A.equal(#calls.plan, 1)
  A.equal(calls.plan[1].opts.planner, "native")
  A.equal(calls.plan[1].cmp, nil)
  A.equal(calls.passStarts, 0)
  A.equal(calls.passEnds, 0)
  A.equal(calls.weapons, 0)
end)

test("legacy hover preview uses one legacy comparer pass", function()
  local _, calls, button = newHarness("legacy")

  button.scripts.OnEnter(button)

  A.equal(#calls.plan, 1)
  A.equal(calls.plan[1].opts.planner, "legacy")
  A.truthy(calls.plan[1].cmp)
  A.equal(calls.passStarts, 1)
  A.equal(calls.passEnds, 1)
  A.equal(calls.weapons, 0)
end)

return tests
