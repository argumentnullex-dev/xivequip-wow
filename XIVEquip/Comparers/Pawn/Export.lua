-- Pawn_Comparer.lua — registers the Pawn comparer using helpers from Pawn.lua
local addon, XIVEquip = ...
XIVEquip = XIVEquip or {}
XIVEquip.Comparers = XIVEquip.Comparers or {}
local M = XIVEquip.Comparers
local Log = XIVEquip.Log
local L = (XIVEquip and XIVEquip.L) or {}
local Core = XIVEquip.Gear_Core
local AddonPrefix = L.AddonPrefix or "XIVEquip: "

-- The comparer
M:RegisterComparer("Pawn", {
  Label = "Pawn",

  -- Available if we can list active scales & there is at least one
  -- [XIVEquip-AUTO] IsAvailable: Predicate helper used for feature gating or filtering.
  IsAvailable = function()
    return XIVEquip.Pawn and type(XIVEquip.Pawn.GetActiveScales) == "function"
        and #((XIVEquip.Pawn.GetActiveScales and XIVEquip.Pawn.GetActiveScales()) or {}) > 0
  end,

  -- Usable for this pass if there’s ≥1 active scale (per-character)
  -- [XIVEquip-AUTO] PrePass: Helper for Pawn module.
  PrePass = function()
    local list = (XIVEquip.Pawn and type(XIVEquip.Pawn.GetActiveScales) == "function") and
        XIVEquip.Pawn.GetActiveScales() or {}
    return #list > 0
  end,

  -- Score an item by ItemLocation
  -- [XIVEquip-AUTO] ScoreItem: Computes a score used to compare candidate items.
  ScoreItem = function(location, slotID) -- slot id is passed as a convenience
    local link = Core.linkFromLocation(location)
    if link and XIVEquip.Pawn and type(XIVEquip.Pawn.ScoreItemLink) == "function" then
      local v = select(1, XIVEquip.Pawn.ScoreItemLink(link, slotID))
      return tonumber(v) or 0
    end
    Log:Debug("Failed to score item in Pawn comparer")
    return 0
  end,

  -- GetActiveTooltipHeader: Comparer integration: get active tooltip header.
  GetActiveTooltipHeader = function()
    if XIVEquip.Pawn and type(XIVEquip.Pawn.GetTooltipHeader) == "function" then
      return XIVEquip.Pawn.GetTooltipHeader()
    end
    return ""
  end,

  DebugScore = function(location, slotID)
    local link = type(location) == "string" and location or Core.linkFromLocation(location)
    if link and XIVEquip.Pawn and type(XIVEquip.Pawn.ScoreItemLink) == "function" then
      return XIVEquip.Pawn.ScoreItemLink(link, slotID)
    end
    return nil, "no-pawn-helper"
  end
})
