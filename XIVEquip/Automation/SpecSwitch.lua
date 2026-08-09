-- AutoSpecSwitcher.lua (drop-in)
local addonName, XIVEquip = ...
XIVEquip = XIVEquip or {}

-- Helpers
-- [XIVEquip-AUTO] GearMod: Helper for Automation module.
local function GearMod() return XIVEquip and XIVEquip.Gear end
local function Settings() return XIVEquip and XIVEquip.Settings end
-- [XIVEquip-AUTO] prefix: Builds a user-facing prefix string for addon messages/logging.
local function prefix()
  return (XIVEquip and XIVEquip.L and XIVEquip.L.AddonPrefix) or "XIVEquip: "
end
-- [XIVEquip-AUTO] dbg: Debug logger for Automation; prints only when debug flags are enabled.
local function dbg(fmt, ...)
  if not _G.XIVEquip_DebugAutoSpec then return end
  local ok, msg = pcall(string.format, fmt, ...)
  print(prefix() .. "[AutoSpec] " .. (ok and msg or tostring(fmt)))
end

local f = CreateFrame("Frame")
local lastSpecIndex = nil
local baselineReady = false
local pending = false
local lastRunAt = 0

-- [XIVEquip-AUTO] tryBaseline: Establishes baseline state to prevent false triggers during login/loads.
local function tryBaseline(tag)
  local idx = GetSpecialization and GetSpecialization() or nil
  if not idx then
    dbg("%s: spec index not ready yet", tostring(tag))
    return false
  end
  lastSpecIndex = idx
  baselineReady = true
  dbg("%s: baseline specIndex=%s", tostring(tag), tostring(lastSpecIndex))
  return true
end

-- [XIVEquip-AUTO] canRun: Helper used by Automation.
local function canRun()
  local S = Settings()
  if not (S and S.GetAutomation and S:GetAutomation("SpecEquip")) then
    dbg("blocked: setting OFF")
    return false
  end
  if InCombatLockdown() then
    dbg("blocked: in combat")
    return false
  end
  local Gear = GearMod()
  if not (Gear and Gear.EquipBest) then
    dbg("blocked: Gear:EquipBest not available yet")
    return false
  end
  return true
end

-- [XIVEquip-AUTO] equipNow: Performs an equip operation (or schedules one) for Automation.
local function equipNow(reason)
  dbg("equipNow(%s) called", tostring(reason))
  if not canRun() then
    if InCombatLockdown() then
      pending = true
      f:RegisterEvent("PLAYER_REGEN_ENABLED")
      dbg("queued for after combat")
    end
    return
  end
  local now = GetTime and GetTime() or 0
  if (now - lastRunAt) < 0.75 then
    dbg("throttled (%.2f s since last run)", now - lastRunAt)
    return
  end
  lastRunAt = now

  local Gear = GearMod()
  if Gear and Gear.EquipBest then
    dbg("calling Gear:EquipBest()")
    Gear:EquipBest() -- your Gear handles saving "Spec.xive" set
  end
end

-- [XIVEquip-AUTO] updateSpecIndex: Updates cached state used by Automation.
local function updateSpecIndex(tag)
  local idx = GetSpecialization()
  dbg("updateSpecIndex(%s): old=%s new=%s", tostring(tag), tostring(lastSpecIndex), tostring(idx))

  -- If we haven't captured a real baseline yet (common during login), do NOT equip.
  -- Just establish baseline and exit.
  if not baselineReady then
    if tryBaseline(tag .. ":baseline") then
      dbg("baseline established; not equipping")
    end
    return
  end

  if idx and idx ~= lastSpecIndex then
    lastSpecIndex = idx
    -- Callback used in SpecSwitch.lua to run inline logic.
    C_Timer.After(0.25, function() equipNow(tag or "SPEC_CHANGED") end)
  else
    dbg("no change detected; not equipping")
  end
end

-- Callback used in SpecSwitch.lua to run inline logic.
f:SetScript("OnEvent", function(self, event, arg1)
  if event == "PLAYER_ENTERING_WORLD" then
    -- Initialize baseline (no auto-equip at login/zone)
    baselineReady = false
    -- Spec index can be nil here; poll briefly until it exists.
    local tries = 0
    -- Callback used in SpecSwitch.lua to run inline logic.
    C_Timer.NewTicker(0.25, function(t)
      tries = tries + 1
      if tryBaseline("PEW") then t:Cancel() end
      if tries >= 20 then t:Cancel() end
    end)
  elseif event == "PLAYER_LOGIN" then
    -- Redundant baseline for safety (still no equip)
    if not baselineReady then
      tryBaseline("LOGIN")
    end
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
    -- Some clients pass unit, some don’t—treat nil as player
    local unit = arg1 or "player"
    dbg("PLAYER_SPECIALIZATION_CHANGED unit=%s", tostring(unit))
    if unit == "player" then
      updateSpecIndex("PLAYER_SPECIALIZATION_CHANGED")
    end
  elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
    dbg("ACTIVE_TALENT_GROUP_CHANGED")
    updateSpecIndex("ACTIVE_TALENT_GROUP_CHANGED")
  elseif event == "PLAYER_TALENT_UPDATE" then
    -- Fires a lot; we still gate by spec index change and throttle
    dbg("PLAYER_TALENT_UPDATE")
    updateSpecIndex("PLAYER_TALENT_UPDATE")
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pending then
      pending = false
      self:UnregisterEvent("PLAYER_REGEN_ENABLED")
      dbg("out of combat; running equip")
      -- Callback used in SpecSwitch.lua to run inline logic.
      C_Timer.After(0.10, function() equipNow("OUT_OF_COMBAT") end)
    end
  end
end)

-- Register events
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
f:RegisterEvent("PLAYER_TALENT_UPDATE")

-- Slash toggle + test
SLASH_XIVEAUTO1 = "/xiveauto"
-- [XIVEquip-AUTO] XIVEAUTO: Helper used by Automation.
SlashCmdList.XIVEAUTO = function(msg)
  msg = tostring(msg or ""):lower()
  if msg:match("^%s*test") then
    equipNow("SLASH_TEST")
    return
  end
  _G.XIVEquip_Settings = _G.XIVEquip_Settings or {}
  local s = _G.XIVEquip_Settings
  local S = Settings()
  local enabled = not (S and S.GetAutomation and S:GetAutomation("SpecEquip"))
  if S and S.SetAutomation then
    S:SetAutomation("SpecEquip", enabled)
  else
    s.Automation = s.Automation or {}
    s.Automation.SpecEquip = enabled
  end
  print(prefix() .. "Auto-equip on spec change: " .. (enabled and "|cff55ff55ON|r" or "|cffff5555OFF|r"))
end
