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

local MAX_SET_PIECES = 4

local function eachAssignmentSetPiece(assignment, visitor)
  for role, candidate in pairs((assignment and assignment.picks) or {}) do
    local setID = candidate and tonumber(candidate.setID)
    if setID and setID > 0 then
      local score = tonumber(assignment.scores and assignment.scores[role]) or 0
      visitor("set:" .. tostring(setID), score)
    end
  end
end

local function insertTopScore(scores, value)
  -- A negative policy adjustment can never improve a branch. Clamping it
  -- to zero is deliberately optimistic, which keeps this a safe bound.
  value = math.max(tonumber(value) or 0, 0)
  local inserted = false
  for i = 1, #scores do
    if value > scores[i] then
      table.insert(scores, i, value)
      inserted = true
      break
    end
  end
  if not inserted then scores[#scores + 1] = value end
  if #scores > MAX_SET_PIECES then scores[#scores] = nil end
end

local function copyScores(source)
  local result = {}
  for i = 1, math.min(#(source or {}), MAX_SET_PIECES) do result[i] = source[i] end
  return result
end

local function mergeTopScores(left, right)
  local result = copyScores(left)
  for _, score in ipairs(right or {}) do insertTopScore(result, score) end
  return result
end

local function assignmentPotentialBySet(assignment)
  local bySet = {}
  eachAssignmentSetPiece(assignment, function(key, score)
    local entry = bySet[key]
    if not entry then
      entry = { count = 0, scores = {} }
      bySet[key] = entry
    end
    entry.count = entry.count + 1
    insertTopScore(entry.scores, score)
  end)
  return bySet
end

local function groupPotentialBySet(group)
  local bySet = {}
  for _, assignment in ipairs((group and group.frontier) or {}) do
    for key, potential in pairs(assignmentPotentialBySet(assignment)) do
      local entry = bySet[key]
      if not entry then
        entry = { count = 0, scores = {} }
        bySet[key] = entry
      end
      entry.count = math.max(entry.count, potential.count)
      -- Rank-wise maxima may combine mutually exclusive assignments from
      -- this group. That can only overestimate, which is safe and much
      -- tighter than treating every remaining set piece as a possible 4pc.
      for i = 1, MAX_SET_PIECES do
        entry.scores[i] = math.max(entry.scores[i] or 0, potential.scores[i] or 0)
      end
      while #entry.scores > entry.count do entry.scores[#entry.scores] = nil end
    end
  end
  return bySet
end

local function copyPotentialMap(source)
  local result = {}
  for key, potential in pairs(source or {}) do
    result[key] = { count = potential.count, scores = copyScores(potential.scores) }
  end
  return result
end

local function prepareSearch(orderedGroups)
  local suffix = {}
  suffix[#orderedGroups + 1] = {}
  for index = #orderedGroups, 1, -1 do
    local current = copyPotentialMap(suffix[index + 1])
    for key, groupPotential in pairs(groupPotentialBySet(orderedGroups[index])) do
      local entry = current[key]
      if not entry then
        entry = { count = 0, scores = {} }
        current[key] = entry
      end
      entry.count = entry.count + groupPotential.count
      entry.scores = mergeTopScores(entry.scores, groupPotential.scores)
    end
    suffix[index] = current
  end
  return { suffix = suffix }
end

local function createSearchState()
  return { sets = {}, seen = {}, generation = 0 }
end

local function pushSearchState(state, assignment)
  local undo, touched
  for role, candidate in pairs((assignment and assignment.picks) or {}) do
    local setID = candidate and tonumber(candidate.setID)
    if setID and setID > 0 then
      local key = "set:" .. tostring(setID)
      local score = tonumber(assignment.scores and assignment.scores[role]) or 0
      if not undo then undo, touched = {}, {} end
      local entry = state.sets[key]
      if not touched[key] then
        undo[#undo + 1] = {
          key = key,
          existed = entry ~= nil,
          count = entry and entry.count or 0,
          top = entry and copyScores(entry.top) or {},
        }
        touched[key] = true
      end
      if not entry then
        entry = { count = 0, top = {} }
        state.sets[key] = entry
      end
      entry.count = entry.count + 1
      insertTopScore(entry.top, score)
    end
  end
  return undo
end

local function popSearchState(state, undo)
  for i = #(undo or {}), 1, -1 do
    local saved = undo[i]
    if saved.existed then
      local entry = state.sets[saved.key]
      entry.count = saved.count
      entry.top = saved.top
    else
      state.sets[saved.key] = nil
    end
  end
end

local function sumBestScores(selected, remaining, count)
  local selectedScores = (selected and selected.top) or {}
  local remainingScores = (remaining and remaining.scores) or {}
  local selectedIndex, remainingIndex, total = 1, 1, 0
  for _ = 1, count do
    local selectedScore = selectedScores[selectedIndex]
    local remainingScore = remainingScores[remainingIndex]
    if selectedScore ~= nil and (remainingScore == nil or selectedScore >= remainingScore) then
      total = total + selectedScore
      selectedIndex = selectedIndex + 1
    elseif remainingScore ~= nil then
      total = total + remainingScore
      remainingIndex = remainingIndex + 1
    end
  end
  return total
end

local function boundForSet(selected, remaining)
  local possibleCount = (selected and selected.count or 0) + (remaining and remaining.count or 0)
  if possibleCount < 2 then return 0, "zero" end
  if possibleCount < 4 then return sumBestScores(selected, remaining, 2) * 0.05, "2pc" end
  return sumBestScores(selected, remaining, 4) * 0.10, "4pc"
end

local function upperBound(state, nextIndex, prepared, context)
  local perf = context and context.perf
  if perf then perf:Add("set_bonus.bound_calls", 1) end

  local remainingBySet = (prepared and prepared.suffix and prepared.suffix[nextIndex]) or {}
  state.generation = state.generation + 1
  local generation = state.generation
  local total, evaluated = 0, 0

  local function addSet(key, selected, remaining)
    local value, kind = boundForSet(selected, remaining)
    total = total + value
    evaluated = evaluated + 1
    state.seen[key] = generation
    if perf then perf:Add("set_bonus.bound_" .. kind, 1) end
  end

  for key, selected in pairs(state.sets) do addSet(key, selected, remainingBySet[key]) end
  for key, remaining in pairs(remainingBySet) do
    if state.seen[key] ~= generation then addSet(key, nil, remaining) end
  end
  if evaluated == 0 and perf then perf:Add("set_bonus.bound_zero", 1) end
  return total
end

XIVEquip:RegisterPolicy({
  id = "XIVEquip.prefer_set_bonuses",
  phase = "preference",
  requires = { "profile.preferences" },
  summaryDimensions = { setCounts = { thresholds = { 2, 4 } } },
  isActive = isEnabled,
  optimizer = {
    prepare = prepareSearch,
    createState = createSearchState,
    push = pushSearchState,
    pop = popSearchState,
    upperBound = upperBound,
  },
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
