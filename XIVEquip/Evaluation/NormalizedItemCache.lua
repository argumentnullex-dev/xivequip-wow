-- Evaluation/NormalizedItemCache.lua
-- Long-lived cache of normalized physical item facts keyed by item GUID.
local addonName, XIVEquip = ...
XIVEquip.Evaluation = XIVEquip.Evaluation or {}
local Evaluation = XIVEquip.Evaluation

local Cache = {
  generation = 0,
  entries = {},
  scansSinceGC = 0,
  gcInterval = 25,
  staleGenerations = 100,
}
Evaluation.NormalizedItemCache = Cache

local function copyMap(source)
  local out = {}
  for key, value in pairs(source or {}) do out[key] = value end
  return out
end

local function cloneCandidate(source, identity)
  if not source then return nil end
  return {
    itemID = source.itemID,
    link = identity.link or source.link,
    guid = identity.guid or source.guid,
    physicalID = identity.physicalID or source.physicalID,
    source = identity.source,
    equip = copyMap(source.equip),
    itemLevel = source.itemLevel,
    setID = source.setID,
    uniqueness = copyMap(source.uniqueness),
    stats = copyMap(source.stats),
    weapon = copyMap(source.weapon),
  }
end

function Cache.BeginScan()
  Cache.generation = Cache.generation + 1
  Cache.scansSinceGC = Cache.scansSinceGC + 1
  if Cache.scansSinceGC >= Cache.gcInterval then
    Cache.CollectGarbage()
  end
  return Cache.generation
end

function Cache.Get(guid, link, source, normalize, opts)
  source = source or {}
  opts = opts or {}
  local perf = opts.perf
  if not guid then
    if perf then perf:Add("normalization.cache_misses", 1) end
    return normalize(link, source, opts)
  end

  local entry = Cache.entries[guid]
  if entry and entry.fingerprint == link and entry.normalized then
    entry.lastSeenGeneration = Cache.generation
    if perf then perf:Add("normalization.cache_hits", 1) end
    return cloneCandidate(entry.normalized, {
      link = link,
      guid = guid,
      physicalID = source.physicalID,
      source = source,
    })
  end

  if perf then
    perf:Add(entry and "normalization.renormalized" or "normalization.cache_misses", 1)
  end
  local normalized, reason = normalize(link, source, opts)
  if not normalized then return nil, reason end

  Cache.entries[guid] = {
    fingerprint = link,
    normalized = cloneCandidate(normalized, { link = link }),
    lastSeenGeneration = Cache.generation,
  }
  return cloneCandidate(normalized, {
    link = link,
    guid = guid,
    physicalID = source.physicalID,
    source = source,
  })
end

function Cache.CollectGarbage(maxAge)
  maxAge = maxAge or Cache.staleGenerations
  local cutoff = Cache.generation - maxAge
  for guid, entry in pairs(Cache.entries) do
    if (entry.lastSeenGeneration or 0) < cutoff then
      Cache.entries[guid] = nil
    end
  end
  Cache.scansSinceGC = 0
end

function Cache.Reset()
  Cache.generation = 0
  Cache.entries = {}
  Cache.scansSinceGC = 0
end

function Cache.Size()
  local n = 0
  for _ in pairs(Cache.entries) do n = n + 1 end
  return n
end
