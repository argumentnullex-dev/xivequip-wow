-- A general, deliberately data-free set preference. Every completed pair
-- of pieces adds 5% to each selected item's own score (2pc = 5%, 4pc =
-- 10%). Spec-specific theorycraft set valuations can later layer on top of
-- this without changing the player's preference semantics.
local addonName, XIVEquip = ...

local function thresholdForSet(setCounts, setID)
  local count = tonumber(setCounts and setCounts["set:" .. tostring(setID)]) or 0
  if count >= 4 then return 4, 0.10 end
  if count >= 2 then return 2, 0.05 end
  return 0, 0
end

local function isEnabled(context)
  local preferences = context and context.profilePreferences
  return preferences and preferences.preferSetBonuses == true
end

local function assignmentSetScore(assignment)
  local total = 0
  for role, candidate in pairs((assignment and assignment.picks) or {}) do
    local setID = candidate and tonumber(candidate.setID)
    if setID and setID > 0 then
      local score = tonumber(assignment.scores and assignment.scores[role]) or 0
      if score > 0 then total = total + score end
    end
  end
  return total
end

XIVEquip:RegisterPolicy({
  id = "XIVEquip.prefer_set_bonuses",
  phase = "preference",
  requires = { "profile.preferences" },
  summaryDimensions = { setCounts = { thresholds = { 2, 4 } } },
  isActive = isEnabled,
  upperBound = function(partialLoadout, remainingGroups)
    local possibleSetScore = 0
    for _, assignment in pairs((partialLoadout and partialLoadout.assignments) or {}) do
      possibleSetScore = possibleSetScore + assignmentSetScore(assignment)
    end
    for _, group in ipairs(remainingGroups or {}) do
      local best = 0
      for _, assignment in ipairs(group.frontier or {}) do
        best = math.max(best, assignmentSetScore(assignment))
      end
      possibleSetScore = possibleSetScore + best
    end
    return possibleSetScore * 0.10
  end,
  apply = function(loadout, context)
    local scoresBySet = {}
    for _, assignment in pairs((loadout and loadout.assignments) or {}) do
      for role, candidate in pairs(assignment.picks or {}) do
        local setID = candidate and tonumber(candidate.setID)
        if setID and setID > 0 then
          local score = tonumber(assignment.scores and assignment.scores[role]) or 0
          local key = "set:" .. tostring(setID)
          scoresBySet[key] = scoresBySet[key] or {}
          scoresBySet[key][#scoresBySet[key] + 1] = score
        end
      end
    end
    local adjustment = 0
    for setKey, scores in pairs(scoresBySet) do
      local setID = tostring(setKey):match("^set:(.+)$")
      local thresholdPieces, percent = thresholdForSet(loadout.summaries and loadout.summaries.setCounts, setID)
      if thresholdPieces > 0 and percent > 0 then
        table.sort(scores, function(a, b) return (tonumber(a) or 0) > (tonumber(b) or 0) end)
        for i = 1, math.min(thresholdPieces, #scores) do
          adjustment = adjustment + ((tonumber(scores[i]) or 0) * percent)
        end
      end
    end
    if adjustment ~= 0 then return { preferenceAdjustment = adjustment } end
    return nil
  end,
})
