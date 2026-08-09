-- tests/scenarios/paired_slots/trinkets.lua
-- Doc section 7's trinket bullets that only need scoring/uniqueness (no
-- policy metadata), ported from tests/specs/paired_slots_spec.lua. The
-- preferred/avoided/excluded/required/passive-on-use bullets need trinket
-- policy metadata that doesn't exist yet -- see
-- tests/scenarios/policies/trinket_policy.lua for those, written as
-- skipped placeholders per user decision.

local root = ...
local sep = package.config:sub(1, 1)
local Item = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "item_builder.lua")

local function trinket(id, s13, s14, extra) return Item.trinket(id, s13, s14, extra) end

return {

  {
    name = "trinket pair: bag upgrade replaces the weaker equipped trinket, stronger one is kept",
    items = {
      old13 = trinket(101, 100, 100),
      old14 = trinket(102, 80, 80),
      upgrade = trinket(201, 110, 110),
    },
    equipped = { [13] = "old13", [14] = "old14" },
    bags = { [0] = { "upgrade" } },
    expect = { final = { [14] = "upgrade" }, unchanged = { 13 } },
  },

  {
    name = "trinket pair: empty slots still equip the best negative-scoring trinkets, worst excluded",
    items = {
      worst = trinket(201, -700, -700),
      mid = trinket(202, -200, -220),
      best = trinket(203, -30, -20),
    },
    equipped = {},
    bags = { [0] = { "worst", "mid", "best" } },
    expect = { final = { [13] = "mid", [14] = "best" } },
  },

  {
    name = "trinket pair: empty slots ignore a deep item-level downgrade when current-tier trinkets are available",
    items = {
      hugeScoreLowIlvl = trinket(201, 1000, 1000, { itemLevel = 192 }),
      currentTierA = trinket(202, 100, 95, { itemLevel = 246 }),
      currentTierB = trinket(203, 90, 105, { itemLevel = 246 }),
    },
    equipped = {},
    bags = { [0] = { "hugeScoreLowIlvl", "currentTierA", "currentTierB" } },
    expect = { final = { [13] = "currentTierA", [14] = "currentTierB" } },
  },

  {
    name = "trinket pair: category zero with limit zero is treated as non-unique",
    items = {
      nonUniqueA = trinket(201, 200, 150, { uniqueKey = 0, uniqueLimit = 0, itemLevel = 246 }),
      nonUniqueB = trinket(202, 140, 190, { uniqueKey = 0, uniqueLimit = 0, itemLevel = 246 }),
    },
    equipped = {},
    bags = { [0] = { "nonUniqueA", "nonUniqueB" } },
    expect = { final = { [13] = "nonUniqueA", [14] = "nonUniqueB" } },
  },
}
