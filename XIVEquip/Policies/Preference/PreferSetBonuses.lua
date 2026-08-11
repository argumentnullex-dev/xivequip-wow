-- A general, deliberately data-free set preference. Every completed pair
-- of pieces adds 5% to each selected item's own score (2pc = 5%, 4pc =
-- 10%). Spec-specific theorycraft set valuations can later layer on top of
-- this without changing the player's preference semantics.
local addonName, XIVEquip = ...

local function setBonusPercent(setCounts, setID)
  local count = tonumber(setCounts and setCounts["set:" .. tostring(setID)]) or 0
  return math.floor(count / 2) * 0.05
end

XIVEquip:RegisterPolicy({
  id = "XIVEquip.prefer_set_bonuses",
  phase = "preference",
  requires = { "profile.preferences" },
  apply = function(loadout, context)
    local preferences = context and context.profilePreferences
    if not (preferences and preferences.preferSetBonuses) then return nil end

    local adjustment = 0
    for _, assignment in pairs((loadout and loadout.assignments) or {}) do
      for role, candidate in pairs(assignment.picks or {}) do
        local setID = candidate and tonumber(candidate.setID)
        if setID and setID > 0 then
          local score = tonumber(assignment.scores and assignment.scores[role]) or 0
          adjustment = adjustment + (score * setBonusPercent(loadout.summaries and loadout.summaries.setCounts, setID))
        end
      end
    end
    if adjustment ~= 0 then return { preferenceAdjustment = adjustment } end
    return nil
  end,
})
