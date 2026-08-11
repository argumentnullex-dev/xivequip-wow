-- Evaluation/CandidateEvaluator.lua
-- The "universal XIVWeights candidate scorer" (doc section 17, section 35).
-- Phase 2 wired normalized candidates to XIVWeights scoring. Phase 5 expands
-- that into the first policy-aware evaluation layer: candidate policies can
-- deny an item before score makes it attractive and attach globally-relevant
-- summary state (set counts, target/required flags) that assignment
-- frontiers and the whole-loadout optimizer must preserve.
local addonName, XIVEquip = ...
XIVEquip.Evaluation = XIVEquip.Evaluation or {}
local Evaluation = XIVEquip.Evaluation

local CandidateEvaluator = {}
Evaluation.CandidateEvaluator = CandidateEvaluator

-- FeatureVector(candidate) -> XIVWeights feature vector, translating the
-- candidate's human-oriented weapon field names (doc section 6: dps,
-- minimumDamage, maximumDamage) into the weaponDps/weaponMinDamage/
-- weaponMaxDamage vocabulary XIVWeights.Scorer.Score expects. Plain stat
-- features pass through unchanged -- CandidateNormalizer already produces
-- them under their XIVWeights feature names.
function CandidateEvaluator.FeatureVector(candidate)
  local vector = {}
  for feature, amount in pairs((candidate and candidate.stats) or {}) do
    vector[feature] = amount
  end

  local weapon = (candidate and candidate.weapon) or {}
  vector.weaponDps = weapon.dps
  vector.weaponMinDamage = weapon.minimumDamage
  vector.weaponMaxDamage = weapon.maximumDamage
  vector.weaponSwingIntervalSeconds = weapon.swingIntervalSeconds

  return vector
end

-- Score(candidate, context) -> number
local function candidateKey(candidate)
  if not candidate then return "nil" end
  return candidate.guid or candidate.physicalID or tostring(candidate)
end

local function contextCaches(context)
  return context and context.caches
end

function CandidateEvaluator.Score(candidate, context)
  local caches = contextCaches(context)
  local key = candidateKey(candidate)
  if caches then
    caches.intrinsicScores = caches.intrinsicScores or {}
    if caches.intrinsicScores[key] ~= nil then
      local perf = context and context.perf
      if perf then perf:Add("evaluation.intrinsic_cache_hits", 1) end
      return caches.intrinsicScores[key]
    end
  end

  local weights = context and context.weights
  local score = XIVEquip.XIVWeights.Scorer.Score(weights, CandidateEvaluator.FeatureVector(candidate))
  if caches then
    caches.intrinsicScores[key] = score
    local perf = context and context.perf
    if perf then perf:Add("evaluation.intrinsic_computed", 1) end
  end
  return score
end

