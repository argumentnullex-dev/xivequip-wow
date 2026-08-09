-- Comparers/ilvl/Export.lua — registers the ilvl comparer
local addon, XIVEquip = ...
XIVEquip = XIVEquip or {}
XIVEquip.Comparers = XIVEquip.Comparers or {}
local M = XIVEquip.Comparers

-- Simple, always-available comparer
M:RegisterComparer("ilvl", {
  Label = "Item Level",

  -- IsAvailable: Comparer integration: is available.
  IsAvailable = function()
    return true
  end,

  -- No special PrePass needed for ilvl
  -- PrePass = function() return true end,

  -- Score an item by ItemLocation or slot id using only item level
  -- [XIVEquip-AUTO] ScoreItem: Computes a score used to compare candidate items.
  ScoreItem = function(location)
    if type(XIVEquip.Ilvl_ScoreLocation) == "function" then
      return tonumber(XIVEquip.Ilvl_ScoreLocation(location)) or 0
    end
    return 0
  end,

  -- Optional header for your hover tooltip
  -- [XIVEquip-AUTO] GetActiveTooltipHeader: Returns active tooltip header.
  GetActiveTooltipHeader = function()
    if type(XIVEquip.Ilvl_GetActiveTooltipHeader) == "function" then
      return XIVEquip.Ilvl_GetActiveTooltipHeader()
    end
    return "Comparer: Item Level"
  end,

  -- Optional debug hook to match Pawn comparer’s DebugScore
  DebugScore = function(location)
    if type(XIVEquip.Ilvl_DebugScore) == "function" then
      return XIVEquip.Ilvl_DebugScore(location)  -- v, "ilvl"
    end
    return nil, "no-ilvl-helper"
  end,
})
