-- Diagnostics/Perf.lua
-- Lightweight opt-in timing/counter recorder for native planner diagnostics.
local addonName, XIVEquip = ...
XIVEquip.Diagnostics = XIVEquip.Diagnostics or {}
local Diagnostics = XIVEquip.Diagnostics

local Perf = {}
Diagnostics.Perf = Perf
local unpackValues = table and table.unpack or unpack

local TIMING_ORDER = {
  "Total Plan",
  "Context build",
  "Inventory enumeration",
  "Normalization",
  "Group/frontier construction",
  "  singleton total",
  "  rings",
  "  trinkets",
  "  weapons",
  "Global optimizer",
  "Current-loadout scoring",
  "Diagnostics",
}

local COUNTER_ORDER = {
  "inventory.locations_scanned",
  "inventory.occupied_locations",
  "inventory.equipment_candidates_discovered",
  "normalization.cache_hits",
  "normalization.cache_misses",
  "normalization.renormalized",
  "normalization.tooltip_reads",
  "evaluation.intrinsic_computed",
  "evaluation.intrinsic_cache_hits",
  "evaluation.placement_computed",
  "evaluation.placement_cache_hits",
  "rings.candidates",
  "rings.raw_pair_combinations",
  "rings.legal_assignments",
  "rings.final_frontier_size",
  "trinkets.candidates",
  "trinkets.raw_pair_combinations",
  "trinkets.legal_assignments",
  "trinkets.final_frontier_size",
  "weapons.candidates",
  "weapons.raw_pair_combinations",
  "weapons.legal_assignments",
  "weapons.final_frontier_size",
  "frontier.dominance_comparisons",
  "frontier.candidates_discarded",
  "optimizer.nodes_visited",
  "optimizer.complete_leaves",
  "optimizer.uniqueness_prunes",
  "optimizer.invalid_count_prunes",
  "optimizer.filled_slot_prunes",
  "optimizer.score_bound_prunes",
  "optimizer.policy_bound_prunes",
}

local function nowMs()
  if type(debugprofilestop) == "function" then return debugprofilestop() end
  if type(GetTime) == "function" then return GetTime() * 1000 end
  if os and type(os.clock) == "function" then return os.clock() * 1000 end
  return 0
end

local function formatMs(value)
  return string.format("%.1f ms", tonumber(value) or 0)
end

local Recorder = {}
Recorder.__index = Recorder

function Recorder:Add(name, amount)
  if not self.enabled then return end
  self.counters[name] = (self.counters[name] or 0) + (amount or 1)
end

function Recorder:Set(name, value)
  if not self.enabled then return end
  self.counters[name] = value or 0
end

function Recorder:Start(name)
  if not self.enabled then return nil end
  return { name = name, started = nowMs() }
end

function Recorder:Stop(token)
  if not (self.enabled and token) then return end
  self.timings[token.name] = (self.timings[token.name] or 0) + (nowMs() - token.started)
end

function Recorder:Measure(name, fn)
  if not self.enabled then return fn() end
  local token = self:Start(name)
  local values = { fn() }
  self:Stop(token)
  return unpackValues(values)
end

function Recorder:Snapshot()
  local timings, counters = {}, {}
  for key, value in pairs(self.timings) do timings[key] = value end
  for key, value in pairs(self.counters) do counters[key] = value end
  return { timings = timings, counters = counters }
end

function Recorder:Lines()
  local lines = { "Performance:" }
  for _, name in ipairs(TIMING_ORDER) do
    local value = self.timings[name]
    if value then lines[#lines + 1] = "  " .. name .. ": " .. formatMs(value) end
  end
  lines[#lines + 1] = "Counters:"
  local seen = {}
  for _, name in ipairs(COUNTER_ORDER) do
    seen[name] = true
    lines[#lines + 1] = "  " .. name .. ": " .. tostring(self.counters[name] or 0)
  end
  for name, value in pairs(self.counters) do
    if not seen[name] then lines[#lines + 1] = "  " .. tostring(name) .. ": " .. tostring(value or 0) end
  end
  return lines
end

function Perf.New(enabled)
  return setmetatable({
    enabled = enabled == true,
    timings = {},
    counters = {},
  }, Recorder)
end

function Perf.IsRecorder(value)
  return type(value) == "table" and getmetatable(value) == Recorder
end
