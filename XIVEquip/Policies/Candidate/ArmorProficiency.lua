-- Policies/Candidate/ArmorProficiency.lua
local addonName, XIVEquip = ...

local ARMOR_SLOTS = {
  [1] = true, [3] = true, [5] = true, [6] = true,
  [7] = true, [8] = true, [9] = true, [10] = true,
}

XIVEquip:RegisterPolicy({
  id = "XIVEquip.candidate_armor_proficiency",
  phase = "candidate",
  requires = { "character.armor_proficiency_subclass" },
  apply = function(candidate, context, policyContext)
    local slot = policyContext and policyContext.slot
    if not ARMOR_SLOTS[slot] then return nil end
    local equip = candidate and candidate.equip
    if not equip or equip.itemClassID ~= 4 then return nil end
    if equip.itemSubclassID == context.armorProficiencySubclass then return nil end
    return { allow = false, reason = "wrong-armor-proficiency" }
  end,
})

