-- tests/scenarios/policies/weapon_overrides.lua
-- Doc section 6, "Weapon-policy override scenarios for 1.2.0" (now the
-- 2.0.0 architecture cycle). These need a per-character weapon-policy
-- override mechanism that doesn't exist yet -- Weapons.lua's
-- policyForSpec() is a pure function of class/spec/dual-wield state with no
-- override input. Written now as skipped placeholders per user decision,
-- so the matrix shape is visible ahead of the 2.0.0 policy pipeline work.
-- Flesh these out (remove `skip`, fill in items/expect) once an override
-- surface exists.

local REASON = "requires 2.0.0 weapon policy override pipeline (not yet implemented)"

return {
  {
    name = "weapon policy override: disabling one-handed weapons for Fury forces the best 2H pair",
    skip = true,
    skipReason = REASON,
    character = { classFile = "WARRIOR", specID = 72, specName = "Fury" },
  },
  {
    name = "weapon policy override: disabling two-handed weapons for Fury forces the best 1H pair",
    skip = true,
    skipReason = REASON,
    character = { classFile = "WARRIOR", specID = 72, specName = "Fury" },
  },
  {
    name = "weapon policy override: disabling one weapon subclass leaves another subclass legal",
    skip = true,
    skipReason = REASON,
  },
  {
    name = "weapon policy override: an explicit override cannot create an impossible game loadout",
    skip = true,
    skipReason = REASON,
  },
  {
    name = "weapon policy override: resetting to default reproduces class/spec default behavior",
    skip = true,
    skipReason = REASON,
  },
  {
    name = "weapon policy override: an override applies only to the configured character/spec",
    skip = true,
    skipReason = REASON,
  },
}
