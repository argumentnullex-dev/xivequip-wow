-- Repeatable operation-count benchmark for Prefer Set Bonuses.
-- Usage: lua tests/benchmarks/set_bonus_optimizer.lua [repo-root] [iterations]
local root = arg[1] or "."
local iterations = tonumber(arg[2]) or 100
local sep = package.config:sub(1, 1)
if type(table.freeze) ~= "function" then table.freeze = function(value) return value end end
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local function newAddon()
  local addon = {}
  _G.XIVEquip_Settings = {}
  Bootstrap.LoadWeights(root, addon)
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  Bootstrap.LoadOptimization(root, addon)
  return addon
end

local function policyByID(policies, id)
  for _, policy in ipairs(policies or {}) do
    if policy.id == id then return policy end
  end
  error("missing policy " .. tostring(id))
end

local function assignment(score, setID, tag)
  local result = {
    score = score,
    picks = { slot = { itemID = tag, physicalID = tostring(tag), setID = setID } },
    scores = { slot = score },
  }
  if setID then result.setCounts = { ["set:" .. tostring(setID)] = 1 } end
  return result
end

local function buildGroups()
  local groups = {}
  -- Five real threshold-capable choices: four slightly lower local scores
  -- win globally once the exact 4pc preference is applied.
  for i = 1, 5 do
    groups[#groups + 1] = {
      id = "tier" .. tostring(i), slots = { i },
      frontier = {
        assignment(105, nil, "plain-tier-slot-" .. tostring(i)),
        assignment(100, 77, "set-77-slot-" .. tostring(i)),
      },
    }
  end
  -- These alternatives belong to unrelated one-piece sets. The legacy
  -- bound treated every score as a possible 10% 4pc contribution; the
  -- set-aware bound proves each one contributes exactly zero.
  for i = 6, 13 do
    groups[#groups + 1] = {
      id = "singleton" .. tostring(i), slots = { i },
      frontier = {
        assignment(100, nil, "plain-singleton-" .. tostring(i)),
        assignment(99, 1000 + i, "unreachable-set-" .. tostring(i)),
      },
    }
  end
  return groups
end

local addon = newAddon()
local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
local setPolicy = policyByID(resolved.preference, "XIVEquip.prefer_set_bonuses")
local totals, finalScore = {}, nil
local started = os.clock()

for _ = 1, iterations do
  local context = {
    profilePreferences = { preferSetBonuses = true },
    caches = {},
    policies = { loadout = {}, preference = { setPolicy } },
    perf = {
      Add = function(_, key, amount) totals[key] = (totals[key] or 0) + (amount or 1) end,
    },
  }
  local _, score = addon.Optimization.LoadoutOptimizer.FindBest(
    buildGroups(), addon.Assignments.LoadoutState.New(), context)
  finalScore = score
end

local elapsedMs = (os.clock() - started) * 1000
local function average(key) return (totals[key] or 0) / iterations end

print(string.format("iterations=%d score=%.1f average_ms=%.3f", iterations, finalScore or 0, elapsedMs / iterations))
print(string.format("nodes=%.0f leaves=%.0f policy_prunes=%.0f score_prunes=%.0f",
  average("optimizer.nodes_visited"), average("optimizer.complete_leaves"),
  average("optimizer.policy_bound_prunes"), average("optimizer.score_bound_prunes")))
print(string.format("policy_pushes=%.0f policy_pops=%.0f bound_calls=%.0f zero=%.0f 2pc=%.0f 4pc=%.0f",
  average("optimizer.policy_state_pushes"), average("optimizer.policy_state_pops"),
  average("set_bonus.bound_calls"), average("set_bonus.bound_zero"),
  average("set_bonus.bound_2pc"), average("set_bonus.bound_4pc")))
