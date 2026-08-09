-- Weapons.lua
local addonName, XIVEquip = ...
local Core = XIVEquip.Gear_Core

local W = {}
XIVEquip.Weapons = W

local MH, OH = 16, 17

local MH2H = {
  INVTYPE_2HWEAPON = true,
  INVTYPE_RANGED = true,
  INVTYPE_RANGEDRIGHT = true,
  INVTYPE_THROWN = true,
}

local MH1H = {
  INVTYPE_WEAPON = true,
  INVTYPE_WEAPONMAINHAND = true,
}

local function itemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hitem:(%d+)") or link:match("item:(%d+)"))
end

local function currentSpecID()
  local idx = GetSpecialization and GetSpecialization()
  if not idx then return nil end
  return (GetSpecializationInfo(idx))
end

local function policyForSpec()
  local class = select(2, UnitClass("player"))
  local spec = currentSpecID()
  local P = {
    allow2H = true,
    allowDualWield = false,
    allowOffhandWeapon = false,
    allowShield = false,
    allowHoldable = false,
    allowMH1H = true,
    allowTitanGrip = false,
    requireShield = false,
  }

  if class == "WARRIOR" then
    if spec == 71 then
      P.allow2H = true; P.allowMH1H = false
    elseif spec == 72 then
      P.allow2H = true; P.allowDualWield = true; P.allowOffhandWeapon = true; P.allowTitanGrip = true
    elseif spec == 73 then
      P.allow2H = false; P.allowMH1H = true; P.allowShield = true; P.requireShield = true
    end
  elseif class == "PALADIN" then
    if spec == 65 then
      P.allow2H = false; P.allowMH1H = true; P.allowShield = true; P.allowHoldable = true
    elseif spec == 66 then
      P.allow2H = false; P.allowMH1H = true; P.allowShield = true; P.requireShield = true
    elseif spec == 70 then
      P.allow2H = true; P.allowMH1H = false
    end
  elseif class == "ROGUE" or class == "DEMONHUNTER" then
    P.allow2H = false; P.allowDualWield = true; P.allowOffhandWeapon = true
  elseif class == "DEATHKNIGHT" then
    if spec == 250 then
      P.allow2H = true; P.allowMH1H = false
    elseif spec == 251 then
      P.allow2H = true; P.allowDualWield = true; P.allowOffhandWeapon = true
    elseif spec == 252 then
      P.allow2H = true; P.allowMH1H = false
    end
  elseif class == "SHAMAN" then
    if spec == 263 then
      P.allow2H = false; P.allowDualWield = true; P.allowOffhandWeapon = true
    else
      P.allow2H = true; P.allowMH1H = true; P.allowShield = true; P.allowHoldable = true
    end
  elseif class == "DRUID" then
    if spec == 103 or spec == 104 then
      P.allow2H = true; P.allowMH1H = false
    else
      P.allow2H = true; P.allowMH1H = true; P.allowHoldable = true
    end
  elseif class == "HUNTER" then
    P.allow2H = true; P.allowMH1H = false
  elseif class == "MAGE" or class == "PRIEST" or class == "WARLOCK" then
    P.allow2H = true; P.allowMH1H = true; P.allowHoldable = true
  elseif class == "MONK" then
    if spec == 269 then
      P.allow2H = true; P.allowDualWield = true; P.allowOffhandWeapon = true
    elseif spec == 268 then
      P.allow2H = true; P.allowMH1H = true
    elseif spec == 270 then
      P.allow2H = true; P.allowMH1H = true; P.allowHoldable = true
    end
  elseif class == "EVOKER" then
    P.allow2H = true; P.allowMH1H = true; P.allowHoldable = true
  end

  if IsDualWielding and IsDualWielding() then
    P.allowDualWield = true; P.allowOffhandWeapon = true
  end

  return P
end

local function is2H(equipLoc) return equipLoc and MH2H[equipLoc] == true end
local function is1H(equipLoc) return equipLoc and MH1H[equipLoc] == true end

local function canMainHand(c, P)
  if not c then return false end
  if is2H(c.equipLoc) then return P.allow2H == true end
  if is1H(c.equipLoc) then return P.allowMH1H == true end
  return false
end

