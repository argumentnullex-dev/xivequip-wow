-- Policies/Candidate/SpecAppropriateTrinkets.lua
-- Opt-in eligibility filter: hides trinkets Blizzard itself does not
-- consider appropriate for the player's current specialization, trusting
-- C_Item.DoesItemContainSpec's own metadata rather than any maintained
-- role/theorycraft mapping. Off by default (see Profiles/Config.lua's
-- per-spec preferSpecAppropriateTrinkets) and scoped to the trinkets
-- assignment group only -- every other slot is unaffected.
local addonName, XIVEquip = ...

local function isEnabled(context)
  local preferences = context and context.profilePreferences
  return preferences and preferences.preferSpecAppropriateTrinkets == true
end

local function cacheFor(context)
  local caches = context and context.caches
  if type(caches) ~= "table" then return nil end
  caches.specAppropriateTrinkets = caches.specAppropriateTrinkets or {}
  return caches.specAppropriateTrinkets
end

-- Blizzard's own metadata is authoritative; a nil/failed result (API
-- unavailable, item data not yet loaded, or Blizzard itself has no opinion)
-- is deliberately treated as "appropriate" -- a false rejection is worse
-- than an occasional off-meta suggestion the player can Avoidlist.
local function isAppropriateForSpec(itemInfo, classID, specID, cache, cacheKey)
  if cache and cache[cacheKey] ~= nil then return cache[cacheKey] end

  local fn = C_Item and C_Item.DoesItemContainSpec
  local result = true
  if type(fn) == "function" then
    local ok, value = pcall(fn, itemInfo, classID, specID)
    if ok and value ~= nil then result = value end
  end

  if cache then cache[cacheKey] = result end
  return result
end

XIVEquip:RegisterPolicy({
  id = "XIVEquip.spec_appropriate_trinkets",
  phase = "candidate",
  groups = { "trinkets" },
  requires = { "character.class_id", "character.spec_id", "profile.preferences" },
  isActive = isEnabled,
  apply = function(candidate, context, policyContext)
    local itemID = candidate and tonumber(candidate.itemID)
    if not itemID then return nil end

    local preferences = context.profilePreferences or {}
    if preferences.wishlist and preferences.wishlist[itemID] then return nil end

    local classID, specID = context.classID, context.specID
    if not (classID and specID) then return nil end

    local cacheKey = tostring(classID) .. ":" .. tostring(specID) .. ":" .. tostring(itemID)
    local itemInfo = candidate.link or itemID
    if isAppropriateForSpec(itemInfo, classID, specID, cacheFor(context), cacheKey) then return nil end

    return { allow = false, reason = "not-spec-appropriate" }
  end,
})
