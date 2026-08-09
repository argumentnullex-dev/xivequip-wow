-- Jewelry.lua
local addonName, XIVEquip = ...
local Core                = XIVEquip.Gear_Core

local J                   = {}
XIVEquip.Jewelry          = J

local playerArmorSubclass = Core.playerArmorSubclass
local tryChooseAppend     = Core.tryChooseAppend

local PAIRS               = {
  { slots = { 11, 12 }, equipLoc = "INVTYPE_FINGER" },
  { slots = { 13, 14 }, equipLoc = "INVTYPE_TRINKET" },
}

local pairedSlot          = {
  [11] = true,
  [12] = true,
  [13] = true,
  [14] = true,
}

local EMPTY_SLOT_ILVL_WINDOW = 40

local function itemIDFromLink(link)
  return Core.itemIDFromLink(link)
end

local function requestItemData(loc)
  if C_Item and C_Item.RequestLoadItemData and loc then
    pcall(C_Item.RequestLoadItemData, loc)
  end
end

local function requiredLevelOK(link, itemID)
  if type(GetItemInfo) ~= "function" then return true end
  local reqLevel = select(5, GetItemInfo(link or itemID))
  if type(reqLevel) ~= "number" then return true end
  return reqLevel <= UnitLevel("player")
end

local function uniqueInfo(itemID, link)
  return Core.GetUniqueInfo(itemID, link)
end

local function uniqueCompatible(a, b)
  if not (a and b) then return true end
  if not (a.uniqueKey and b.uniqueKey) then return true end
  if a.uniqueKey ~= b.uniqueKey then return true end
  local limit = math.min(tonumber(a.uniqueLimit) or 1, tonumber(b.uniqueLimit) or 1)
  return limit >= 2
end

local function samePhysical(a, b)
  return a and b and a.physicalID and b.physicalID and a.physicalID == b.physicalID
end

local function makeCandidate(cmp, source, loc, itemID, link, equipLoc, sourceSlot, slots, equippedBySlot)
  if not equipLoc then
    requestItemData(loc)
    return nil, true
  end
  if equipLoc ~= "INVTYPE_FINGER" and equipLoc ~= "INVTYPE_TRINKET" then return nil, false end
  if not requiredLevelOK(link, itemID) then return nil, false end

  local guid = Core.itemGUID(loc)
  local physicalID = guid or (source .. ":" .. tostring(sourceSlot or "?") .. ":" .. tostring(itemID or itemIDFromLink(link) or "?"))
  local uniqueKey, uniqueLimit = uniqueInfo(itemID, link)
  local scores = {}
  local allowed = {}
  for _, slotID in ipairs(slots) do
    scores[slotID] = Core.scoreItem(cmp, loc, slotID)
    allowed[slotID] = source ~= "bag" or Core.EvaluateSlotCandidate(slotID, equippedBySlot and equippedBySlot[slotID], {
      link = link,
      loc = loc,
      ilvl = Core.getItemLevel(link, loc),
      score = scores[slotID],
      guid = guid,
    })
  end

  return {
    source = source,
    sourceSlot = sourceSlot,
    loc = loc,
    guid = guid,
    physicalID = physicalID,
    itemID = itemID,
    link = link,
    equipLoc = equipLoc,
    ilvl = Core.getItemLevel(link, loc),
    scores = scores,
    uniqueKey = uniqueKey,
    uniqueLimit = uniqueLimit,
    allowed = allowed,
  }, false
end

local function equippedCandidate(cmp, slotID, slots)
  local equipped = Core.equippedBasics(slotID, cmp)
  if not (equipped and equipped.loc and equipped.equipLoc) then return nil, equipped, false end
  local itemID = itemIDFromLink(equipped.link)
  local c, pending = makeCandidate(cmp, "equipped", equipped.loc, itemID, equipped.link, equipped.equipLoc, slotID, slots, nil)
  return c, equipped, pending
end

local function collectPairCandidates(cmp, used, pair)
  local slots = pair.slots
  local candidates = {}
  local hadPending = false
  local equippedCandidates = {}
  local equippedBasics = {}

  for _, slotID in ipairs(slots) do
    local c, equipped, pending = equippedCandidate(cmp, slotID, slots)
    equippedCandidates[slotID] = c
    equippedBasics[slotID] = equipped
    hadPending = hadPending or pending
    if c and c.equipLoc == pair.equipLoc then table.insert(candidates, c) end
  end

  for bag = 0, NUM_BAG_SLOTS do
    local num = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, num do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local _, _, _, equipLoc = GetItemInfoInstant(info.itemID)
        if equipLoc == pair.equipLoc then
          local link = info.hyperlink or C_Container.GetContainerItemLink(bag, slot)
          local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
          local guid = Core.itemGUID(loc)
          if used and guid and used[guid] then
            -- already claimed by an earlier planner
          else
            local c, pending = makeCandidate(cmp, "bag", loc, info.itemID, link, equipLoc, bag .. ":" .. slot, slots,
              equippedBasics)
            hadPending = hadPending or pending
            if c then table.insert(candidates, c) end
          end
        elseif not equipLoc then
          hadPending = true
        end
      end
    end
  end

  return candidates, equippedCandidates, equippedBasics, hadPending
