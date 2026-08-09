-- Core/Comparers.lua - comparer registry and configured runtime resolution
local addon, XIVEquip = ...
XIVEquip = XIVEquip or {}
XIVEquip.Comparers = XIVEquip.Comparers or {}
local M = XIVEquip.Comparers

---@type Logger
local Log = (XIVEquip.Log) or
-- [XIVEquip-AUTO] Defines a default no-op logger table used until a real logger is configured.
{ Debug = function(...) end, Info = function(...) end, Warn = function(...) end, Error = function(...) end }
local L = (XIVEquip and XIVEquip.L) or {}
local AddonPrefix = L.AddonPrefix or "XIVEquip: "

-- Internal registry and state
local registry = {}
local activeName = "default"
local resolvedName = nil
local runtimeActive = nil
local lastUsedLabel = nil
local lastResolution = nil

local function normalizeKey(name)
  return string.lower(tostring(name or ""))
end

local function canonicalKey(name)
  local key = normalizeKey(name)
  if key == "" then return nil end
  if key == "auto" or key == "default" then return "default" end
  for regKey, def in pairs(registry) do
    if key == regKey or key == normalizeKey(def and def.Label) then
      return regKey
    end
  end
  return nil
end

local function checkUsable(key, def)
  if not def then return false, "unknown" end
  if def.IsAvailable and not def.IsAvailable() then
    return false, "unavailable"
  end
  if def.PrePass then
    local ok, usable = pcall(def.PrePass)
    if not ok then return false, "prepass-error" end
    if usable == false then return false, "prepass-unusable" end
  end
  return true, nil
end

-- M:RegisterComparer: Core addon plumbing: register comparer.
function M:RegisterComparer(name, def)
  registry[normalizeKey(name)] = def
end

-- M:Get: Core addon plumbing: get.
function M:Get(name) return registry[normalizeKey(name)] end

-- M:All: Core addon plumbing: all.
function M:All() return registry end

-- M:GetActiveName: Core addon plumbing: get active name.
function M:GetActiveName() return activeName end

function M:GetResolvedName() return resolvedName or activeName end

-- M:GetActive: Core addon plumbing: get active.
function M:GetActive() return runtimeActive or self:Get(resolvedName or activeName) end

-- M:GetLastUsedLabel: Core addon plumbing: get last used label.
function M:GetLastUsedLabel() return lastUsedLabel end

function M:GetLastResolution() return lastResolution end

function M:CanonicalKey(name) return canonicalKey(name) end

function M:GetDisplayLabel(name)
  local key = canonicalKey(name) or normalizeKey(name)
  if key == "default" then return "Default" end
  local def = registry[key]
  return (def and def.Label) or tostring(name or key)
end

function M:ResolveConfiguredComparer(runPrePass)
  local s = _G.XIVEquip_Settings or {}
  local configured = (XIVEquip.Settings and XIVEquip.Settings.GetComparerName and XIVEquip.Settings:GetComparerName())
      or (s.Comparer and s.Comparer.Selected)
      or s.SelectedComparer
      or "default"
  local configuredKey = canonicalKey(configured) or normalizeKey(configured)

  local result = {
    configured_key = configuredKey,
    requested_key = configuredKey,
    resolved_key = nil,
    comparer = nil,
    fallback_used = false,
    reason = nil,
  }

  local function choose(key, fallbackUsed, reason)
    local def = registry[key]
    local usable, unusableReason = true, nil
    if runPrePass then usable, unusableReason = checkUsable(key, def) end
    if def and usable then
      result.resolved_key = key
      result.comparer = def
      result.fallback_used = fallbackUsed == true
      result.reason = reason
      return true
    end
    result.reason = unusableReason or reason or "unavailable"
    return false
  end

  if configuredKey == "default" then
    if choose("pawn", false, nil) then return result end
    if choose("ilvl", true, result.reason or "pawn-unavailable") then return result end
    return result
  end

  if not registry[configuredKey] then
    if choose("ilvl", true, "unknown") then return result end
    return result
  end

  choose(configuredKey, false, nil)
  return result
end

-- Initialize: honor user setting; "default" = Pawn when usable, otherwise ilvl.
function M:Initialize()
  local resolution = self:ResolveConfiguredComparer(true)
  activeName = resolution.configured_key or "default"
  resolvedName = resolution.resolved_key
  lastResolution = resolution
  if activeName == "default" and resolvedName == "pawn" then return "default:pawn", resolution end
  if activeName == "default" and resolvedName == "ilvl" then return "default:ilvl", resolution end
  if resolution.reason == "unknown" then return "saved:unknown", resolution end
  if not resolution.comparer then return "saved:unavailable", resolution end
  return "saved:ok", resolution
end

-- [XIVEquip-AUTO] M:StartPass: Helper for Core module.
function M:StartPass()
  runtimeActive = nil
  lastUsedLabel = nil

  local resolution = self:ResolveConfiguredComparer(true)
  activeName = resolution.configured_key or "default"
  resolvedName = resolution.resolved_key
  lastResolution = resolution

  if not resolution.comparer then
    Log.Warn("Comparer '" .. tostring(activeName) .. "' not available.")
    return nil, resolution
  end

  if resolution.fallback_used then
    Log.Warn("Comparer fallback: " .. tostring(activeName) .. " -> " .. tostring(resolution.resolved_key))
  end

  runtimeActive = resolution.comparer
  lastUsedLabel = resolution.comparer.Label or resolution.resolved_key
  return resolution.comparer, resolution
end

function M:AcquirePass()
  local cmp, resolution = self:StartPass()
  local closed = false
  return {
    comparer = cmp,
    resolution = resolution,
    Close = function()
      if closed then return end
      closed = true
      if M.EndPass then M:EndPass() end
    end,
    EndPass = function(selfLease)
      return selfLease:Close()
    end,
  }
end

-- M:EndPass: Core addon plumbing: end pass.
function M:EndPass()
  runtimeActive = nil
end
