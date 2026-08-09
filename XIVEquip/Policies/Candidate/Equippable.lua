-- Policies/Candidate/Equippable.lua
local addonName, XIVEquip = ...

XIVEquip:RegisterPolicy({
  id = "XIVEquip.candidate_equippable",
  phase = "candidate",
  apply = function(candidate)
    if not (candidate and candidate.link) then return nil end
    if C_Item and type(C_Item.IsEquippableItem) == "function" then
      local ok, equippable = pcall(C_Item.IsEquippableItem, candidate.link)
      if ok and equippable == false then
        return { allow = false, reason = "not-equippable" }
      end
    end
    return nil
  end,
})

