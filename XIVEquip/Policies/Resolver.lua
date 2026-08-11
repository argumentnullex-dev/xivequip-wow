-- Policies/Resolver.lua
-- Startup finalization (doc section 15.9): validate, reject duplicate ids,
-- validate requires/provides, detect dependency cycles, resolve
-- deterministic order, partition by phase, freeze. Runs once at startup --
-- never during evaluation (15.10).
local addonName, XIVEquip = ...
XIVEquip.Policies = XIVEquip.Policies or {}
local Policies = XIVEquip.Policies

local Resolver = {}
Policies.Resolver = Resolver

-- Fixed phase order (doc section 4's pipeline: context is built, then
-- candidates are evaluated, then assignments, then loadout-level policies,
-- then preference ranking). A requires token satisfied by an earlier phase
-- needs no intra-phase ordering edge -- the phase boundary itself guarantees
-- the order.
Resolver.PHASES = { "evaluation_context", "candidate", "assignment", "loadout", "preference" }

local ALL_GROUPS_CACHE_KEY = "\0all"

local function policyAppliesToGroup(policy, groupId)
  if not policy.groups then return true end
  if groupId == nil then return false end
  for _, g in ipairs(policy.groups) do
    if g == groupId then return true end
  end
  return false
end

local function cacheCounter(context, field)
  local caches = context and context.caches
  if type(caches) ~= "table" then return end
  caches.policyResolutionStats = caches.policyResolutionStats or { hits = 0, misses = 0 }
  caches.policyResolutionStats[field] = (caches.policyResolutionStats[field] or 0) + 1
end

-- Rejects anything that isn't a clean 1..N array of strings -- see
-- Policies/Registry.lua's identical check for why ipairs alone isn't
-- enough (it silently tolerates non-array keys and holes).
local function isStringArray(value)
  if value == nil then return true end
  if type(value) ~= "table" then return false end

  local count = 0
  for _ in pairs(value) do count = count + 1 end

  for i = 1, count do
    if type(value[i]) ~= "string" then return false end
  end

  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key > count or key % 1 ~= 0 then
      return false
    end
  end

  return true
end

local function validateDeclaration(decl)
  if type(decl) ~= "table" then return "declaration is not a table" end
  if type(decl.id) ~= "string" or decl.id == "" then return "declaration has no valid id" end
  if type(decl.phase) ~= "string" then return "policy '" .. tostring(decl.id) .. "' has no valid phase" end
  local knownPhase = false
  for _, phase in ipairs(Resolver.PHASES) do
    if phase == decl.phase then knownPhase = true end
  end
  if not knownPhase then return "policy '" .. decl.id .. "' has unknown phase '" .. tostring(decl.phase) .. "'" end
  if type(decl.apply) ~= "function" then return "policy '" .. decl.id .. "' has no apply function" end
  if not isStringArray(decl.requires) then return "policy '" .. decl.id .. "': requires must be an array of strings" end
  if not isStringArray(decl.provides) then return "policy '" .. decl.id .. "': provides must be an array of strings" end
  -- `groups` scopes an assignment-phase policy to specific
  -- Assignments.Groups ids (Assignments/Paired.lua's assignmentPoliciesFor).
  -- It's registered as ordinary declaration metadata (Registry.lua does a
  -- redundant-but-cheap check of its own at registration time, same as
  -- requires/provides), but this is the authoritative, centralized check:
  -- a bare string would break `ipairs(policy.groups)` at evaluation time,
  -- and a map shape would silently iterate zero entries instead of
  -- failing -- exactly the kind of malformed-but-not-obviously-wrong
  -- declaration that must be caught here, once, at startup, not
  -- discovered later during actual equipment evaluation.
  if not isStringArray(decl.groups) then return "policy '" .. decl.id .. "': groups must be an array of strings" end
  return nil
end

-- Freeze(source) -> source, made read-only in place.
--
-- This addon's .toc targets Interface 120100 (retail 12.x), which added
-- native table.freeze() -- it marks the table itself read-only at the VM
-- level and returns the same reference, so `#`, pairs, ipairs, and direct
-- indexing all keep working completely normally; only writes raise. That's
-- a strictly better fit here than a hand-rolled metatable proxy (which
-- this function used to be): a proxy's raw backing table is always empty,
-- so `pairs()` over it silently iterates zero entries -- exactly the kind
-- of subtle breakage this policy array/EvaluationContext, as a public,
-- long-lived contract, shouldn't carry. table.freeze doesn't have that
-- problem because it doesn't proxy anything.
--
-- This repo's plain-Lua test runner has no WoW client and therefore no
-- native table.freeze -- tests/runner.lua installs a same-named polyfill
-- before any spec loads (see the comment there for its known limitations),
-- so production code here can simply call the real API name unconditionally.
function Resolver.Freeze(source)
  return table.freeze(source)
