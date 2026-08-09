-- tests/harness/item_builder.lua
-- Convenience constructors for scenario item fixtures (doc section 4's
-- `scenario.items[key] = {...}` shape), so scenario files can stay terse
-- instead of repeating boilerplate defaults.

local Item = {}

-- A weapon candidate for the main-hand (16) / off-hand (17) slots.
function Item.weapon(id, equipLoc, mhScore, ohScore, extra)
  extra = extra or {}
  extra.itemID = id
  extra.equipLoc = equipLoc
  extra.classID = extra.classID or 2
  extra.scores = extra.scores or { [16] = mhScore, [17] = ohScore or mhScore }
  extra.itemLevel = extra.itemLevel or mhScore
  extra.requiredLevel = extra.requiredLevel or 1
  return extra
end

-- A paired-slot candidate (rings 11/12, trinkets 13/14).
function Item.jewelry(id, equipLoc, slotA, scoreA, slotB, scoreB, extra)
  extra = extra or {}
  extra.itemID = id
  extra.equipLoc = equipLoc
  extra.classID = extra.classID or 4
  extra.scores = extra.scores or { [slotA] = scoreA, [slotB] = scoreB or scoreA }
  extra.itemLevel = extra.itemLevel or math.max(scoreA or 1, scoreB or scoreA or 1)
  extra.requiredLevel = extra.requiredLevel or 1
  return extra
end

function Item.ring(id, score11, score12, extra)
  return Item.jewelry(id, "INVTYPE_FINGER", 11, score11, 12, score12, extra)
end

function Item.trinket(id, score13, score14, extra)
  return Item.jewelry(id, "INVTYPE_TRINKET", 13, score13, 14, score14, extra)
end

-- Player-armor-proficiency subclass IDs, matching Core.playerArmorSubclass's
-- class -> subclass map (Core/GearCore.lua): plate=4, mail=3, leather=2, cloth=1.
Item.ARMOR_SUBCLASS = {
  plate = 4,
  mail = 3,
  leather = 2,
  cloth = 1,
}

-- A single-slot armor candidate. `armorType` is "plate"/"mail"/"leather"/
-- "cloth" and is checked against the scenario character's class by
-- Core.equipIsValidArmorType -- mismatches are legally excluded, which is
-- exactly what makes them useful as "illegal but tempting" trap candidates.
function Item.armor(id, equipLoc, slotID, armorType, score, extra)
  extra = extra or {}
  extra.itemID = id
  extra.equipLoc = equipLoc
  extra.classID = 4
  extra.subclassID = Item.ARMOR_SUBCLASS[armorType] or extra.subclassID
  extra.scores = extra.scores or { [slotID] = score }
  extra.itemLevel = extra.itemLevel or score
  extra.requiredLevel = extra.requiredLevel or 1
  return extra
end

return Item
