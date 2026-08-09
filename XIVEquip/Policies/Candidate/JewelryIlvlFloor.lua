-- Policies/Candidate/JewelryIlvlFloor.lua
local addonName, XIVEquip = ...

local JEWELRY_SLOTS = { [2] = true, [11] = true, [12] = true, [13] = true, [14] = true, [15] = true }

XIVEquip:RegisterPolicy({
  id = "XIVEquip.jewelry_ilvl_floor",
  phase = "candidate",
  groups = { "neck", "back", "rings", "trinkets" },
  apply = function(candidate, _, policyContext)
    local slot = policyContext and policyContext.slot
    if not JEWELRY_SLOTS[slot] then return nil end
    local current = policyContext and policyContext.currentCandidate
    if not (candidate and current) then return nil end
    if candidate.source and candidate.source.kind ~= "bag" then return nil end

    local ilvl = candidate.itemLevel
    local currentIlvl = current.itemLevel or 0
    if type(ilvl) == "number" and (ilvl == 1 or ilvl >= (currentIlvl - 80)) then
      return nil
    end
    return { allow = false, reason = "below-current-jewelry-ilvl-floor" }
  end,
})

