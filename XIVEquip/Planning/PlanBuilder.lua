-- Planning/PlanBuilder.lua
-- Converts a RecommendationResult's desired final slot assignment into the
-- existing executor's pick records. It intentionally does not perform any
-- protected action itself; Gear/Interface.lua remains responsible for
-- protected equips/cleanup, retries, verification, BoE handling, and save
-- behavior.
local addonName, XIVEquip = ...
XIVEquip.Planning = XIVEquip.Planning or {}
local Planning = XIVEquip.Planning

local PlanBuilder = {}
Planning.PlanBuilder = PlanBuilder

local OPTIMIZED_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

local function samePhysical(a, b)
  if a == b then return true end
  if not (a and b) then return false end
  if a.guid and b.guid and a.guid == b.guid then return true end
  if a.physicalID and b.physicalID and a.physicalID == b.physicalID then return true end
  return false
end

local function scoreOf(candidate, slotScores, slotID)
  local slotScore = slotScores and slotScores[slotID]
  if slotScore ~= nil then return tonumber(slotScore) or 0 end
  return tonumber(candidate and candidate.score or candidate and candidate.assignmentScore) or 0
end

local function candidateSourceSlot(candidate)
  local source = candidate and candidate.source
  if source and source.kind == "equipped" then return source.slot end
  return nil
end

local function is2H(candidate)
  local equipLoc = candidate and (candidate.equipLoc or candidate.equip and candidate.equip.equipLoc)
  return equipLoc == "INVTYPE_2HWEAPON"
      or equipLoc == "INVTYPE_RANGED"
      or equipLoc == "INVTYPE_RANGEDRIGHT"
      or equipLoc == "INVTYPE_THROWN"
end

local function candidatePick(slotID, candidate, finalSlotScores)
  local source = candidate and candidate.source or {}
  local uniqueness = candidate and candidate.uniqueness or {}
  return {
    loc = source.loc,
    itemLoc = source.loc,
    bagID = source.bag,
    slotIndex = source.slot,
    bag = source.bag,
    slot = source.slot,
    fromSlot = source.kind == "equipped" and source.slot or nil,
    targetSlot = slotID,
    link = candidate and candidate.link,
    newLink = candidate and candidate.link,
    ilvl = candidate and candidate.itemLevel,
    score = scoreOf(candidate, finalSlotScores, slotID),
    itemID = candidate and candidate.itemID,
    equipLoc = candidate and candidate.equip and candidate.equip.equipLoc,
    guid = candidate and candidate.guid,
    physicalID = candidate and candidate.physicalID,
    uniqueKey = uniqueness.key,
    uniqueLimit = uniqueness.limit,
  }
end

local function changeRow(slotID, current, candidate, pick, currentSlotScores, finalSlotScores)
  local Core = XIVEquip.Gear_Core or {}
  local oldScore = scoreOf(current, currentSlotScores, slotID)
  local newScore = scoreOf(candidate, finalSlotScores, slotID)
  local oldIlvl = tonumber(current and current.itemLevel) or 0
  local newIlvl = tonumber(candidate and candidate.itemLevel) or 0
  return {
    slot = slotID,
    slotName = (Core.SLOT_LABEL and Core.SLOT_LABEL[slotID]) or ("Slot " .. tostring(slotID)),
    oldLink = (current and current.link) or "|cff888888(None)|r",
    newLink = (candidate and candidate.link) or "|cff888888(None)|r",
    deltaScore = newScore - oldScore,
    deltaIlvl = newIlvl - oldIlvl,
    newLoc = pick and pick.loc,
    oldLoc = current and current.source and current.source.loc or nil,
  }
end

local function appendPick(plan, changes, slotID, current, candidate, currentSlotScores, finalSlotScores)
  if not candidate then return end
  local sourceSlot = candidateSourceSlot(candidate)
  if sourceSlot == slotID then return end

  local pick = candidatePick(slotID, candidate, finalSlotScores)
  plan[#plan + 1] = pick
  changes[#changes + 1] = changeRow(slotID, current, candidate, pick, currentSlotScores, finalSlotScores)
end

local function appendUnequip(plan, changes, slotID, current, currentSlotScores, finalSlotScores)
  if not current then return end
  local pick = {
    action = "unequip",
    targetSlot = slotID,
    oldLink = current.link,
  }
  plan[#plan + 1] = pick
  changes[#changes + 1] = changeRow(slotID, current, nil, pick, currentSlotScores, finalSlotScores)
end

local function planHasMainhandClear(plan)
  for _, pick in ipairs(plan or {}) do
    if pick and pick.targetSlot == 16 and is2H(pick) then return true end
  end
  return false
end

function PlanBuilder.Build(result, opts)
  opts = opts or {}
  result = result or {}
  local slots = opts.slots or result.optimizedSlots or OPTIMIZED_SLOTS
  local currentBySlot = result.equippedBySlot or result.currentSlots or {}
  local finalSlots = result.finalSlots or {}
  local currentSlotScores = result.currentSlotScores or {}
  local finalSlotScores = result.finalSlotScores or {}
  local plan, changes = {}, {}
  local covered = {}

  -- Equipment-slot moves must happen before bag equips so a displaced
  -- current item can still be moved to its desired destination.
  for _, slotID in ipairs(slots) do
    if not covered[slotID] then
      local candidate = finalSlots[slotID]
      local current = currentBySlot[slotID]
      local sourceSlot = candidateSourceSlot(candidate)
      if candidate and sourceSlot and sourceSlot ~= slotID and not samePhysical(candidate, current) then
        appendPick(plan, changes, slotID, current, candidate, currentSlotScores, finalSlotScores)
        covered[slotID] = true
        if samePhysical(finalSlots[sourceSlot], current) then
          covered[sourceSlot] = true
        end
      end
    end
  end

  for _, slotID in ipairs(slots) do
    if not covered[slotID] then
      local candidate = finalSlots[slotID]
      local current = currentBySlot[slotID]
      if candidate and not samePhysical(candidate, current) then
        appendPick(plan, changes, slotID, current, candidate, currentSlotScores, finalSlotScores)
      end
    end
  end

  if finalSlots[17] == nil and currentBySlot[17] and is2H(finalSlots[16]) and not planHasMainhandClear(plan) then
    appendUnequip(plan, changes, 17, currentBySlot[17], currentSlotScores, finalSlotScores)
  end

  return changes, result.pending == true, plan
end

return PlanBuilder
