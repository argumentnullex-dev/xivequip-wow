-- Evaluation/ContextBuilder.lua
-- Assembles an EvaluationContext from the resolved evaluation_context
-- policy phase (doc section 5.1): a small immutable snapshot for one
-- evaluation pass, built entirely by policies rather than a central
-- factory hard-coding every capability XIVEquip knows about.
local addonName, XIVEquip = ...
XIVEquip.Evaluation = XIVEquip.Evaluation or {}
local Evaluation = XIVEquip.Evaluation

local ContextBuilder = {}
Evaluation.ContextBuilder = ContextBuilder

local Methods = {}
local BuilderMT = { __index = Methods }

-- New(runtime) -> builder. `runtime` is whatever bootstrap services context
-- policies need (character/spec lookups, live capability checks, weights
-- resolution) -- injected so this is testable without the real WoW client,
-- mirroring the adapter pattern XIVWeights.Providers.Pawn already uses.
function ContextBuilder.New(runtime)
  return setmetatable({ runtime = runtime, fields = {}, capabilities = {} }, BuilderMT)
end

function Methods:Set(field, value)
  self.fields[field] = value
end

function Methods:Get(field)
  return self.fields[field]
end

function Methods:SetCapability(name, value)
  self.capabilities[name] = value
end

function Methods:GetCapability(name)
  return self.capabilities[name]
end

-- Build() -> plain (not yet frozen) context table combining every field a
-- context policy has staged plus the capabilities sub-table (doc 5.2).
function Methods:Build()
  local context = { capabilities = {} }
  for field, value in pairs(self.fields) do
    context[field] = value
  end
  for name, value in pairs(self.capabilities) do
    context.capabilities[name] = value
  end
  return context
end

-- BuildContext(resolved, runtime) -> immutable EvaluationContext
-- `resolved` is Policies.Resolver.Finalize's full return value (all five
-- phase arrays) -- the evaluation_context phase runs now to build the
-- context; the other four are attached to context.policies so downstream
-- pipeline stages (candidate evaluation, assignment, loadout, preference --
-- Phase 3+) can iterate them without re-touching the registry (doc 15.10:
-- no policy discovery/resolution in the hot path, only iteration).
function ContextBuilder.BuildContext(resolved, runtime)
  local builder = ContextBuilder.New(runtime)

  for _, policy in ipairs(resolved.evaluation_context) do
    policy.apply(builder, runtime)
  end

  local context = builder:Build()
  context.policies = XIVEquip.Policies.Resolver.Freeze({
    candidate = resolved.candidate,
    assignment = resolved.assignment,
    loadout = resolved.loadout,
    preference = resolved.preference,
  })
  context.capabilities = XIVEquip.Policies.Resolver.Freeze(context.capabilities)
  -- caches is deliberately left mutable -- that's what a cache is for.
  -- weights is left as whatever the resolved scale is: immutability there
  -- belongs to the XIVWeights.Scale contract (Phase 1), not something to
  -- special-case here.
  context.caches = {}

  -- Freeze the outer context, and separately the two structural children
  -- above that matter for the "immutable EvaluationContext" contract
  -- (doc 5.1/5.6): the phase arrays under context.policies were already
  -- frozen individually by Resolver.Finalize, but the *wrapper* table
  -- grouping them, and context.capabilities, were still plain, freshly
  -- built tables here -- freezing only the outer context left both of
  -- them swappable/mutable in place (context.policies.candidate = {},
  -- context.capabilities["x"] = false) despite the outer table being read-only.
  return XIVEquip.Policies.Resolver.Freeze(context)
end
