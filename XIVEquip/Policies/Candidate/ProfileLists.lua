-- Wishlist and Avoidlist are evaluated at candidate time: an avoided item
-- never becomes a proposed replacement. A wished item receives its ordinary
-- ten-percent bonus, with a current-gear floor so an explicit Wishlist choice
-- still works for proc/on-use items whose calculable stat score is zero.
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
      local currentScore = tonumber(policyContext and policyContext.strongestCurrentBaseScore) or 0
      local anchor = math.max(baseScore, currentScore)
      local margin = math.max(math.abs(baseScore), math.abs(currentScore)) * 0.10
      if margin <= 0 then margin = 1e-6 end
      return { scoreAdjustment = (anchor + margin) - baseScore, reason = "wishlist" }
    end
    return nil
  end,
})
