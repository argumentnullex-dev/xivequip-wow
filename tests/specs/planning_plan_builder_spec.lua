local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function join(...) return table.concat({ ... }, sep) end

local function newAddon()
  local addon = { Gear_Core = { SLOT_LABEL = { [11] = "Ring 1", [12] = "Ring 2", [16] = "Main Hand", [17] = "Off Hand" } } }
  local chunk = assert(loadfile(join(root, "XIVEquip", "Planning", "PlanBuilder.lua")))
  chunk("XIVEquip", addon)
  return addon
end

local function bag(id, bagID, slotIndex)
  return {
    itemID = id,
    link = "|Hitem:" .. tostring(id) .. "::::::::::::|h[item-" .. tostring(id) .. "]|h",
    itemLevel = id,
    physicalID = "bag:" .. tostring(bagID) .. ":" .. tostring(slotIndex),
    source = { kind = "bag", bag = bagID, slot = slotIndex, loc = { bagID = bagID, slotIndex = slotIndex } },
    equip = { equipLoc = "INVTYPE_FINGER" },
    uniqueness = {},
  }
end

local function equipped(id, slotID)
  return {
    itemID = id,
    link = "|Hitem:" .. tostring(id) .. "::::::::::::|h[item-" .. tostring(id) .. "]|h",
    itemLevel = id,
    physicalID = "equip:" .. tostring(slotID),
    source = { kind = "equipped", slot = slotID, loc = { equipmentSlot = slotID } },
    equip = { equipLoc = "INVTYPE_FINGER" },
    uniqueness = {},
  }
end

