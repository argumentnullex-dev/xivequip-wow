-- tests/scenarios/weapons/archetypes.lua
-- Doc section 6's weapon archetype matrix, tested under Weapons.lua's real
-- (hardcoded, current-behavior) policyForSpec() -- no overrides. Each
-- archetype gets a naked scenario and an already-equipped-upgrade scenario,
-- using a representative class/spec from the doc's table.

local root = ...
local sep = package.config:sub(1, 1)
local Item = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "item_builder.lua")

local function weapon2h(id, score, extra) return Item.weapon(id, "INVTYPE_2HWEAPON", score, score, extra) end
local function weapon1h(id, score, extra) return Item.weapon(id, "INVTYPE_WEAPON", score, score, extra) end
local function shield(id, score, extra) return Item.weapon(id, "INVTYPE_SHIELD", 0, score, extra) end
local function holdable(id, score, extra) return Item.weapon(id, "INVTYPE_HOLDABLE", 0, score, extra) end

return {

  -- 1. Two-handed only (Arms Warrior)
  {
    name = "weapon archetype: two-handed only, naked (Arms)",
    character = { classFile = "WARRIOR", specID = 71, specName = "Arms" },
    items = {
      legal2h = weapon2h(1101, 100),
      illegal1hTrap = weapon1h(1102, 999),
    },
    equipped = {},
    bags = { [0] = { "legal2h", "illegal1hTrap" } },
    expect = { final = { [16] = "legal2h" }, unchanged = { 17 } },
  },
  {
    name = "weapon archetype: two-handed only, equipped upgrade (Arms)",
    character = { classFile = "WARRIOR", specID = 71, specName = "Arms" },
    items = {
      old2h = weapon2h(1103, 80),
      strong2h = weapon2h(1104, 120),
      illegal1hTrap = weapon1h(1105, 999),
    },
    equipped = { [16] = "old2h" },
    bags = { [0] = { "strong2h", "illegal1hTrap" } },
    expect = { final = { [16] = "strong2h" }, unchanged = { 17 } },
  },

  -- 2. Dual-wield only (Rogue)
  {
    name = "weapon archetype: dual-wield only, naked (Rogue)",
    character = { classFile = "ROGUE", specID = 260, specName = "Outlaw" },
    items = {
      betterMh = weapon1h(1201, 100),
      weakerOh = weapon1h(1202, 90),
      illegal2hTrap = weapon2h(1203, 999),
    },
    equipped = {},
    bags = { [0] = { "betterMh", "weakerOh", "illegal2hTrap" } },
    expect = { final = { [16] = "betterMh", [17] = "weakerOh" } },
  },
  {
    name = "weapon archetype: dual-wield only, displaced main hand moves to offhand (Rogue)",
    character = { classFile = "ROGUE", specID = 260, specName = "Outlaw" },
    items = {
      oldMh = weapon1h(1204, 50),
      oldOh = weapon1h(1205, 45),
      strongNew = weapon1h(1206, 110),
    },
    equipped = { [16] = "oldMh", [17] = "oldOh" },
    bags = { [0] = { "strongNew" } },
    expect = { final = { [16] = "strongNew", [17] = "oldMh" } },
  },

  -- 3. One-hand + required shield (Protection Warrior)
  {
    name = "weapon archetype: 1H + required shield, naked (Protection Warrior)",
    character = { classFile = "WARRIOR", specID = 73, specName = "Protection" },
    items = {
      legal1h = weapon1h(1301, 80),
      legalShield = shield(1302, 60),
      illegal2hTrap = weapon2h(1303, 999),
      illegalHoldableTrap = holdable(1304, 70),
    },
    equipped = {},
    bags = { [0] = { "legal1h", "legalShield", "illegal2hTrap", "illegalHoldableTrap" } },
    expect = { final = { [16] = "legal1h", [17] = "legalShield" } },
  },
  {
    name = "weapon archetype: 1H + required shield, missing better shield keeps current shield (Protection Warrior)",
    character = { classFile = "WARRIOR", specID = 73, specName = "Protection" },
    items = {
      old1h = weapon1h(1305, 50),
      oldShield = shield(1306, 40),
      better1h = weapon1h(1307, 90),
    },
    equipped = { [16] = "old1h", [17] = "oldShield" },
    bags = { [0] = { "better1h" } },
    expect = { final = { [16] = "better1h" }, unchanged = { 17 } },
  },

  -- 4. One-hand + shield or holdable (Holy Paladin)
  {
    name = "weapon archetype: 1H + shield-or-holdable, score picks holdable pair, naked (Holy Paladin)",
    character = { classFile = "PALADIN", specID = 65, specName = "Holy" },
    items = {
      mh = weapon1h(1401, 80),
      legalShield = shield(1402, 50),
      legalHoldable = holdable(1403, 60),
      illegal2hTrap = weapon2h(1404, 999),
    },
    equipped = {},
    bags = { [0] = { "mh", "legalShield", "legalHoldable", "illegal2hTrap" } },
    expect = { final = { [16] = "mh", [17] = "legalHoldable" } },
  },
  {
    name = "weapon archetype: 1H + shield-or-holdable, offhand-only upgrade (Holy Paladin)",
    character = { classFile = "PALADIN", specID = 65, specName = "Holy" },
    items = {
      oldMh = weapon1h(1405, 60),
      oldShield = shield(1406, 40),
      betterHoldable = holdable(1407, 90),
    },
    equipped = { [16] = "oldMh", [17] = "oldShield" },
    bags = { [0] = { "betterHoldable" } },
    expect = { final = { [17] = "betterHoldable" }, unchanged = { 16 } },
  },

  -- 5. Two-handed or 1H+shield/holdable (Elemental Shaman)
  {
    name = "weapon archetype: 2H or 1H+offhand, 2H wins on total score, naked (Elemental Shaman)",
    character = { classFile = "SHAMAN", specID = 262, specName = "Elemental" },
    items = {
      staff = weapon2h(1501, 150),
      mh1h = weapon1h(1502, 70),
      legalShield = shield(1503, 50),
      legalHoldable = holdable(1504, 60),
    },
    equipped = {},
    bags = { [0] = { "staff", "mh1h", "legalShield", "legalHoldable" } },
    expect = { final = { [16] = "staff" }, unchanged = { 17 } },
  },
  {
    -- A two-handed weapon physically occupies the offhand slot too, so
    -- replacing an equipped 1H+shield loadout with a 2H must clear the
    -- shield out of slot 17 as a side effect, even though the plan only
    -- carries an explicit pick for slot 16.
    name = "weapon archetype: 2H or 1H+offhand, upgrading to a 2H clears the equipped shield (Elemental Shaman)",
    character = { classFile = "SHAMAN", specID = 262, specName = "Elemental" },
    items = {
      oldMh1h = weapon1h(1508, 60),
      oldShield = shield(1509, 40),
      strongStaff = weapon2h(1510, 200),
    },
    equipped = { [16] = "oldMh1h", [17] = "oldShield" },
    bags = { [0] = { "strongStaff" } },
    expect = { final = { [16] = "strongStaff", [17] = false } },
  },
  {
    name = "weapon archetype: 2H or 1H+offhand, 1H+holdable pair beats current 2H (Elemental Shaman)",
    character = { classFile = "SHAMAN", specID = 262, specName = "Elemental" },
    items = {
      old2h = weapon2h(1505, 100),
      mh1h = weapon1h(1506, 90),
      legalHoldable = holdable(1507, 85),
    },
    equipped = { [16] = "old2h" },
    bags = { [0] = { "mh1h", "legalHoldable" } },
    expect = { final = { [16] = "mh1h", [17] = "legalHoldable" } },
  },

  -- 6. Two-handed or 1H+holdable, never 2H+offhand (Mage)
  {
    name = "weapon archetype: 2H or 1H+holdable, holdable pair wins, naked (Mage)",
    character = { classFile = "MAGE", specID = 62, specName = "Arcane" },
    items = {
      staff = weapon2h(1601, 120),
      mh1h = weapon1h(1602, 70),
      legalHoldable = holdable(1603, 60),
      illegalShieldTrap = shield(1604, 999),
    },
    equipped = {},
    bags = { [0] = { "staff", "mh1h", "legalHoldable", "illegalShieldTrap" } },
    expect = { final = { [16] = "mh1h", [17] = "legalHoldable" } },
  },
  {
    name = "weapon archetype: 2H or 1H+holdable, pair upgrade replaces equipped 2H (Mage)",
    character = { classFile = "MAGE", specID = 62, specName = "Arcane" },
    items = {
      old2h = weapon2h(1605, 100),
      mh1h = weapon1h(1606, 60),
      legalHoldable = holdable(1607, 50),
    },
    equipped = { [16] = "old2h" },
    bags = { [0] = { "mh1h", "legalHoldable" } },
    expect = { final = { [16] = "mh1h", [17] = "legalHoldable" } },
  },

  -- 7. Two-handed or dual-wield (Frost Death Knight)
  {
    name = "weapon archetype: 2H or dual-wield, dual-wield wins on total score, naked (Frost DK)",
    character = { classFile = "DEATHKNIGHT", specID = 251, specName = "Frost" },
    items = {
      the2h = weapon2h(1701, 140),
      dw1 = weapon1h(1702, 80),
      dw2 = weapon1h(1703, 75),
    },
    equipped = {},
    bags = { [0] = { "the2h", "dw1", "dw2" } },
    expect = { final = { [16] = "dw1", [17] = "dw2" } },
  },
  {
    name = "weapon archetype: 2H or dual-wield, 2H upgrade wins -- dual-wield is not assumed (Frost DK)",
    character = { classFile = "DEATHKNIGHT", specID = 251, specName = "Frost" },
    items = {
      old2h = weapon2h(1704, 100),
      strong2h = weapon2h(1705, 160),
      dw1 = weapon1h(1706, 70),
      dw2 = weapon1h(1707, 65),
    },
    equipped = { [16] = "old2h" },
    bags = { [0] = { "strong2h", "dw1", "dw2" } },
    expect = { final = { [16] = "strong2h" }, unchanged = { 17 } },
  },

  -- 8. Titan's Grip (Fury Warrior)
  {
    name = "weapon archetype: Titan's Grip, mixed 2H+1H pair beats matched pairs, naked (Fury)",
    character = { classFile = "WARRIOR", specID = 72, specName = "Fury" },
    items = {
      the2hBest = weapon2h(1801, 130),
      the2hSecond = weapon2h(1802, 110),
      the1hBest = weapon1h(1803, 120),
      the1hSecond = weapon1h(1804, 115),
    },
    equipped = {},
    bags = { [0] = { "the2hBest", "the2hSecond", "the1hBest", "the1hSecond" } },
    expect = { final = { [16] = "the2hBest", [17] = "the1hBest" } },
  },
  {
    name = "weapon archetype: Titan's Grip, displaced equipped weapon moves to offhand (Fury)",
    character = { classFile = "WARRIOR", specID = 72, specName = "Fury" },
    items = {
      oldMh = weapon2h(1805, 100),
      oldOh = weapon2h(1806, 90),
      strongNew = weapon2h(1807, 200),
    },
    equipped = { [16] = "oldMh", [17] = "oldOh" },
    bags = { [0] = { "strongNew" } },
    expect = { final = { [16] = "strongNew", [17] = "oldMh" } },
  },
  {
    -- The already-equipped offhand 2H stays the best offhand choice, so
    -- Weapons.lua emits only a main-hand pick (appendIfChanged skips a pick
    -- whose candidate is the same physical item as what's already there).
    -- That must not be mistaken for "the plan left slot 17 unaddressed
    -- because it needs clearing" -- a legal Titan's Grip offhand has to
    -- survive an unrelated main-hand upgrade.
    name = "weapon archetype: Titan's Grip, main-hand-only upgrade keeps the legitimate 2H offhand (Fury)",
    character = { classFile = "WARRIOR", specID = 72, specName = "Fury" },
    items = {
      oldMh = weapon2h(1808, 100),
      oldOh = weapon2h(1809, 110),
      strongNew = weapon2h(1810, 150),
    },
    equipped = { [16] = "oldMh", [17] = "oldOh" },
    bags = { [0] = { "strongNew" } },
    expect = { final = { [16] = "strongNew" }, unchanged = { 17 } },
  },
  {
    -- Titan's Grip also legally covers a mixed 2H+1H pair (Blizzard's own
    -- description: "one-hand weapons, and two-hand weapons, or a
    -- combination") -- not just matched 2H+2H. A 1H offhand is exactly as
    -- legitimate here as a 2H one and must equally survive an unrelated
    -- main-hand-only upgrade.
    name = "weapon archetype: Titan's Grip, main-hand-only upgrade keeps a legitimate 1H offhand (Fury)",
    character = { classFile = "WARRIOR", specID = 72, specName = "Fury" },
    items = {
      oldMh = weapon2h(1811, 100),
      oldOh = weapon1h(1812, 110),
      strongNew = weapon2h(1813, 150),
    },
    equipped = { [16] = "oldMh", [17] = "oldOh" },
    bags = { [0] = { "strongNew" } },
    expect = { final = { [16] = "strongNew" }, unchanged = { 17 } },
  },

  -- 9. One-hand or two-hand, no offhand ever (Brewmaster Monk)
  {
    name = "weapon archetype: 1H or 2H without offhand, best single weapon wins, naked (Brewmaster)",
    character = { classFile = "MONK", specID = 268, specName = "Brewmaster" },
    items = {
      mh1h = weapon1h(1901, 90),
      the2h = weapon2h(1902, 110),
      offhandTrap = holdable(1903, 999),
    },
    equipped = {},
    bags = { [0] = { "mh1h", "the2h", "offhandTrap" } },
    expect = { final = { [16] = "the2h" }, unchanged = { 17 } },
  },
  {
    name = "weapon archetype: 1H or 2H without offhand, 2H upgrade replaces equipped 1H (Brewmaster)",
    character = { classFile = "MONK", specID = 268, specName = "Brewmaster" },
    items = {
      old1h = weapon1h(1904, 70),
      strong2h = weapon2h(1905, 130),
    },
    equipped = { [16] = "old1h" },
    bags = { [0] = { "strong2h" } },
    expect = { final = { [16] = "strong2h" }, unchanged = { 17 } },
  },
}
