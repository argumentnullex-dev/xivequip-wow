-- Global/Logger.lua
local addonName, XIVEquip = ...
XIVEquip = XIVEquip or _G.XIVEquip or {}
local Const = XIVEquip.Const
local Settings = XIVEquip.Settings

local PREFIX = "|cff66ccffXIVEquip|r"
-- [XIVEquip-AUTO] Fallback print function used if _G.print is unavailable.
local _print = rawget(_G, "print") or print or function() end

-- concatParts: Shared utility: concat parts.
local function concatParts(...)
  local t = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    t[#t + 1] = (v == nil) and "nil" or tostring(v)
  end
  return table.concat(t, " ")
end

-- isDebugEnabled: Shared utility: is debug enabled.
local function isDebugEnabled()
  return Settings and Settings.GetDebugEnabled and Settings:GetDebugEnabled() or false
end

-- slotFilterAllows: Shared utility: slot filter allows.
local function slotFilterAllows(slotID)
  if slotID == "force" then return true end
  if not Settings or not Settings.GetDebugSlot then return false end
  local only = Settings:GetDebugSlot()
  if only == nil then return true end

  local t = type(only)
  if t == "number" then
    return slotID == only
  elseif t == "string" then
    local n = tonumber(only); return n and (slotID == n) or false
  elseif t == "table" then
    return only[slotID] == true
  end
  return false
end

-- safeFormat: Shared utility: safe format.
local function safeFormat(fmt, ...)
  local ok, msg = pcall(string.format, fmt, ...)
  return ok and msg or tostring(fmt)
end

XIVEquip.Log = {
  -- Debug: Shared utility: debug.
  Debug  = function(...)
    if isDebugEnabled() then _print(PREFIX, concatParts(...)) end
  end,
  -- Info: Shared utility: info.
  Info   = function(...) _print(PREFIX, concatParts(...)) end,
  -- Warn: Shared utility: warn.
  Warn   = function(...) _print(PREFIX, "|cffffff00[warn]|r", concatParts(...)) end,
  -- Error: Shared utility: error.
  Error  = function(...) _print(PREFIX, "|cffff3333[error]|r", concatParts(...)) end,

  -- Debugf(slotID, fmt, ...)
  Debugf = function(slotID, fmt, ...)
    if not isDebugEnabled() then return end
    if not slotFilterAllows(slotID) then return end

    local labels = Const and Const.SLOT_LABEL
    local name = (labels and labels[slotID]) or ("Slot " .. tostring(slotID))
    _print(string.format("|cff7fbfffXIVEquip:DBG|r [%s] %s", name, safeFormat(fmt, ...)))
  end,
}

-- Optional single helper used elsewhere
-- [XIVEquip-AUTO] XIVEquip.DebugEnabled: Emits addon debug output when debugging is enabled.
function XIVEquip.DebugEnabled() return isDebugEnabled() end
