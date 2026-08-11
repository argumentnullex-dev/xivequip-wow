-- Captures profile-backed preferences once for an evaluation pass. Policies
-- consume this snapshot rather than reading SavedVariables while scoring.
local addonName, XIVEquip = ...

XIVEquip:RegisterPolicy({
  id = "XIVEquip.profile_preferences",
  phase = "evaluation_context",
  requires = { "character.class_file", "character.spec_id" },
  provides = { "profile.preferences" },
  apply = function(builder, runtime)
    local Profiles = XIVEquip.Profiles and XIVEquip.Profiles.Config
    local specID = builder:Get("specID")
    local profile = Profiles and specID and Profiles.GetForSpec(specID, runtime) or nil
    local preferences = Profiles and Profiles.GetSpecPreferences
        and Profiles.GetSpecPreferences(profile, specID)
        or { preferSetBonuses = false, wishlist = {}, avoidlist = {} }
    builder:Set("profilePreferences", preferences)
  end,
})
