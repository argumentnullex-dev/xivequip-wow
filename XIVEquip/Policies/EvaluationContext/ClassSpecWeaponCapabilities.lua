-- Policies/EvaluationContext/ClassSpecWeaponCapabilities.lua
-- Ports Gear/Weapons.lua's policyForSpec() (lines 33-106) faithfully into a
-- context policy -- same class/spec branches, same flags. Weapons.lua's own
-- copy is untouched; this is new, parallel infrastructure for Phase 3+ to
-- eventually consume (see Phase 2 plan's scope decisions).
--
-- One policy sets all 8 capabilities together rather than 8 separate
-- policies each re-deriving the same interdependent per-spec branch (doc
-- 5.4: capabilities are resolved once per pass -- this is one such
-- resolution, not eight). The live IsDualWielding() override is a separate
-- policy (DualWieldOverride.lua), ordered after this one via requires.
local addonName, XIVEquip = ...

-- classFile -> spec ID -> capability overrides layered onto the defaults
-- below. Mirrors policyForSpec()'s if/elseif chain exactly.
local SPEC_OVERRIDES = {
  WARRIOR = {
    [71] = { allow2H = true, allowMH1H = false },
    [72] = { allow2H = true, allowDualWield = true, allowOffhandWeapon = true, allowTitanGrip = true },
    [73] = { allow2H = false, allowMH1H = true, allowShield = true, requireShield = true },
  },
  PALADIN = {
    [65] = { allow2H = false, allowMH1H = true, allowShield = true, allowHoldable = true },
    [66] = { allow2H = false, allowMH1H = true, allowShield = true, requireShield = true },
    [70] = { allow2H = true, allowMH1H = false },
  },
  DEATHKNIGHT = {
    [250] = { allow2H = true, allowMH1H = false },
    [251] = { allow2H = true, allowDualWield = true, allowOffhandWeapon = true },
    [252] = { allow2H = true, allowMH1H = false },
  },
  MONK = {
    [269] = { allow2H = true, allowDualWield = true, allowOffhandWeapon = true },
    [268] = { allow2H = true, allowMH1H = true },
    [270] = { allow2H = true, allowMH1H = true, allowHoldable = true },
  },
}

-- classFile -> capability overrides that don't vary by spec.
local CLASS_OVERRIDES = {
  ROGUE = { allow2H = false, allowDualWield = true, allowOffhandWeapon = true },
  DEMONHUNTER = { allow2H = false, allowDualWield = true, allowOffhandWeapon = true },
  HUNTER = { allow2H = true, allowMH1H = false },
  MAGE = { allow2H = true, allowMH1H = true, allowHoldable = true },
  PRIEST = { allow2H = true, allowMH1H = true, allowHoldable = true },
  WARLOCK = { allow2H = true, allowMH1H = true, allowHoldable = true },
  EVOKER = { allow2H = true, allowMH1H = true, allowHoldable = true },
}

-- SHAMAN and DRUID key off spec presence/absence rather than a flat class
-- default (policyForSpec()'s `if spec == X then ... else ... end` shape),
-- so they're handled directly in classSpecWeaponProfile below.

local function classSpecWeaponProfile(classFile, specID)
  local P = {
    allow2H = true,
    allowDualWield = false,
    allowOffhandWeapon = false,
    allowShield = false,
    allowHoldable = false,
    allowMH1H = true,
    allowTitanGrip = false,
    requireShield = false,
  }

  local specOverrides = SPEC_OVERRIDES[classFile] and SPEC_OVERRIDES[classFile][specID]
  if specOverrides then
    for key, value in pairs(specOverrides) do P[key] = value end
  elseif classFile == "SHAMAN" then
    if specID == 263 then
      P.allow2H = false; P.allowDualWield = true; P.allowOffhandWeapon = true
    else
      P.allow2H = true; P.allowMH1H = true; P.allowShield = true; P.allowHoldable = true
    end
  elseif classFile == "DRUID" then
    if specID == 103 or specID == 104 then
      P.allow2H = true; P.allowMH1H = false
    else
      P.allow2H = true; P.allowMH1H = true; P.allowHoldable = true
    end
  elseif CLASS_OVERRIDES[classFile] then
    for key, value in pairs(CLASS_OVERRIDES[classFile]) do P[key] = value end
  end

  return P
end

XIVEquip.Policies = XIVEquip.Policies or {}
XIVEquip.Policies.ClassSpecWeaponProfile = classSpecWeaponProfile

XIVEquip:RegisterPolicy({
  id = "XIVEquip.class_spec_weapon_capabilities",
  phase = "evaluation_context",
  requires = { "character.class_file", "character.spec_id" },
  provides = {
    "capability.XIVEquip.allow_two_hand",
    "capability.XIVEquip.allow_dual_wield",
    "capability.XIVEquip.allow_offhand_weapon",
    "capability.XIVEquip.allow_shield",
    "capability.XIVEquip.allow_holdable",
    "capability.XIVEquip.allow_main_hand_one_hand",
    "capability.XIVEquip.titan_grip",
    "capability.XIVEquip.require_shield",
  },
  apply = function(builder, runtime)
    local profile = classSpecWeaponProfile(builder:Get("classFile"), builder:Get("specID"))
    builder:SetCapability("XIVEquip.allow_two_hand", profile.allow2H)
    builder:SetCapability("XIVEquip.allow_dual_wield", profile.allowDualWield)
    builder:SetCapability("XIVEquip.allow_offhand_weapon", profile.allowOffhandWeapon)
    builder:SetCapability("XIVEquip.allow_shield", profile.allowShield)
    builder:SetCapability("XIVEquip.allow_holdable", profile.allowHoldable)
    builder:SetCapability("XIVEquip.allow_main_hand_one_hand", profile.allowMH1H)
    builder:SetCapability("XIVEquip.titan_grip", profile.allowTitanGrip)
    builder:SetCapability("XIVEquip.require_shield", profile.requireShield)
  end,
})