end

function Resolver.IsActive(policy, context)
  if not policy or type(policy.isActive) ~= "function" then return true end
  return policy.isActive(context) ~= false
end

local function groupMatches(policy, groupId)
  return policyAppliesToGroup(policy, groupId)
end

-- ActiveForPhase(context, phase, groupId) -> ordered active policies
-- EvaluationContext is immutable after the evaluation-context phase has
-- completed; only context.caches is mutable. That makes policy activation
-- stable for the lifetime of one planning operation, so scoped/active
-- policy arrays can be prepared once per phase/group and reused by the hot
-- candidate, assignment, loadout, and preference loops.
function Resolver.ActiveForPhase(context, phase, groupId)
  local all = (context and context.policies and context.policies[phase]) or {}
  local caches = context and context.caches
  local groupKey = groupId == nil and ALL_GROUPS_CACHE_KEY or tostring(groupId)

  if type(caches) == "table" then
    caches.activePolicies = caches.activePolicies or {}
    caches.activePolicies[phase] = caches.activePolicies[phase] or {}
    local cached = caches.activePolicies[phase][groupKey]
    if cached then
      cacheCounter(context, "hits")
      return cached
    end
  end

  cacheCounter(context, "misses")
  local active = {}
  for _, policy in ipairs(all) do
    if groupMatches(policy, groupId) and Resolver.IsActive(policy, context) then
      active[#active + 1] = policy
    end
  end

  if type(caches) == "table" then
    caches.activePolicies[phase][groupKey] = active
  end
  return active
end

-- topoSortPhase(decls, satisfiedBeforePhase) -> orderedDecls
-- decls: declarations belonging to exactly one phase, in registration order.
-- satisfiedBeforePhase: set of requires-tokens already provided by an
-- earlier phase (or by the caller's knownProvides) -- these need no
-- intra-phase ordering edge.
-- Raises on a requires-token satisfied by nothing (this phase or earlier),
-- or on a dependency cycle within the phase.
local function topoSortPhase(decls, satisfiedBeforePhase)
  local providesIndex = {} -- token -> array of provider ids
  for _, decl in ipairs(decls) do
    for _, token in ipairs(decl.provides or {}) do
      providesIndex[token] = providesIndex[token] or {}
      table.insert(providesIndex[token], decl.id)
    end
  end

  local byId = {}
  for _, decl in ipairs(decls) do byId[decl.id] = decl end

  -- At most one "transformer" (a declaration that both requires and
  -- provides the same token -- the override pattern DualWieldOverride
  -- uses) is supported per token. Two transformers of the same token have
  -- no way to establish who runs first without either arbitrary
  -- registration-order tie-breaking (making the result depend on
  -- incidental registration order, which is exactly what this resolver
  -- exists to avoid) or new priority metadata (which doc section 5.3
  -- explicitly disfavors: "preferable to hidden order dependencies or
  -- arbitrary numeric priorities"). This is caught here, up front, with a
  -- specific and actionable message -- letting it fall through to the
  -- general topological sort below would instead surface as an opaque
  -- dependency-cycle error, since two mutual transformers of one token
  -- always form a 2-node cycle (A needs to run after B's transform, B
  -- needs to run after A's). A second transformer of the same value
  -- should require the first transformer's own distinct output token
  -- instead of re-declaring the same one -- see DualWieldOverride.lua.
  local transformerOf = {}
  for _, decl in ipairs(decls) do
    local providesSet = {}
    for _, token in ipairs(decl.provides or {}) do providesSet[token] = true end
    for _, token in ipairs(decl.requires or {}) do
      if providesSet[token] then
        if transformerOf[token] then
          error("policies '" .. transformerOf[token] .. "' and '" .. decl.id ..
            "' both require and provide '" .. token .. "' with no order defined between them -- " ..
            "at most one same-phase transformer of a token is supported; have the later one require " ..
            "the earlier transformer's own distinct output token instead of re-using '" .. token .. "'", 0)
        end
        transformerOf[token] = decl.id
      end
    end
  end

  -- inDegree/dependents build the Kahn's-algorithm graph. An edge runs from
  -- a same-phase provider to whatever requires its token.
  local inDegree = {}
  local dependents = {}
  for _, decl in ipairs(decls) do
    inDegree[decl.id] = 0
    dependents[decl.id] = {}
  end

  for _, decl in ipairs(decls) do
    for _, token in ipairs(decl.requires or {}) do
      local providers = providesIndex[token]
      -- A declaration providing the very token it also requires doesn't
      -- count as satisfying itself (that's a self-edge, which we skip
      -- rather than add) -- otherwise a lone `{requires={"x"},
      -- provides={"x"}}` policy with no other provider anywhere would
      -- pass validation while `apply` still runs with "x" never having
      -- actually been set by anything.
      local hasExternalProvider = false
      if providers then
        for _, providerId in ipairs(providers) do
          if providerId ~= decl.id then
            hasExternalProvider = true
            table.insert(dependents[providerId], decl.id)
            inDegree[decl.id] = inDegree[decl.id] + 1
          end
        end
      end
      if not hasExternalProvider and not satisfiedBeforePhase[token] then
        error("policy '" .. decl.id .. "' requires '" .. token .. "', but no other policy (in this phase or an earlier one) provides it", 0)
      end
    end
  end

  -- Kahn's algorithm with a FIFO ready queue: nodes with no remaining
  -- dependency start in original registration order, and a node newly
  -- unblocked by processing an earlier one is appended to the end of the
  -- queue, not re-sorted back to its own original index. The result is
  -- still fully deterministic for a given input (insertion order into the
  -- queue is entirely determined by registration order + the dependency
  -- graph), but it is *not* "always pick the lowest original-registration-
  -- index ready node globally" -- a node that becomes ready later can run
  -- before one with a lower original index that was already ready.
  local ready = {}
  for _, decl in ipairs(decls) do
    if inDegree[decl.id] == 0 then table.insert(ready, decl.id) end
  end

  local ordered = {}
  local remaining = #decls
  while #ready > 0 do
    local id = table.remove(ready, 1)
    table.insert(ordered, byId[id])
    remaining = remaining - 1
    for _, dependentId in ipairs(dependents[id]) do
      inDegree[dependentId] = inDegree[dependentId] - 1
      if inDegree[dependentId] == 0 then table.insert(ready, dependentId) end
    end
  end

  if remaining > 0 then
    local cycleIds = {}
    for _, decl in ipairs(decls) do
      if inDegree[decl.id] > 0 then table.insert(cycleIds, decl.id) end
    end
    table.sort(cycleIds)
    error("dependency cycle detected among policies: " .. table.concat(cycleIds, ", "), 0)
  end

  return ordered
end

-- Finalize(pending, knownProvides) -> resolved
-- pending: array of declarations (e.g. registry:Pending()).
-- knownProvides: optional array of requires-tokens considered satisfied
-- before any phase runs (bootstrap-provided facts that aren't produced by
-- any registered policy). Defaults to none.
-- Returns { evaluation_context = frozenArray, candidate = ..., assignment = ..., loadout = ..., preference = ... }.
function Resolver.Finalize(pending, knownProvides)
  pending = pending or {}

  local seenIds = {}
  local byPhase = {}
  for _, phase in ipairs(Resolver.PHASES) do byPhase[phase] = {} end

  for _, decl in ipairs(pending) do
    local err = validateDeclaration(decl)
    if err then error(err, 0) end
    if seenIds[decl.id] then
      error("duplicate policy id '" .. decl.id .. "'", 0)
    end
    seenIds[decl.id] = true
    table.insert(byPhase[decl.phase], decl)
  end

  local satisfied = {}
  for _, token in ipairs(knownProvides or {}) do satisfied[token] = true end

  local resolved = {}
  for _, phase in ipairs(Resolver.PHASES) do
    local ordered = topoSortPhase(byPhase[phase], satisfied)
    resolved[phase] = Resolver.Freeze(ordered)
    for _, decl in ipairs(ordered) do
      for _, token in ipairs(decl.provides or {}) do
        satisfied[token] = true
      end
    end
  end

  return resolved
end
