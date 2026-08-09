-- Comparers/ilvl/Interface.lua — item level comparer helpers (no registration)
local addon, XIVEquip = ...
XIVEquip = XIVEquip or {}

-- [XIVEquip-AUTO] Inline no-op logger fallback used when XIVEquip.Log isn't available yet.
local Log = XIVEquip.Log or { Debug=function() end }

-- --- Helpers to obtain a link & item level from a location ------------------

-- [XIVEquip-AUTO] linkFromLocation: Helper for ilvl module.
local function linkFromLocation(location)
  if type(location) == "string" then
    return location
  end
  -- ItemLocation (bags/equipped)
  if C_Item and C_Item.GetItemLink and type(location) == "table" then
    local ok, link = pcall(C_Item.GetItemLink, location)
    if ok and link then return link end
  end
  -- Inventory slot id
  if type(location) == "number" and GetInventoryItemLink then
    local ok, link = pcall(GetInventoryItemLink, "player", location)
    if ok and link then return link end
  end
  return nil
end

-- getIlvlFromLink: Comparer integration: get ilvl from link.
local function getIlvlFromLink(link)
  if not link then return 0 end
  if GetDetailedItemLevelInfo then
    local ok, ilvl = pcall(GetDetailedItemLevelInfo, link)
    if ok and type(ilvl) == "number" and ilvl > 0 then return ilvl end
  end
  -- Fallback: the coarse API
  if C_Item and C_Item.GetCurrentItemLevel then
    local ok, ilvl = pcall(C_Item.GetCurrentItemLevel, link)
    if ok and type(ilvl) == "number" and ilvl > 0 then return ilvl end
  end
  return 0
end

-- getIlvlFromLocation: Comparer integration: get ilvl from location.
local function getIlvlFromLocation(location)
  -- Prefer the location-based API when possible
  if C_Item and C_Item.GetCurrentItemLevel and type(location) == "table" then
    local ok, ilvl = pcall(C_Item.GetCurrentItemLevel, location)
    if ok and type(ilvl) == "number" and ilvl > 0 then return ilvl end
  end
  local link = linkFromLocation(location)
  return getIlvlFromLink(link)
end

-- --- Public (addon-scoped) helpers used by Export.lua -----------------------

-- Score an item by ItemLocation or slot id strictly by ilvl
-- [XIVEquip-AUTO] XIVEquip.Ilvl_ScoreLocation: Computes a score used to compare candidate items.
function XIVEquip.Ilvl_ScoreLocation(location)
  return getIlvlFromLocation(location) or 0
end

-- Optional debug hook to mirror Pawn comparer’s DebugScore contract
-- Returns: value, sourceTag
function XIVEquip.Ilvl_DebugScore(location)
  local v = getIlvlFromLocation(location) or 0
  return v, "ilvl"
end

-- Tooltip header line for UI
-- [XIVEquip-AUTO] XIVEquip.Ilvl_GetActiveTooltipHeader: Helper for ilvl module.
function XIVEquip.Ilvl_GetActiveTooltipHeader()
  return "Comparer: Item Level"
end