local function canOffHand(c, P)
  if not c then return false end
  if is2H(c.equipLoc) then return P.allowTitanGrip == true end
  if c.equipLoc == "INVTYPE_SHIELD" then return P.allowShield == true end
  if c.equipLoc == "INVTYPE_HOLDABLE" then return P.allowHoldable == true end
  if c.equipLoc == "INVTYPE_WEAPONOFFHAND" then return P.allowOffhandWeapon == true end
  if c.equipLoc == "INVTYPE_WEAPON" then return P.allowDualWield == true end
  return false
end

local function isCandidateAllowed(itemID, link, equipLoc)
  if XIVEquip and XIVEquip.Pawn and type(XIVEquip.Pawn.IsItemTypeUnusable) == "function" then
    local bad = XIVEquip.Pawn.IsItemTypeUnusable(itemID, equipLoc)
    if bad == true then return false end
  end

  local itemInfo = link or itemID
  if C_Item and type(C_Item.IsEquippableItem) == "function" then
    local ok, canEquip = pcall(C_Item.IsEquippableItem, itemInfo)
    if ok and canEquip == false then return false end
  elseif type(IsEquippableItem) == "function" then
    local ok, canEquip = pcall(IsEquippableItem, itemInfo)
    if ok and canEquip == false then return false end
  end

  return true
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

local function loadoutLegal(P, mh, oh)
  if not canMainHand(mh, P) then return false end

  if not oh then
    if P.requireShield then return false end
    return true
  end

  if samePhysical(mh, oh) then return false end
  if not canOffHand(oh, P) then return false end
  if P.requireShield and oh.equipLoc ~= "INVTYPE_SHIELD" then return false end
  if not uniqueCompatible(mh, oh) then return false end

  if is2H(mh.equipLoc) or is2H(oh.equipLoc) then
    return P.allowTitanGrip == true
  end

  return true
end

local function requestItemData(loc)
  if C_Item and C_Item.RequestLoadItemData and loc then
    pcall(C_Item.RequestLoadItemData, loc)
  end
end

local function candidateFromLocation(cmp, source, loc, itemID, link, equipLoc, sourceSlot)
  if not equipLoc then
    requestItemData(loc)
    return nil, true
  end
  if not isCandidateAllowed(itemID, link, equipLoc) then return nil, false end
  if not requiredLevelOK(link, itemID) then return nil, false end

  local guid = Core.itemGUID(loc)
  local physicalID = guid or (source .. ":" .. tostring(sourceSlot or "?") .. ":" .. tostring(itemID or itemIDFromLink(link) or "?"))
  local uniqueKey, uniqueLimit = uniqueInfo(itemID, link)

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
    scoreMH = Core.scoreItem(cmp, loc, MH),
    scoreOH = Core.scoreItem(cmp, loc, OH),
    uniqueKey = uniqueKey,
    uniqueLimit = uniqueLimit,
  }, false
end

local function equippedCandidate(cmp, slotID)
  local equipped = Core.equippedBasics(slotID, cmp)
  if not (equipped and equipped.loc and equipped.equipLoc) then return nil, equipped, false end
  local itemID = itemIDFromLink(equipped.link)
  local c, pending = candidateFromLocation(cmp, "equipped", equipped.loc, itemID, equipped.link, equipped.equipLoc, slotID)
  return c, equipped, pending
end

local function collectCandidates(cmp, used, P)
  local candidates = {}
  local hadPending = false
  local eqMHCandidate, eqMH, pendingMH = equippedCandidate(cmp, MH)
  local eqOHCandidate, eqOH, pendingOH = equippedCandidate(cmp, OH)
  hadPending = hadPending or pendingMH or pendingOH

  if eqMHCandidate then table.insert(candidates, eqMHCandidate) end
  if eqOHCandidate then table.insert(candidates, eqOHCandidate) end

  for bag = 0, NUM_BAG_SLOTS do
    local num = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, num do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local _, _, _, equipLoc = GetItemInfoInstant(info.itemID)
        local link = info.hyperlink or C_Container.GetContainerItemLink(bag, slot)
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local guid = Core.itemGUID(loc)
        if used and guid and used[guid] then
          -- already used by an earlier planner
        else
          local c, pending = candidateFromLocation(cmp, "bag", loc, info.itemID, link, equipLoc, bag .. ":" .. slot)
          hadPending = hadPending or pending
          if c and (canMainHand(c, P) or canOffHand(c, P)) then
            table.insert(candidates, c)
          end
        end
      end
    end
  end

  return candidates, eqMHCandidate, eqOHCandidate, eqMH, eqOH, hadPending
