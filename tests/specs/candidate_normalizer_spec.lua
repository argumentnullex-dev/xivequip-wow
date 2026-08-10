-- tests/specs/candidate_normalizer_spec.lua
-- Doc section 6's Normalized Candidate Model: fact extraction from an
-- already-resolved link, against fake_world's stubs.

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")
local FakeWorld = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "fake_world.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function newAddon()
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)
  return addon
end

test("extracts equip facts, item level, and required level", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = {
      helm = { itemID = 2001, equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 4, itemLevel = 450, requiredLevel = 70 },
    },
  })

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(2001), { kind = "bag", bag = 0, slot = 3 })

  A.equal(candidate.itemID, 2001)
  A.equal(candidate.equip.equipLoc, "INVTYPE_HEAD")
  A.equal(candidate.equip.itemClassID, 4)
  A.equal(candidate.equip.itemSubclassID, 4)
  A.equal(candidate.equip.requiredLevel, 70)
  A.equal(candidate.itemLevel, 450)
end)

test("uses the full item link when the itemID cannot be parsed locally", function()
  local addon = newAddon()
  FakeWorld.Install()
  local richLink = "|Hkeystone-item-string-without-local-item-token|h[item-9001]|h"

  _G.GetItemInfoInstant = function(info)
    A.equal(info, richLink)
    return 9001, nil, nil, "INVTYPE_FINGER", nil, 4, 0
  end
  _G.GetItemInfo = function(info)
    A.equal(info, richLink)
    return "item-9001", richLink, nil, 515, 80, nil, nil, nil, "INVTYPE_FINGER"
  end
  _G.GetDetailedItemLevelInfo = function(info)
    A.equal(info, richLink)
    return 522
  end
  _G.GetItemStats = function(info)
    A.equal(info, richLink)
    return { ITEM_MOD_HASTE_RATING_SHORT = 123 }
  end

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(richLink, { kind = "bag" })

  A.equal(candidate.itemID, 9001)
  A.equal(candidate.equip.equipLoc, "INVTYPE_FINGER")
  A.equal(candidate.itemLevel, 522)
  A.equal(candidate.stats.haste, 123)
end)

test("prefers the effective (upgraded) item level over the base level from GetItemInfo", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = { helm = { itemID = 2002, equipLoc = "INVTYPE_HEAD", itemLevel = 450 } },
  })
  -- fake_world's GetDetailedItemLevelInfo normally mirrors the same base
  -- ilvl, which can't distinguish "prefers effective" from "prefers base"
  -- since they're numerically identical -- override it to return a
  -- genuinely different (upgraded) value, as a real upgrade track item would.
  _G.GetDetailedItemLevelInfo = function() return 489 end

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(2002), {})

  A.equal(candidate.itemLevel, 489, "the effective/upgraded level should win over the base 450")
end)

test("falls back to the base item level when no effective level is available", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = { helm = { itemID = 2003, equipLoc = "INVTYPE_HEAD", itemLevel = 450 } },
  })
  _G.GetDetailedItemLevelInfo = function() return nil end

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(2003), {})

  A.equal(candidate.itemLevel, 450)
end)

test("passes caller-supplied source metadata through verbatim", function()
  local addon = newAddon()
  FakeWorld.Install({ items = { ring = { itemID = 3001, equipLoc = "INVTYPE_FINGER" } } })

  local source = { kind = "bag", bag = 2, slot = 5, guid = "guid-abc", physicalID = "bag:2:5" }
  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(3001), source)

  A.equal(candidate.guid, "guid-abc")
  A.equal(candidate.physicalID, "bag:2:5")
  A.same(candidate.source, source)
end)

test("uses source itemID when the item link identity is not parseable", function()
  local addon = newAddon()
  FakeWorld.Install({ items = { ring = { itemID = 3002, equipLoc = "INVTYPE_FINGER" } } })
  _G.GetItemInfo = function() return "ring", "opaque-link", nil, 450, 1 end
  _G.GetDetailedItemLevelInfo = function() return nil end

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink("opaque-link", { itemID = 3002 })

  A.truthy(candidate)
  A.equal(candidate.itemID, 3002)
  A.equal(candidate.equip.equipLoc, "INVTYPE_FINGER")
end)

test("returns pending instead of throwing when item info cannot be normalized", function()
  local addon = newAddon()
  FakeWorld.Install({})

  local candidate, reason = addon.Evaluation.CandidateNormalizer.FromLink("not-an-item-link", {})

  A.falsy(candidate)
  A.equal(reason, "pending-item-data")
end)