local function policiesFor(context, phase, groupId)
  local all = (context and context.policies and context.policies[phase]) or {}
  local scoped = {}
  for _, policy in ipairs(all) do
    if not policy.groups then
      scoped[#scoped + 1] = policy
    else
      for _, g in ipairs(policy.groups) do
        if g == groupId then
          scoped[#scoped + 1] = policy
          break
        end
      end
    end
  end
  return scoped
end

local function appendReason(reasons, reason)
  if type(reason) == "string" and reason ~= "" then reasons[#reasons + 1] = reason end
end

local function mergeNumericMap(target, source)
  if type(source) ~= "table" then return end
  for key, value in pairs(source) do
    if type(value) == "number" then
      target[key] = (target[key] or 0) + value
    end
  end
end

local function mergeFlags(target, source)
  if type(source) ~= "table" then return end
  for key, value in pairs(source) do
    if value then target[key] = true end
  end
end

local function shallowCopy(source)
  local out = {}
  for key, value in pairs(source or {}) do out[key] = value end
  return out
end

local function copyArray(source)
  local out = {}
  for i, value in ipairs(source or {}) do out[i] = value end
  return out
end

local function cloneEvaluation(result)
  if not result then return nil end
  return {
    candidate = result.candidate,
    eligible = result.eligible,
    baseScore = result.baseScore,
    scoreAdjustment = result.scoreAdjustment,
    score = result.score,
    reasons = copyArray(result.reasons),
    setCounts = shallowCopy(result.setCounts),
    targetFlags = shallowCopy(result.targetFlags),
    requiredFlags = shallowCopy(result.requiredFlags),
  }
end

local function currentKey(candidate)
  return candidate and candidateKey(candidate) or "empty"
end

local function placementKey(candidate, opts)
  return table.concat({
    candidateKey(candidate),
    tostring(opts.groupId or ""),
    tostring(opts.role or ""),
    tostring(opts.slot or ""),
    currentKey(opts.currentCandidate),
  }, "|")
end

local function applyPolicyResult(result, policyResult, options)
  if policyResult == false and options.canDeny then
    result.eligible = false
    appendReason(result.reasons, options.defaultReason)
    return
  end
  if type(policyResult) ~= "table" then return end

  if options.canDeny and (policyResult.allow == false or policyResult.eligible == false or policyResult.deny == true) then
    result.eligible = false
  end

  appendReason(result.reasons, policyResult.reason)
  if type(policyResult.reasons) == "table" then
    for _, reason in ipairs(policyResult.reasons) do appendReason(result.reasons, reason) end
  end

  result.scoreAdjustment = result.scoreAdjustment + (tonumber(policyResult.scoreAdjustment) or 0)
  mergeNumericMap(result.setCounts, policyResult.setCounts)
  mergeFlags(result.targetFlags, policyResult.targetFlags)
  mergeFlags(result.requiredFlags, policyResult.requiredFlags)
end

-- Evaluate(candidate, context, opts) -> result
-- opts = {
--   groupId, role, slot, currentCandidate, currentByRole, currentBySlot,
--   score = optional base scorer fn(candidate, context) -> number
-- }
--
-- Candidate-phase policies answer eligibility and may also contribute
-- structured state. Preference-phase policies intentionally do NOT run
-- here: Resolver.PHASES orders preference after loadout, so invoking them
-- from candidate evaluation would violate the public dependency contract.
function CandidateEvaluator.Evaluate(candidate, context, opts)
  opts = opts or {}
  local caches = contextCaches(context)
  local cachedKey
  if candidate and caches then
    caches.placementEvaluations = caches.placementEvaluations or {}
    cachedKey = placementKey(candidate, opts)
    local cached = caches.placementEvaluations[cachedKey]
    if cached then
      local perf = context and context.perf
      if perf then perf:Add("evaluation.placement_cache_hits", 1) end
      return cloneEvaluation(cached)
    end
  end

  local scoreCandidate = opts.score or CandidateEvaluator.Score
  local baseScore = candidate and (tonumber(scoreCandidate(candidate, context)) or 0) or 0
  local result = {
    candidate = candidate,
    eligible = true,
    baseScore = baseScore,
    scoreAdjustment = 0,
    score = baseScore,
    reasons = {},
    setCounts = {},
    targetFlags = {},
    requiredFlags = {},
  }

  local policyContext = {
    groupId = opts.groupId,
    role = opts.role,
    slot = opts.slot,
    currentCandidate = opts.currentCandidate,
    currentByRole = opts.currentByRole,
    currentBySlot = opts.currentBySlot,
    baseScore = baseScore,
  }

  for _, policy in ipairs(policiesFor(context, "candidate", opts.groupId)) do
    applyPolicyResult(result, policy.apply(candidate, context, policyContext), {
      canDeny = true,
      defaultReason = policy.id,
    })
  end

  result.score = result.baseScore + result.scoreAdjustment
  if candidate and caches and cachedKey then
    caches.placementEvaluations[cachedKey] = cloneEvaluation(result)
    local perf = context and context.perf
    if perf then perf:Add("evaluation.placement_computed", 1) end
  end
  return result
end
