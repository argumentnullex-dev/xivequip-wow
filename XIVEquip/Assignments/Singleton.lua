-- Assignments/Singleton.lua
-- Generic one-slot assignment frontier for ordinary equipment slots. Slot
-- differences come from context/policies and data, not per-slot modules.
local addonName, XIVEquip = ...
XIVEquip.Assignments = XIVEquip.Assignments or {}
local Assignments = XIVEquip.Assignments

local Singleton = {}
Assignments.Singleton = Singleton

local Frontier = Assignments.Frontier

local function evaluateCandidate(candidate, spec)
  if not candidate then
    return {
      eligible = true,
      score = 0,
      baseScore = 0,
      scoreAdjustment = 0,
      setCounts = {},
      targetFlags = {},
      requiredFlags = {},
      reasons = {},
    }
  end
  return XIVEquip.Evaluation.CandidateEvaluator.Evaluate(candidate, spec.context, {
    groupId = spec.groupId,
    role = "slot",
    slot = spec.slot,
    currentCandidate = spec.current,
    currentByRole = { slot = spec.current },
    currentBySlot = { [spec.slot] = spec.current },
    score = spec.score and function(c, context) return spec.score(c, context, spec.slot, "slot") end or nil,
  })
end

local function mergeNumericMap(target, source)
  if type(source) ~= "table" then return end
  for key, value in pairs(source) do
    if type(value) == "number" then target[key] = (target[key] or 0) + value end
  end
end

local function mergeFlags(target, source)
  if type(source) ~= "table" then return end
  for key, value in pairs(source) do
    if value then target[key] = true end
  end
end

local function appendAll(target, source)
  if type(source) ~= "table" then return end
  for _, value in ipairs(source) do target[#target + 1] = value end
end

function Singleton.Evaluate(spec)
  local candidate = spec.pick
  local eval = evaluateCandidate(candidate, spec)
  local isCurrent = candidate == spec.current
  if eval.eligible == false and not isCurrent then return nil end

  local additions = {}
  if candidate then additions[#additions + 1] = candidate end
  if not spec.loadoutState:CheckAssignment(additions, spec.allSlots or { spec.slot }) then
    return nil
  end

  local assignment = {
    groupId = spec.groupId,
    picks = { slot = candidate },
    scores = { slot = eval.score or 0 },
    score = eval.score or 0,
    filledCount = candidate and 1 or 0,
    baseScore = eval.baseScore or 0,
    scoreAdjustment = eval.scoreAdjustment or 0,
    policyValid = eval.eligible ~= false,
    setCounts = {},
    targetFlags = {},
    requiredFlags = {},
    reasons = {},
  }
  mergeNumericMap(assignment.setCounts, eval.setCounts)
  mergeFlags(assignment.targetFlags, eval.targetFlags)
  mergeFlags(assignment.requiredFlags, eval.requiredFlags)
  appendAll(assignment.reasons, eval.reasons)
  return assignment
end

function Singleton.Frontier(spec)
  local all = {}
  local seenCurrent = false

  for _, candidate in ipairs(spec.candidates or {}) do
    if candidate == spec.current then seenCurrent = true end
    local assignment = Singleton.Evaluate({
      groupId = spec.groupId,
      slot = spec.slot,
      pick = candidate,
      current = spec.current,
      context = spec.context,
      loadoutState = spec.loadoutState,
      allSlots = spec.allSlots,
      score = spec.score,
    })
    if assignment then all[#all + 1] = assignment end
  end

  if spec.current and not seenCurrent then
    local currentAssignment = Singleton.Evaluate({
      groupId = spec.groupId,
      slot = spec.slot,
      pick = spec.current,
      current = spec.current,
      context = spec.context,
      loadoutState = spec.loadoutState,
      allSlots = spec.allSlots,
      score = spec.score,
    })
    if currentAssignment then all[#all + 1] = currentAssignment end
  elseif not spec.current then
    local emptyAssignment = Singleton.Evaluate({
      groupId = spec.groupId,
      slot = spec.slot,
      pick = nil,
      current = nil,
      context = spec.context,
      loadoutState = spec.loadoutState,
      allSlots = spec.allSlots,
      score = spec.score,
    })
    if emptyAssignment then all[#all + 1] = emptyAssignment end
  end

  return Frontier.Prune(all)
end
