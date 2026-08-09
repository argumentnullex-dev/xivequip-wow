-- Assignments/LoadoutState.lua
-- Uniqueness/loadout accounting over normalized candidates (doc section
-- 20). Ports Core.EnsurePlanContext/Core.UniqueAssignmentOK/
-- Core.MarkPlannedEquip's exact math (Core/GearCore.lua:60-164) -- those
-- functions are already shared across Weapons.lua/Jewelry.lua/Armor.lua in
-- production, so this isn't inventing shared uniqueness infrastructure
-- from scratch, it's porting the existing shared semantics onto
-- CandidateNormalizer's normalized `candidate.uniqueness = {key, limit}`
-- shape instead of raw itemID/link, so the new solver never needs raw item
-- data. Core.GearCore.lua itself is untouched.
local addonName, XIVEquip = ...
XIVEquip.Assignments = XIVEquip.Assignments or {}
local Assignments = XIVEquip.Assignments

local LoadoutState = {}
Assignments.LoadoutState = LoadoutState

local Methods = {}
local StateMT = { __index = Methods }

function LoadoutState.New()
  return setmetatable({
    equippedUniqueBySlot = {},
  }, StateMT)
end

-- SeedFromEquipped(candidatesBySlot): candidatesBySlot = {slotID -> candidate|nil}.
-- Mirrors Core.EnsurePlanContext's seeding (GearCore.lua:107-125), but
-- takes already-normalized candidates instead of reading
-- GetInventoryItemLink itself -- collecting equipped items is a
-- Collector-stage concern (see CandidateNormalizer.lua's header comment
-- on that split), not this module's job.
--
-- equippedUniqueBySlot is the ONLY state this module keeps (see
-- CheckAssignment's comment for why an aggregate count/limit cache was
-- removed): every count and limit CheckAssignment needs is reconstructed
-- fresh from this per-slot map on every call.
function Methods:SeedFromEquipped(candidatesBySlot)
  for slotID, candidate in pairs(candidatesBySlot or {}) do
    local uniqueness = candidate and candidate.uniqueness
    local key = uniqueness and uniqueness.key
    if key then
      self.equippedUniqueBySlot[slotID] = { key = key, limit = uniqueness.limit }
    end
  end
end

-- CheckAssignment(additions, removalSlots) -> ok
-- additions: array of non-nil candidates being proposed (an empty/unfilled
-- role contributes nothing and should simply be omitted by the caller).
-- removalSlots: array of slot IDs whose currently-equipped unique
-- contribution should be provisionally subtracted first -- mirrors
-- Core.UniqueAssignmentOK's removalsByKey (GearCore.lua:127-149) exactly,
-- including that a slot is always listed here even if the trial
-- assignment leaves it empty (its *current* occupant is still being
-- displaced by the trial).
--
-- The baseline count AND limit per key are rebuilt from
-- equippedUniqueBySlot fresh on every call, filtering out removalSlots,
-- rather than read from a running aggregate (an earlier version kept
-- aggregate uniqueCounts/uniqueLimits tables updated incrementally by
-- Commit). That aggregate was wrong for this purpose: uniqueLimits[key]
-- only ever tightened to the minimum limit EVER seen for that key, so
-- once a slot holding a tighter-limited item was provisionally removed
-- via removalSlots, the aggregate had no way to "give back" that item's
-- contribution to the limit -- the removed item's old, tighter limit kept
-- constraining every trial forever, even though the item itself was
-- gone. Concrete case this caused: a limit-1 item in a slot being
-- replaced by two limit-2 items of the same key elsewhere -- legal, since
-- the limit-1 item is leaving -- was wrongly rejected because
-- uniqueLimits[key] was still pinned at 1 from before the removal.
-- Rebuilding from equippedUniqueBySlot -- the actual per-slot ground
-- truth -- each call means a removed slot's limit contribution vanishes
-- exactly when its count contribution does, with no separate cache to
-- fall out of sync.
function Methods:CheckAssignment(additions, removalSlots)
  local removalSet = {}
  for _, slotID in ipairs(removalSlots or {}) do
    removalSet[slotID] = true
  end

  local function accumulate(counts, limits, key, limit)
    counts[key] = (counts[key] or 0) + 1
    limit = tonumber(limit) or 1
    limits[key] = limits[key] and math.min(limits[key], limit) or limit
  end

  local counts, limits = {}, {}
  for slotID, rec in pairs(self.equippedUniqueBySlot) do
    if rec.key and not removalSet[slotID] then
      accumulate(counts, limits, rec.key, rec.limit)
    end
  end

  for _, candidate in ipairs(additions or {}) do
    local uniqueness = candidate and candidate.uniqueness
    local key = uniqueness and uniqueness.key
    if key then
      accumulate(counts, limits, key, uniqueness.limit)
    end
  end

  for key, count in pairs(counts) do
    if count > (limits[key] or 1) then return false end
  end
  return true
end

-- Commit(slotID, candidate): applies an accepted assignment for one slot --
-- mirrors Core.MarkPlannedEquip's exact per-slot calling convention
-- (GearCore.lua:151-164), one slot per call, not a batched map. This is
-- deliberate, not just a mirror of the original: `candidate` needs to be
-- an ordinary function argument (which can be nil) so "clear this slot"
-- is expressible at all -- a batched {slotID -> candidate} table can't
-- represent that, because `{[11] = nil}` never actually stores the key 11
-- in Lua (assigning nil in a table constructor is the same as omitting
-- it), making a "clear slot 11" request indistinguishable from "say
-- nothing about slot 11". Committing multiple slots is just multiple
-- calls, each just replacing that one slot's entry in
-- equippedUniqueBySlot -- there's no aggregate cache left to keep in
-- sync, so call order across different slots can't matter even when two
-- of them happen to share a uniqueness key.
function Methods:Commit(slotID, candidate)
  local uniqueness = candidate and candidate.uniqueness
  if uniqueness and uniqueness.key then
    self.equippedUniqueBySlot[slotID] = { key = uniqueness.key, limit = uniqueness.limit }
  else
    self.equippedUniqueBySlot[slotID] = nil
  end
end