-- These uniqueness tests deliberately do NOT use fake_world.lua's
-- uniqueKey/uniqueLimit scenario fields -- that fake returns an
-- already-normalized string as the "key" directly, which isn't what
-- Blizzard's real API returns (a numeric limitCategory, where 0
-- specifically means "item-specific," not "not unique") and would mask
-- exactly the bug being tested for here. Overriding C_Item's uniqueness
-- functions directly, after FakeWorld.Install, exercises the real
-- raw-category branching in CandidateNormalizer.resolveUniqueness.

test("an ordinary Unique-Equipped item (category 0) normalizes to an item-specific key, not the raw 0", function()
  local addon = newAddon()
  FakeWorld.Install({ items = { trinket = { itemID = 4001, equipLoc = "INVTYPE_TRINKET" } } })
  _G.C_Item.GetItemUniqueness = function() return 0, 1 end

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(4001), {})

  A.equal(candidate.uniqueness.key, "item:4001")
  A.equal(candidate.uniqueness.limit, 1)
end)

test("two different item-specific unique items normalize to different keys, so they don't spuriously conflict", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = {
      trinketA = { itemID = 4001, equipLoc = "INVTYPE_TRINKET" },
      trinketB = { itemID = 4002, equipLoc = "INVTYPE_TRINKET" },
    },
  })
  _G.C_Item.GetItemUniqueness = function() return 0, 1 end

  local a = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(4001), {})
  local b = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(4002), {})

  A.truthy(a.uniqueness.key ~= b.uniqueness.key, "two unrelated Unique-Equipped items must not share a key")
end)

test("a shared unique category (nonzero) normalizes to a category-based key", function()
  local addon = newAddon()
  FakeWorld.Install({ items = { trinket = { itemID = 4003, equipLoc = "INVTYPE_TRINKET" } } })
  _G.C_Item.GetItemUniqueness = function() return 55, 2 end

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(4003), {})

  A.equal(candidate.uniqueness.key, "category:55")
  A.equal(candidate.uniqueness.limit, 2)
end)

test("falls back to GetItemUniquenessByID when GetItemUniqueness returns nothing", function()
  local addon = newAddon()
  FakeWorld.Install({ items = { trinket = { itemID = 4004, equipLoc = "INVTYPE_TRINKET" } } })
  _G.C_Item.GetItemUniqueness = function() return nil, nil end
  _G.C_Item.GetItemUniquenessByID = function() return true, nil, nil, nil end

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(4004), {})

  A.equal(candidate.uniqueness.key, "item:4004")
  A.equal(candidate.uniqueness.limit, 1)
end)

test("an item with no uniqueness data at all normalizes to a nil key", function()
  local addon = newAddon()
  FakeWorld.Install({ items = { plain = { itemID = 4005, equipLoc = "INVTYPE_TRINKET" } } })
  _G.C_Item.GetItemUniqueness = function() return nil, nil end
  _G.C_Item.GetItemUniquenessByID = function() return nil, nil, nil, nil end

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(4005), {})

  A.falsy(candidate.uniqueness.key)
end)

test("extracts every stat feature, defaulting absent ones to zero", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = {
      chest = {
        itemID = 5001, equipLoc = "INVTYPE_CHEST",
        stats = { ITEM_MOD_STRENGTH_SHORT = 120, ITEM_MOD_CRIT_RATING_SHORT = 45 },
      },
    },
  })

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(5001), {})

  A.equal(candidate.stats.strength, 120)
  A.equal(candidate.stats.criticalStrike, 45)
  A.equal(candidate.stats.haste, 0, "an absent stat should default to zero, not nil")
end)

test("extracts weapon dps/min/max damage from the same stats table", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = {
      axe = {
        itemID = 6001, equipLoc = "INVTYPE_WEAPON",
        stats = { ITEM_MIN_DAMAGE = 80, ITEM_MAX_DAMAGE = 160, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 55.5 },
      },
    },
  })

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(6001), {})

  A.equal(candidate.weapon.minimumDamage, 80)
  A.equal(candidate.weapon.maximumDamage, 160)
  A.equal(candidate.weapon.dps, 55.5)
end)

test("extracts weapon speed and tooltip damage fallback for native Pawn scoring", function()
  local addon = newAddon()
  FakeWorld.Install({
    items = {
      axe = {
        itemID = 6002, equipLoc = "INVTYPE_WEAPON",
        stats = {},
      },
    },
  })
  _G.C_TooltipInfo = {
    GetHyperlink = function()
      return {
        lines = {
          { leftText = "120 - 240 Damage", rightText = "Speed 3.60" },
        },
      }
    end,
  }

  local candidate = addon.Evaluation.CandidateNormalizer.FromLink(FakeWorld.ItemLink(6002), {})

  A.equal(candidate.weapon.minimumDamage, 120)
  A.equal(candidate.weapon.maximumDamage, 240)
  A.equal(candidate.weapon.swingIntervalSeconds, 3.60)
  A.equal(candidate.weapon.dps, 50)
end)

return tests
