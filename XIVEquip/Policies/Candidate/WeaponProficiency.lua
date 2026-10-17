-- Policies/Candidate/WeaponProficiency.lua
-- C_Item.IsEquippableItem identifies equipment, not whether the current
-- class/spec has the corresponding weapon proficiency. Candidate collection
-- already handles the structural question; this policy owns the player-specific
-- proficiency question. Hand and loadout legality remains an assignment policy.
local addonName, XIVEquip = ...

local WEAPON_ITEM_CLASS_ID = 2

-- Enum.ItemWeaponSubclass values. Named locally so the policy also works in
-- the offline harness, where the client Enum table is intentionally absent.
local W = {
  AXE_1H = 0,
  AXE_2H = 1,
  BOW = 2,
  GUN = 3,
  MACE_1H = 4,
  MACE_2H = 5,
  POLEARM = 6,
  SWORD_1H = 7,
  SWORD_2H = 8,
  WARGLAIVE = 9,
  STAFF = 10,
  FIST = 13,
  DAGGER = 15,
  CROSSBOW = 18,
  WAND = 19,
}

local function set(...)
  local result = {}
  for i = 1, select("#", ...) do result[select(i, ...)] = true end
  return result
end

-- Complete retail class proficiency matrix. This deliberately describes
-- weapon skills, not preferred stats or legal hand combinations.
local ALLOWED_WEAPON_SUBCLASSES = {
  WARRIOR = set(W.AXE_1H, W.AXE_2H, W.MACE_1H, W.MACE_2H, W.POLEARM,
    W.SWORD_1H, W.SWORD_2H, W.STAFF, W.FIST, W.DAGGER),
  PALADIN = set(W.AXE_1H, W.AXE_2H, W.MACE_1H, W.MACE_2H, W.POLEARM,
    W.SWORD_1H, W.SWORD_2H),
  HUNTER = set(W.AXE_1H, W.AXE_2H, W.BOW, W.GUN, W.POLEARM, W.SWORD_1H,
    W.SWORD_2H, W.STAFF, W.FIST, W.DAGGER, W.CROSSBOW),
  ROGUE = set(W.AXE_1H, W.MACE_1H, W.SWORD_1H, W.FIST, W.DAGGER),
  PRIEST = set(W.MACE_1H, W.STAFF, W.DAGGER, W.WAND),
  DEATHKNIGHT = set(W.AXE_1H, W.AXE_2H, W.MACE_1H, W.MACE_2H, W.POLEARM,
    W.SWORD_1H, W.SWORD_2H),
  SHAMAN = set(W.AXE_1H, W.AXE_2H, W.MACE_1H, W.MACE_2H, W.STAFF, W.FIST,
    W.DAGGER),
  MAGE = set(W.SWORD_1H, W.STAFF, W.DAGGER, W.WAND),
  WARLOCK = set(W.SWORD_1H, W.STAFF, W.DAGGER, W.WAND),
  MONK = set(W.AXE_1H, W.MACE_1H, W.POLEARM, W.SWORD_1H, W.STAFF, W.FIST),
  DRUID = set(W.MACE_1H, W.MACE_2H, W.POLEARM, W.STAFF, W.FIST, W.DAGGER),
  DEMONHUNTER = set(W.AXE_1H, W.SWORD_1H, W.WARGLAIVE, W.FIST),
  EVOKER = set(W.AXE_1H, W.AXE_2H, W.MACE_1H, W.MACE_2H, W.SWORD_1H,
    W.SWORD_2H, W.STAFF, W.FIST, W.DAGGER),
}

-- Midnight's Devourer specialization adds dagger proficiency to the Demon
-- Hunter baseline. Keep the exception spec-scoped: Havoc and Vengeance retain
-- their class-page weapon list.
local SPEC_WEAPON_SUBCLASS_ADDITIONS = {
  DEMONHUNTER = {
    [1480] = set(W.DAGGER),
  },
}

XIVEquip:RegisterPolicy({
  id = "XIVEquip.candidate_weapon_proficiency",
  phase = "candidate",
  requires = { "character.class_file", "character.spec_id" },
  apply = function(candidate, context)
    local equip = candidate and candidate.equip
    if not equip or equip.itemClassID ~= WEAPON_ITEM_CLASS_ID then return nil end

    local classFile = context and context.classFile
    local allowed = ALLOWED_WEAPON_SUBCLASSES[classFile]
    if not allowed then return nil end
    if allowed[equip.itemSubclassID] then return nil end

    local bySpec = SPEC_WEAPON_SUBCLASS_ADDITIONS[classFile]
    local additions = bySpec and bySpec[context and context.specID]
    if additions and additions[equip.itemSubclassID] then return nil end

    return { allow = false, reason = "unsupported-weapon-proficiency" }
  end,
})
