-- Policies/EvaluationContext/ArmorProficiency.lua
-- Ports Core.playerArmorSubclass()'s class -> armor-subclass-ID map
-- (Core/GearCore.lua:407-425) into a context policy, faithfully (same
-- values -- plate=4, mail=3, leather=2, cloth=1 -- keyed by the same class
-- file strings). Core.playerArmorSubclass() itself is untouched; this is
-- new, parallel infrastructure, not a replacement (see Phase 2 plan's
-- scope decisions).
local addonName, XIVEquip = ...

local ARMOR_SUBCLASS_BY_CLASS = {
  WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
  HUNTER = 3, SHAMAN = 3, EVOKER = 3,
  ROGUE = 2, MONK = 2, DEMONHUNTER = 2, DRUID = 2,
  MAGE = 1, PRIEST = 1, WARLOCK = 1,
}

XIVEquip:RegisterPolicy({
  id = "XIVEquip.armor_proficiency",
  phase = "evaluation_context",
  requires = { "character.class_file" },
  provides = { "character.armor_proficiency_subclass" },
  apply = function(builder, runtime)
    local classFile = builder:Get("classFile")
    builder:Set("armorProficiencySubclass", ARMOR_SUBCLASS_BY_CLASS[classFile])
  end,
})
