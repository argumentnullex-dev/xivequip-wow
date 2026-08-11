-- Preserve item-set membership through frontier pruning so a later
-- whole-loadout preference policy can see whether a 2pc/4pc threshold is met.
local addonName, XIVEquip = ...

local function policyIsActive(policy, context)
  local resolver = XIVEquip.Policies and XIVEquip.Policies.Resolver
  if resolver and resolver.IsActive then return resolver.IsActive(policy, context) end
  if type(policy.isActive) ~= "function" then return true end
  return policy.isActive(context) ~= false
end

local function downstreamNeedsSetCounts(context)
  local policies = context and context.policies or {}
  for _, phase in ipairs({ "loadout", "preference" }) do
    for _, policy in ipairs(policies[phase] or {}) do
      local dimensions = policy.summaryDimensions
      if dimensions and dimensions.setCounts and policyIsActive(policy, context) then
        return true
      end
    end
  end
  return false
end

XIVEquip:RegisterPolicy({
  id = "XIVEquip.set_membership",
  phase = "candidate",
  isActive = downstreamNeedsSetCounts,
  apply = function(candidate)
    local setID = candidate and tonumber(candidate.setID)
    if not setID or setID <= 0 then return nil end
    return { setCounts = { ["set:" .. tostring(setID)] = 1 } }
  end,
})
