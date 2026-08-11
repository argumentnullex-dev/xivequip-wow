-- Evaluation/CandidateCollector.lua
-- Collects equipped + bag items into normalized candidates. This module is
-- intentionally boring: it resolves item links, preserves source identity,
-- reports pending/unresolved entries, and delegates all legality/scoring to
-- downstream policies and assignment solvers.
local addonName, XIVEquip = ...
XIVEquip.Evaluation = XIVEquip.Evaluation or {}
local Evaluation = XIVEquip.Evaluation

local CandidateCollector = {}
Evaluation.CandidateCollector = CandidateCollector

local DEFAULT_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local SUPPORTED_WEAPON_EQUIPLOCS = {
  INVTYPE_WEAPON = true,
  INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_2HWEAPON = true,
  INVTYPE_RANGED = true,
  INVTYPE_RANGEDRIGHT = true,
  INVTYPE_THROWN = true,
  INVTYPE_HOLDABLE = true,
  INVTYPE_SHIELD = true,
}

local function parseItemID(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hitem:(%d+)") or link:match("item:(%d+)"))
end

local function locationLink(location)
  local Core = XIVEquip.Gear_Core
  if Core and type(Core.linkFromLocation) == "function" then
    return Core.linkFromLocation(location)
  end
  if C_Item and type(C_Item.GetItemLink) == "function" then
    local ok, link = pcall(C_Item.GetItemLink, location)
    if ok and link then return link end
  end
  return nil
end

local function itemGUID(location)
  if C_Item and type(C_Item.GetItemGUID) == "function" then
    local ok, guid = pcall(C_Item.GetItemGUID, location)
    if ok then return guid end
  end
  return nil
end

local function requestLoad(location)
  if C_Item and type(C_Item.RequestLoadItemData) == "function" then
    pcall(C_Item.RequestLoadItemData, location)
  end
end

local function locationHasItem(location)
  if C_Item and type(C_Item.DoesItemExist) == "function" then
    local ok, exists = pcall(C_Item.DoesItemExist, location)
    if ok then return exists == true end
  end
  return false
end

local function canNormalize(link, itemID)
  if type(GetItemInfoInstant) ~= "function" then return true end
  local ok, id, _, _, equipLoc = pcall(GetItemInfoInstant, itemID or link)
  return ok and id ~= nil and equipLoc ~= nil
end

local function appendUnresolved(result, source, reason, link, itemID)
  result.pending = true
  source.reason = reason
  source.link = link
  source.itemID = itemID
  result.unresolved[#result.unresolved + 1] = source
end

local function supportedEquipLoc(equipLoc)
  if type(equipLoc) ~= "string" or equipLoc == "" then return false end
  local Const = XIVEquip.Const or {}
  if Const.INV_BY_EQUIPLOC and Const.INV_BY_EQUIPLOC[equipLoc] then return true end
  return SUPPORTED_WEAPON_EQUIPLOCS[equipLoc] == true
end

local function couldBeSupportedEquipment(itemID, link)
  if type(GetItemInfoInstant) ~= "function" then return true end
  local ok, resolvedID, _, _, equipLoc = pcall(GetItemInfoInstant, itemID or link)
  if not ok then return true end
  if not resolvedID then return true end
  return supportedEquipLoc(equipLoc)
end

local function collectLocation(result, location, source)
  if not location then return nil end
  local perf = result.perf
  local link = locationLink(location)
  local itemID = parseItemID(link) or source.itemID
  source.guid = source.guid or itemGUID(location)

  if not link then
    if source.kind == "equipped" and not locationHasItem(location) then return nil end
    requestLoad(location)
    appendUnresolved(result, source, "no-link", nil, itemID)
    return nil
  end

  if not canNormalize(link, itemID) then
    requestLoad(location)
    appendUnresolved(result, source, "pending-item-data", link, itemID)
    return nil
  end

  local cache = Evaluation.NormalizedItemCache
  local function normalize(candidateLink, candidateSource, normalizeOpts)
    return Evaluation.CandidateNormalizer.FromLink(candidateLink, candidateSource, normalizeOpts)
  end
  local candidate, normalizeReason
  local normalizeToken = perf and perf:Start("Normalization")
  if cache and cache.Get then
    candidate, normalizeReason = cache.Get(source.guid, link, source, normalize, { perf = perf })
  else
    candidate, normalizeReason = normalize(link, source, { perf = perf })
  end
  if perf then perf:Stop(normalizeToken) end
  if not candidate then
    requestLoad(location)
    appendUnresolved(result, source, normalizeReason or "pending-item-data", link, itemID)
    return nil
  end
  if perf then perf:Add("inventory.equipment_candidates_discovered", 1) end
  result.candidates[#result.candidates + 1] = candidate
  return candidate
end

local function equipmentLocation(slotID)
  if type(ItemLocation) == "table" and type(ItemLocation.CreateFromEquipmentSlot) == "function" then
    return ItemLocation:CreateFromEquipmentSlot(slotID)
  end
  return slotID
end

local function bagLocation(bag, slot)
  if type(ItemLocation) == "table" and type(ItemLocation.CreateFromBagAndSlot) == "function" then
    return ItemLocation:CreateFromBagAndSlot(bag, slot)
  end
  return { bagID = bag, slotIndex = slot }
end

function CandidateCollector.Collect(opts)
  opts = opts or {}
  local slots = opts.slots or DEFAULT_SLOTS
  local result = { candidates = {}, equippedBySlot = {}, pending = false, unresolved = {}, perf = opts.perf }
  local perf = opts.perf
  if Evaluation.NormalizedItemCache and Evaluation.NormalizedItemCache.BeginScan then
    Evaluation.NormalizedItemCache.BeginScan()
  end

  for _, slotID in ipairs(slots) do
    if perf then perf:Add("inventory.locations_scanned", 1) end
    local loc = equipmentLocation(slotID)
    if locationHasItem(loc) and perf then perf:Add("inventory.occupied_locations", 1) end
    local candidate = collectLocation(result, loc, {
      kind = "equipped",
      slot = slotID,
      loc = loc,
      physicalID = "equip:" .. tostring(slotID),
    })
    if candidate then result.equippedBySlot[slotID] = candidate end
  end

  if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
    for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
      local count = C_Container.GetContainerNumSlots(bag) or 0
      for slot = 1, count do
        if perf then perf:Add("inventory.locations_scanned", 1) end
        local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot) or nil
        if info and info.itemID then
          if perf then perf:Add("inventory.occupied_locations", 1) end
          if couldBeSupportedEquipment(info.itemID, info.hyperlink) then
            local loc = bagLocation(bag, slot)
            collectLocation(result, loc, {
              kind = "bag",
              bag = bag,
              slot = slot,
              loc = loc,
              itemID = info.itemID,
              physicalID = "bag:" .. tostring(bag) .. ":" .. tostring(slot),
            })
          end
        end
      end
    end
  end

  result.perf = nil
  return result
end
