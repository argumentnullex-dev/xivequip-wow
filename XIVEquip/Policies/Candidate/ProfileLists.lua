-- Wishlist and Avoidlist are evaluated at candidate time: an avoided item
-- never becomes a proposed replacement, while a wished item receives a
-- transparent ten-percent bonus to its ordinary score.
local addonName, XIVEquip = ...

XIVEquip:RegisterPolicy({
  id = "XIVEquip.profile_item_lists",
  phase = "candidate",
  requires = { "profile.preferences" },
  apply = function(candidate, context, policyContext)
    local preferences = context and context.profilePreferences or {}
    local itemID = candidate and tonumber(candidate.itemID)
    if not itemID then return nil end
    if preferences.avoidlist and preferences.avoidlist[itemID] then
      return { allow = false, reason = "avoidlist" }
    end
    if preferences.wishlist and preferences.wishlist[itemID] then
      local baseScore = tonumber(policyContext and policyContext.baseScore) or 0
      return { scoreAdjustment = baseScore * 0.10, reason = "wishlist" }
    end
    return nil
  end,
})
