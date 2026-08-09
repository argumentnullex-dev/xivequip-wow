-- XIVWeights/Resolver.lua
-- Effective-scale composition (doc section 13): a Provider's values always
-- win; only *supplemental* namespaces (e.g. setBonuses) may be deep-filled
-- from a class/spec default when the Provider hasn't supplied a value there.
-- Core weight namespaces are never filled from a default (13.2) -- missing
-- always means zero, never a borrowed value, so a Provider scale can't be
-- silently contaminated with another source's stat opinions.
--
-- Phase 1 has no real class/spec default content yet (that's doc phase 5)
-- -- this implements the generic algorithm so it's ready when defaults
-- exist; callers may pass a nil defaultScale today.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
local XIVWeights = XIVEquip.XIVWeights

local Resolver = {}
XIVWeights.Resolver = Resolver

-- Namespaces on a Scale that support schema-aware deep-fill from a default.
local SUPPLEMENTAL_NAMESPACES = { "setBonuses" }

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for k, v in pairs(value) do copy[k] = deepCopy(v) end
  return copy
end

-- deepFill: for every key present in `default`, fill it into `target` only
-- if `target` doesn't already have a value there (nil, not falsy -- an
-- explicit 0/false must survive untouched per doc 13.4). Recurses into
-- nested tables present on both sides so a partially-supplied structure
-- (e.g. one set threshold provided, another missing) fills correctly.
local function deepFill(target, default)
  if type(default) ~= "table" then return target end
  target = target or {}
  for key, defaultValue in pairs(default) do
    local existing = target[key]
    if existing == nil then
      target[key] = deepCopy(defaultValue)
    elseif type(existing) == "table" and type(defaultValue) == "table" then
      deepFill(existing, defaultValue)
    end
  end
  return target
end

-- Resolve(providerScale, defaultScale) -> effectiveScale
function Resolver.Resolve(providerScale, defaultScale)
  assert(providerScale, "Resolver.Resolve requires a provider scale")

  local effective = XIVWeights.NewScale({
    id = providerScale.id,
    name = providerScale.name,
    source = providerScale.source,
    weights = providerScale.weights,
    meta = providerScale.meta,
  })

  -- Provider supplemental data always carries forward, independent of
  -- whether a default exists -- "provider wins" (13.1) must hold even with
  -- no default to compose against. The default only ever fills gaps.
  for _, namespace in ipairs(SUPPLEMENTAL_NAMESPACES) do
    local merged = deepCopy(providerScale[namespace])
    if defaultScale then
      merged = deepFill(merged, defaultScale[namespace])
    end
    effective[namespace] = merged
  end

  return effective
end