test("PlanBuilder emits bag picks compatible with the existing executor", function()
  local addon = newAddon()
  local current = equipped(101, 11)
  local upgrade = bag(201, 0, 3)

  local changes, pending, plan = addon.Planning.PlanBuilder.Build({
    equippedBySlot = { [11] = current },
    finalSlots = { [11] = upgrade },
    optimizedSlots = { 11 },
  })

  A.equal(pending, false)
  A.equal(#plan, 1)
  A.equal(plan[1].targetSlot, 11)
  A.equal(plan[1].bagID, 0)
  A.equal(plan[1].slotIndex, 3)
  A.equal(plan[1].loc, upgrade.source.loc)
  A.equal(changes[1].oldLink, current.link)
  A.equal(changes[1].newLink, upgrade.link)
end)

test("PlanBuilder moves equipped items before bag items can displace them", function()
  local addon = newAddon()
  local currentA = equipped(101, 11)
  local bagUpgrade = bag(201, 0, 5)

  local _, _, plan = addon.Planning.PlanBuilder.Build({
    equippedBySlot = { [11] = currentA },
    finalSlots = { [11] = bagUpgrade, [12] = currentA },
    optimizedSlots = { 11, 12 },
  })

  A.equal(#plan, 2)
  A.equal(plan[1].fromSlot, 11)
  A.equal(plan[1].targetSlot, 12)
  A.equal(plan[2].bagID, 0)
  A.equal(plan[2].targetSlot, 11)
end)

test("PlanBuilder emits one move for a direct equipped-slot swap", function()
  local addon = newAddon()
  local ringA = equipped(101, 11)
  local ringB = equipped(102, 12)

  local _, _, plan = addon.Planning.PlanBuilder.Build({
    equippedBySlot = { [11] = ringA, [12] = ringB },
    finalSlots = { [11] = ringB, [12] = ringA },
    optimizedSlots = { 11, 12 },
  })

  A.equal(#plan, 1)
  A.equal(plan[1].fromSlot, 12)
  A.equal(plan[1].targetSlot, 11)
end)

test("PlanBuilder relies on 2H equip side effects instead of emitting an empty offhand pick", function()
  local addon = newAddon()
  local oldMain = equipped(101, 16)
  local oldOff = equipped(102, 17)
  local staff = bag(301, 0, 7)
  staff.equip.equipLoc = "INVTYPE_2HWEAPON"

  local _, _, plan = addon.Planning.PlanBuilder.Build({
    equippedBySlot = { [16] = oldMain, [17] = oldOff },
    finalSlots = { [16] = staff, [17] = nil },
    optimizedSlots = { 16, 17 },
  })

  A.equal(#plan, 1)
  A.equal(plan[1].targetSlot, 16)
  A.equal(plan[1].equipLoc, "INVTYPE_2HWEAPON")
end)

test("PlanBuilder emits an explicit offhand cleanup when the selected 2H is already equipped", function()
  local addon = newAddon()
  local staff = equipped(301, 16)
  staff.equip.equipLoc = "INVTYPE_2HWEAPON"
  local staleOffhand = equipped(302, 17)
  staleOffhand.equip.equipLoc = "INVTYPE_2HWEAPON"

  local changes, pending, plan = addon.Planning.PlanBuilder.Build({
    equippedBySlot = { [16] = staff, [17] = staleOffhand },
    finalSlots = { [16] = staff, [17] = nil },
    optimizedSlots = { 16, 17 },
  })

  A.equal(pending, false)
  A.equal(#changes, 1)
  A.equal(#plan, 1)
  A.equal(plan[1].action, "unequip")
  A.equal(plan[1].targetSlot, 17)
  A.equal(changes[1].slot, 17)
end)

test("PlanBuilder reports weapon pair delta for 1H plus offhand to 2H changes", function()
  local addon = newAddon()
  local currentMH = equipped(600, 16)
  currentMH.equip.equipLoc = "INVTYPE_WEAPON"
  local currentOH = equipped(601, 17)
  currentOH.equip.equipLoc = "INVTYPE_HOLDABLE"
  local twoHand = bag(700, 0, 7)
  twoHand.equip.equipLoc = "INVTYPE_2HWEAPON"

  local changes, _, plan = addon.Planning.PlanBuilder.Build({
    equippedBySlot = { [16] = currentMH, [17] = currentOH },
    finalSlots = { [16] = twoHand, [17] = nil },
    currentSlotScores = { [16] = 600, [17] = 600 },
    finalSlotScores = { [16] = 1400, [17] = 0 },
    currentGroupScores = { weapons = 1200 },
    finalGroupScores = { weapons = 1400 },
    optimizedSlots = { 16, 17 },
  })

  A.equal(#plan, 1)
  A.equal(changes[1].slot, 16)
  A.equal(changes[1].deltaScore, 200)
end)

test("PlanBuilder reports unchanged weapon pair score for stale offhand cleanup", function()
  local addon = newAddon()
  local staff = equipped(600, 16)
  staff.equip.equipLoc = "INVTYPE_2HWEAPON"
  local staleOffhand = equipped(601, 17)
  staleOffhand.equip.equipLoc = "INVTYPE_2HWEAPON"

  local changes, _, plan = addon.Planning.PlanBuilder.Build({
    equippedBySlot = { [16] = staff, [17] = staleOffhand },
    finalSlots = { [16] = staff, [17] = nil },
    currentSlotScores = { [16] = 1200, [17] = 0 },
    finalSlotScores = { [16] = 1200, [17] = 0 },
    currentGroupScores = { weapons = 1200 },
    finalGroupScores = { weapons = 1200 },
    optimizedSlots = { 16, 17 },
  })

  A.equal(#plan, 1)
  A.equal(plan[1].action, "unequip")
  A.equal(changes[1].slot, 17)
  A.equal(changes[1].deltaScore, 0)
end)

test("PlanBuilder treats nil recommendation for an ordinary occupied slot as no operation", function()
  local addon = newAddon()
  local current = equipped(101, 11)

  local changes, pending, plan = addon.Planning.PlanBuilder.Build({
    equippedBySlot = { [11] = current },
    finalSlots = { [11] = nil },
    optimizedSlots = { 11 },
  })

  A.equal(pending, false)
  A.equal(#changes, 0)
  A.equal(#plan, 0)
end)

test("PlanBuilder uses evaluated slot scores when present", function()
  local addon = newAddon()
  local current = equipped(101, 11)
  local upgrade = bag(201, 0, 3)

  local changes, _, plan = addon.Planning.PlanBuilder.Build({
    equippedBySlot = { [11] = current },
    finalSlots = { [11] = upgrade },
    currentSlotScores = { [11] = 10 },
    finalSlotScores = { [11] = 55 },
    optimizedSlots = { 11 },
  })

  A.equal(#plan, 1)
  A.equal(plan[1].score, 55)
  A.equal(changes[1].deltaScore, 45)
  A.equal(plan[1].preview, changes[1], "the physical equip step should retain its matching human-facing preview row")
end)

return tests