end

local function loadoutScore(loadout)
  local score = loadout.mh.scoreMH or 0
  if loadout.oh then score = score + (loadout.oh.scoreOH or 0) end
  return score
end

local function loadoutBetter(candidate, current)
  if not current then return true end
  if candidate.score > current.score then return true end
  if candidate.score < current.score then return false end

  local candidateMH = candidate.mh and candidate.mh.scoreMH or 0
  local currentMH = current.mh and current.mh.scoreMH or 0
  if candidateMH ~= currentMH then return candidateMH > currentMH end

  local candidateOH = candidate.oh and candidate.oh.scoreOH or 0
  local currentOH = current.oh and current.oh.scoreOH or 0
  return candidateOH > currentOH
end

local function makePick(c, slotID)
  return {
    loc = c.loc,
    guid = c.guid,
    itemID = c.itemID,
    link = c.link,
    score = (slotID == MH) and c.scoreMH or c.scoreOH,
    ilvl = c.ilvl,
    equipLoc = c.equipLoc,
    targetSlot = slotID,
    source = c.source,
    sourceSlot = c.sourceSlot,
    uniqueKey = c.uniqueKey,
    uniqueLimit = c.uniqueLimit,
  }
end

local function appendIfChanged(plan, changes, slotID, candidate, currentCandidate, equipped)
  if not candidate or samePhysical(candidate, currentCandidate) then return false end
  Core.appendPlanAndChange(plan, changes, slotID, makePick(candidate, slotID), equipped)
  return true
end

function W:PlanBest(cmp, opts, used)
  opts = opts or {}
  used = Core.EnsurePlanContext(used or {})

  local plan, changes = {}, {}
  local EPS = 1e-6
  local P = policyForSpec()
  local candidates, eqMHCandidate, eqOHCandidate, eqMH, eqOH, hadPending = collectCandidates(cmp, used, P)

  local currentScore = -math.huge
  if loadoutLegal(P, eqMHCandidate, eqOHCandidate) then
    if Core.UniqueAssignmentOK(used, { eqMHCandidate, eqOHCandidate }, { MH, OH }) then
      currentScore = loadoutScore({ mh = eqMHCandidate, oh = eqOHCandidate })
    end
  elseif loadoutLegal(P, eqMHCandidate, nil)
      and Core.UniqueAssignmentOK(used, { eqMHCandidate }, { MH, OH })
  then
    currentScore = loadoutScore({ mh = eqMHCandidate, oh = nil })
  end

  local best = nil
  for _, mh in ipairs(candidates) do
    if loadoutLegal(P, mh, nil) and Core.UniqueAssignmentOK(used, { mh }, { MH, OH }) then
      local loadout = { mh = mh, oh = nil }
      loadout.score = loadoutScore(loadout)
      if loadoutBetter(loadout, best) then best = loadout end
    end
    for _, oh in ipairs(candidates) do
      if loadoutLegal(P, mh, oh) and Core.UniqueAssignmentOK(used, { mh, oh }, { MH, OH }) then
        local loadout = { mh = mh, oh = oh }
        loadout.score = loadoutScore(loadout)
        if loadoutBetter(loadout, best) then best = loadout end
      end
    end
  end

  if not best or best.score <= currentScore + EPS then
    return changes, hadPending, plan
  end

  local ohMovesFromMH = best.oh and best.oh.source == "equipped" and best.oh.sourceSlot == MH
  local ohChanged = best.oh and not samePhysical(best.oh, eqOHCandidate)

  if ohMovesFromMH and ohChanged then
    appendIfChanged(plan, changes, OH, best.oh, eqOHCandidate, eqOH)
    appendIfChanged(plan, changes, MH, best.mh, eqMHCandidate, eqMH)
  else
    appendIfChanged(plan, changes, MH, best.mh, eqMHCandidate, eqMH)
    if best.oh then appendIfChanged(plan, changes, OH, best.oh, eqOHCandidate, eqOH) end
  end

  Core.MarkPlannedEquip(used, makePick(best.mh, MH), eqMH, MH)
  if best.oh then
    Core.MarkPlannedEquip(used, makePick(best.oh, OH), eqOH, OH)
  else
    Core.MarkPlannedEquip(used, nil, eqOH, OH)
  end

  return changes, hadPending, plan
end
