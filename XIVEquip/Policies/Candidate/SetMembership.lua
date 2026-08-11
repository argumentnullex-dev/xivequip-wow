-- Preserve item-set membership through frontier pruning so a later
-- whole-loadout preference policy can see whether a 2pc/4pc threshold is met.
local addonName, XIVEquip = ...

XIVEquip:RegisterPolicy({
  id = "XIVEquip.set_membership",
  phase = "candidate",
  apply = function(candidate)
    local setID = candidate and tonumber(candidate.setID)
    if not setID or setID <= 0 then return nil end
    return { setCounts = { ["set:" .. tostring(setID)] = 1 } }
  end,
})
