-- Policies/Assignment/WeaponHandLegality.lua
-- Ports Weapons.lua's loadoutLegal (lines 169-187) into a real, registered
-- `assignment`-phase policy -- doc section 15.3 lists "main/offhand
-- compatibility, shield requirement, Titan's Grip" as its canonical
-- Assignment-policy examples, and this is precisely what Phase 2's
-- previously-empty `assignment` phase was built for.
--
-- Reads the exact capability facts Phase 2's ClassSpecWeaponCapabilities/
-- DualWieldOverride context policies already produce
-- (context.capabilities["XIVEquip.*"]) instead of the original's local
-- per-call `P` table -- Weapons.lua's own policyForSpec() is untouched and
-- keeps computing its own copy for the live planner; this is new,
-- parallel infrastructure.
--
-- Physical-item dedup (samePhysical(mh,oh) in the original) is NOT
-- reproduced here -- Assignments/Paired.lua's Evaluate already rejects
-- that generically, before any assignment-phase policy runs, so it would
-- be dead code here.
--
-- canMainHand's "no candidate at all" rejection is conditioned on
-- assignment.emptyAllowed.mh (set only by Groups.lua's frontierPaired,
-- when representing a group's literal current state -- see Paired.lua's
-- isCurrentState doc comment): an empty mainhand is only ever illegal
-- here as a matter of "the solver shouldn't propose going weaponless,"
-- never as a genuine per-spec rule the way e.g. require_shield is (that
-- rule has no exception carved out here, and still fires on a nil
-- offhand regardless of emptyAllowed -- a spec that actually needs a
-- shield and doesn't have one is a real mismatch, not a representability
-- nicety). Ordinary (non-current-state) evaluation never sets
-- emptyAllowed on the assignment at all, so this is a no-op for every
-- transition the solver could ever actually propose -- it only matters
-- for the one caller asking "is the mainhand being empty, BY ITSELF, why
-- this fails."
local addonName, XIVEquip = ...

local MH2H = {
  INVTYPE_2HWEAPON = true,
  INVTYPE_RANGED = true,
  INVTYPE_RANGEDRIGHT = true,
  INVTYPE_THROWN = true,
}

local MH1H = {
  INVTYPE_WEAPON = true,
  INVTYPE_WEAPONMAINHAND = true,
}

local function is2H(equipLoc) return equipLoc and MH2H[equipLoc] == true end
local function is1H(equipLoc) return equipLoc and MH1H[equipLoc] == true end

local function equipLocOf(candidate)
  return candidate and candidate.equip and candidate.equip.equipLoc
end

local function canMainHand(candidate, capabilities, emptyAllowed)
  if not candidate then return emptyAllowed and emptyAllowed.mh == true end
  local equipLoc = equipLocOf(candidate)
  if is2H(equipLoc) then return capabilities["XIVEquip.allow_two_hand"] == true end
  if is1H(equipLoc) then return capabilities["XIVEquip.allow_main_hand_one_hand"] == true end
  return false
end

local function canOffHand(candidate, capabilities)
  if not candidate then return false end
  local equipLoc = equipLocOf(candidate)
  if is2H(equipLoc) then return capabilities["XIVEquip.titan_grip"] == true end
  if equipLoc == "INVTYPE_SHIELD" then return capabilities["XIVEquip.allow_shield"] == true end
  if equipLoc == "INVTYPE_HOLDABLE" then return capabilities["XIVEquip.allow_holdable"] == true end
  if equipLoc == "INVTYPE_WEAPONOFFHAND" then return capabilities["XIVEquip.allow_offhand_weapon"] == true end
  if equipLoc == "INVTYPE_WEAPON" then return capabilities["XIVEquip.allow_dual_wield"] == true end
  return false
end

XIVEquip:RegisterPolicy({
  id = "XIVEquip.weapon_hand_legality",
  phase = "assignment",
  groups = { "weapons" },
  requires = {
    "capability.XIVEquip.allow_two_hand",
    "capability.XIVEquip.allow_main_hand_one_hand",
    "capability.XIVEquip.allow_dual_wield",
    "capability.XIVEquip.allow_offhand_weapon",
    "capability.XIVEquip.allow_shield",
    "capability.XIVEquip.allow_holdable",
    "capability.XIVEquip.titan_grip",
    "capability.XIVEquip.require_shield",
  },
  apply = function(assignment, context)
    local capabilities = (context and context.capabilities) or {}
    local mh, oh = assignment.picks.mh, assignment.picks.oh

    if not canMainHand(mh, capabilities, assignment.emptyAllowed) then
      return false, "mainhand item is not a legal main-hand weapon for this spec"
    end

    if not oh then
      if capabilities["XIVEquip.require_shield"] then
        return false, "this spec requires a shield in the offhand"
      end
      return true
    end

    if not canOffHand(oh, capabilities) then
      return false, "offhand item is not legal for this spec"
    end

    local ohEquipLoc = equipLocOf(oh)
    if capabilities["XIVEquip.require_shield"] and ohEquipLoc ~= "INVTYPE_SHIELD" then
      return false, "this spec requires a shield in the offhand"
    end

    if is2H(equipLocOf(mh)) or is2H(ohEquipLoc) then
      if capabilities["XIVEquip.titan_grip"] ~= true then
        return false, "a two-handed weapon in either hand requires Titan's Grip"
      end
    end

    return true
  end,
})