end

local EMPTY = { isEmpty = true, scores = {}, allowed = {} }

local function scoreFor(c, slotID)
  if not c or c.isEmpty then return 0 end
  return c.scores[slotID] or 0
end

local function canAssign(c, slotID)
  return c and (c.isEmpty or c.allowed[slotID] ~= false)
end

local function scoreAssignment(a, b, slotA, slotB)
  return scoreFor(a, slotA) + scoreFor(b, slotB)
end

local function filledCount(first, second)
  local n = 0
  if first and not first.isEmpty then n = n + 1 end
  if second and not second.isEmpty then n = n + 1 end
  return n
end

local function missingCount(first, second)
  local n = 0
  if not first then n = n + 1 end
  if not second then n = n + 1 end
  return n
end

local function emptySlotIlvlFloor(candidates, currentA, currentB)
  local missing = missingCount(currentA, currentB)
  if missing <= 0 then return nil end

  local levels = {}
  for _, c in ipairs(candidates or {}) do
    local ilvl = c and not c.isEmpty and tonumber(c.ilvl)
    if ilvl and ilvl > 1 then levels[#levels + 1] = ilvl end
  end

  if #levels <= missing then return nil end
  table.sort(levels, function(a, b) return a > b end)
  return levels[missing] - EMPTY_SLOT_ILVL_WINDOW
end

local function passesEmptySlotIlvlFloor(c, floor)
  if not c or c.isEmpty or not floor then return true end
  local ilvl = tonumber(c.ilvl)
  return not ilvl or ilvl == 1 or ilvl >= floor
end

local function changedCount(loadout, currentA, currentB)
  local n = 0
  if not ((loadout.first and loadout.first.isEmpty and not currentA) or samePhysical(loadout.first, currentA)) then n = n + 1 end
  if not ((loadout.second and loadout.second.isEmpty and not currentB) or samePhysical(loadout.second, currentB)) then n = n + 1 end
  return n
end

local function betterLoadout(candidate, current, currentA, currentB)
  if not current then return true end
  if candidate.filled > current.filled then return true end
  if candidate.filled < current.filled then return false end
  if candidate.score > current.score then return true end
  if candidate.score < current.score then return false end

  local candidateChanges = changedCount(candidate, currentA, currentB)
  local currentChanges = changedCount(current, currentA, currentB)
  if candidateChanges ~= currentChanges then return candidateChanges < currentChanges end

  local candidateFirst = scoreFor(candidate.first, candidate.slotA)
  local currentFirst = scoreFor(current.first, current.slotA)
  return candidateFirst > currentFirst
end

local function makePick(c, slotID)
  return {
    loc = c.loc,
    guid = c.guid,
    itemID = c.itemID,
    link = c.link,
    score = c.scores[slotID] or 0,
    ilvl = c.ilvl,
    equipLoc = c.equipLoc,
    targetSlot = slotID,
    source = c.source,
    sourceSlot = c.sourceSlot,
    uniqueKey = c.uniqueKey,
    uniqueLimit = c.uniqueLimit,
  }
end

local function appendMove(plan, changes, slotID, candidate, currentCandidate, equipped)
  if not candidate or candidate.isEmpty or samePhysical(candidate, currentCandidate) then return false end
  Core.appendPlanAndChange(plan, changes, slotID, makePick(candidate, slotID), equipped)
  return true
end

local function appendPairPlan(plan, changes, best, currentA, currentB, equippedA, equippedB)
  local slotA, slotB = best.slotA, best.slotB
  local firstMovesFromSecond = best.first and best.first.source == "equipped" and best.first.sourceSlot == slotB
  local secondMovesFromFirst = best.second and best.second.source == "equipped" and best.second.sourceSlot == slotA
  local firstChanged = not samePhysical(best.first, currentA)
  local secondChanged = not samePhysical(best.second, currentB)

  if firstMovesFromSecond and secondMovesFromFirst then
    appendMove(plan, changes, slotA, best.first, currentA, equippedA)
  elseif firstMovesFromSecond and firstChanged then
    appendMove(plan, changes, slotA, best.first, currentA, equippedA)
    appendMove(plan, changes, slotB, best.second, currentB, equippedB)
  elseif secondMovesFromFirst and secondChanged then
    appendMove(plan, changes, slotB, best.second, currentB, equippedB)
    appendMove(plan, changes, slotA, best.first, currentA, equippedA)
  else
    appendMove(plan, changes, slotA, best.first, currentA, equippedA)
    appendMove(plan, changes, slotB, best.second, currentB, equippedB)
  end
end

local function assignmentUniqueOK(used, first, second, slotA, slotB)
  local additions = {}
  if first and not first.isEmpty then table.insert(additions, first) end
  if second and not second.isEmpty then table.insert(additions, second) end
  return Core.UniqueAssignmentOK(used, additions, { slotA, slotB })
end

local function markFinalSlot(used, candidate, equipped, slotID)
  if candidate and not candidate.isEmpty then
    Core.MarkPlannedEquip(used, makePick(candidate, slotID), equipped, slotID)
  else
    Core.MarkPlannedEquip(used, nil, equipped, slotID)
  end
end

local function findBestLoadout(candidates, floor, slotA, slotB, used, currentA, currentB)
  local best = nil
  for i = 1, #candidates do
    for j = 1, #candidates do
      if i ~= j or candidates[i].isEmpty then
        local first, second = candidates[i], candidates[j]
        if (not (first.isEmpty and second.isEmpty))
            and canAssign(first, slotA)
            and canAssign(second, slotB)
            and passesEmptySlotIlvlFloor(first, floor)
            and passesEmptySlotIlvlFloor(second, floor)
            and not samePhysical(first, second)
            and uniqueCompatible(first, second)
            and assignmentUniqueOK(used, first, second, slotA, slotB)
        then
          local loadout = {
            first = first,
            second = second,
            slotA = slotA,
            slotB = slotB,
            score = scoreAssignment(first, second, slotA, slotB),
            filled = filledCount(first, second),
          }
          if betterLoadout(loadout, best, currentA, currentB) then best = loadout end
        end
      end
    end
  end
  return best
end

local function solvePair(plan, changes, cmp, used, pair)
  local EPS = 1e-6
  local slotA, slotB = pair.slots[1], pair.slots[2]
  local candidates, current, equipped, hadPending = collectPairCandidates(cmp, used, pair)
  local currentA, currentB = current[slotA], current[slotB]
  local currentFirst, currentSecond = currentA or EMPTY, currentB or EMPTY
  local currentScore = scoreAssignment(currentFirst, currentSecond, slotA, slotB)

  if not currentA or not currentB
      or not assignmentUniqueOK(used, currentFirst, currentSecond, slotA, slotB)
      or samePhysical(currentA, currentB)
  then
    currentScore = -math.huge
  end

  local ilvlFloor = emptySlotIlvlFloor(candidates, currentA, currentB)
  table.insert(candidates, EMPTY)

  local best = findBestLoadout(candidates, ilvlFloor, slotA, slotB, used, currentA, currentB)
  if ilvlFloor then
    -- The floor must never cost filled slots: it's a preference among
    -- loadouts that fill the same number of slots, not a hard filter
    -- that can leave a slot empty when a legal item is available.
    local unrestricted = findBestLoadout(candidates, nil, slotA, slotB, used, currentA, currentB)
    if unrestricted and (not best or unrestricted.filled > best.filled) then
      best = unrestricted
    end
  end

  local applied = false
  if best and best.score > currentScore + EPS then
    appendPairPlan(plan, changes, best, currentA, currentB, equipped[slotA], equipped[slotB])
    applied = true
  end

  if applied then
    markFinalSlot(used, best.first, equipped[slotA], slotA)
    markFinalSlot(used, best.second, equipped[slotB], slotB)
  end

  return hadPending
end

-- PlanBest returns (changes, pending, plan); accepts shared `used` table
-- [XIVEquip-AUTO] J:PlanBest: Helper for Gear module.
function J:PlanBest(cmp, opts, used)
  opts = opts or {}
  used = Core.EnsurePlanContext(used or {})

  local expectedArmor = playerArmorSubclass()
  local plan, changes = {}, {}
  local hadPending = false

  for _, slotID in ipairs(Core.JEWELRY_SLOTS) do
    if not pairedSlot[slotID] then
      local _, _, _, pending = tryChooseAppend(plan, changes, slotID, cmp, expectedArmor, used)
      hadPending = hadPending or pending == true
    end
  end

  for _, pair in ipairs(PAIRS) do
    hadPending = solvePair(plan, changes, cmp, used, pair) or hadPending
  end

  return changes, hadPending, plan
end
