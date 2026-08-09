-- tests/specs/weapon_hand_legality_policy_spec.lua
-- The registered XIVEquip.weapon_hand_legality assignment policy
-- (Policies/Assignment/WeaponHandLegality.lua), ported verbatim from
-- Weapons.lua's loadoutLegal -- exercised directly against representative
-- capability contexts, independent of the rest of the solver.

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function newAddon()
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  return addon
end

local function findPolicy(addon)
  for _, decl in ipairs(addon.Policies.DefaultRegistry:Pending()) do
    if decl.id == "XIVEquip.weapon_hand_legality" then return decl end
  end
  error("policy not registered")
end

local function weapon(equipLoc, physicalID)
  return { equip = { equipLoc = equipLoc }, physicalID = physicalID }
end

local function capContext(overrides)
  local capabilities = {
    ["XIVEquip.allow_two_hand"] = false,
    ["XIVEquip.allow_main_hand_one_hand"] = false,
    ["XIVEquip.allow_dual_wield"] = false,
    ["XIVEquip.allow_offhand_weapon"] = false,
    ["XIVEquip.allow_shield"] = false,
    ["XIVEquip.allow_holdable"] = false,
    ["XIVEquip.titan_grip"] = false,
    ["XIVEquip.require_shield"] = false,
  }
  for k, v in pairs(overrides or {}) do capabilities[k] = v end
  return { capabilities = capabilities }
end

test("Fury (Titan's Grip): two two-handers in both hands is legal", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_two_hand"] = true, ["XIVEquip.titan_grip"] = true })

  local ok = policy.apply({ picks = { mh = weapon("INVTYPE_2HWEAPON"), oh = weapon("INVTYPE_2HWEAPON") } }, context)

  A.truthy(ok)
end)

test("Fury (Titan's Grip): a two-hander plus a one-hander offhand is legal", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({
    ["XIVEquip.allow_two_hand"] = true, ["XIVEquip.titan_grip"] = true, ["XIVEquip.allow_dual_wield"] = true,
  })

  local ok = policy.apply({ picks = { mh = weapon("INVTYPE_2HWEAPON"), oh = weapon("INVTYPE_WEAPON") } }, context)

  A.truthy(ok)
end)

test("without Titan's Grip, a two-hander plus anything in the offhand is illegal", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_two_hand"] = true, ["XIVEquip.allow_dual_wield"] = true })

  local ok = policy.apply({ picks = { mh = weapon("INVTYPE_2HWEAPON"), oh = weapon("INVTYPE_WEAPON") } }, context)

  A.falsy(ok)
end)

test("without Titan's Grip, a two-hander alone (no offhand) is legal", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_two_hand"] = true })

  local ok = policy.apply({ picks = { mh = weapon("INVTYPE_2HWEAPON"), oh = nil } }, context)

  A.truthy(ok)
end)

test("without Titan's Grip, a two-hander may clear an occupied offhand as a game side effect", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_two_hand"] = true })

  local ok = policy.apply({
    picks = { mh = weapon("INVTYPE_2HWEAPON"), oh = nil },
    currentBySlot = { [17] = weapon("INVTYPE_SHIELD") },
  }, context)

  A.truthy(ok)
end)

test("without Titan's Grip, a currently equipped two-hander cannot pretend to clear an occupied offhand", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_two_hand"] = true })
  local currentMH = weapon("INVTYPE_2HWEAPON", "mh-current")
  local currentOH = weapon("INVTYPE_2HWEAPON", "oh-current")

  local ok = policy.apply({
    picks = { mh = currentMH, oh = nil },
    currentBySlot = { [16] = currentMH, [17] = currentOH },
  }, context)

  A.falsy(ok)
end)

test("nil offhand does not remove an occupied offhand when the mainhand equip will not clear it", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({
    ["XIVEquip.allow_main_hand_one_hand"] = true,
    ["XIVEquip.allow_dual_wield"] = true,
  })

  local ok = policy.apply({
    picks = { mh = weapon("INVTYPE_WEAPON"), oh = nil },
    currentBySlot = { [17] = weapon("INVTYPE_WEAPON") },
  }, context)

  A.falsy(ok)
end)

test("Titan's Grip nil offhand does not remove an occupied offhand", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_two_hand"] = true, ["XIVEquip.titan_grip"] = true })

  local ok = policy.apply({
    picks = { mh = weapon("INVTYPE_2HWEAPON"), oh = nil },
    currentBySlot = { [17] = weapon("INVTYPE_2HWEAPON") },
  }, context)

  A.falsy(ok)
end)

test("a spec that requires a shield rejects a non-shield offhand", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({
    ["XIVEquip.allow_main_hand_one_hand"] = true, ["XIVEquip.allow_shield"] = true, ["XIVEquip.require_shield"] = true,
  })

  local ok = policy.apply({ picks = { mh = weapon("INVTYPE_WEAPONMAINHAND"), oh = weapon("INVTYPE_HOLDABLE") } }, context)

  A.falsy(ok)
end)

test("a spec that requires a shield accepts a shield offhand", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({
    ["XIVEquip.allow_main_hand_one_hand"] = true, ["XIVEquip.allow_shield"] = true, ["XIVEquip.require_shield"] = true,
  })

  local ok = policy.apply({ picks = { mh = weapon("INVTYPE_WEAPONMAINHAND"), oh = weapon("INVTYPE_SHIELD") } }, context)

  A.truthy(ok)
end)

test("a spec that requires a shield rejects an empty offhand", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_main_hand_one_hand"] = true, ["XIVEquip.require_shield"] = true })

  local ok = policy.apply({ picks = { mh = weapon("INVTYPE_WEAPONMAINHAND"), oh = nil } }, context)

  A.falsy(ok)
end)

test("dual wield allows two one-handers", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({
    ["XIVEquip.allow_main_hand_one_hand"] = true, ["XIVEquip.allow_dual_wield"] = true,
  })

  local ok = policy.apply({ picks = { mh = weapon("INVTYPE_WEAPON"), oh = weapon("INVTYPE_WEAPON") } }, context)

  A.truthy(ok)
end)

test("a two-hander is illegal in the mainhand when the spec doesn't allow two-handers", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_main_hand_one_hand"] = true })

  local ok = policy.apply({ picks = { mh = weapon("INVTYPE_2HWEAPON"), oh = nil } }, context)

  A.falsy(ok)
end)

test("a one-hander is illegal in the mainhand when the spec only allows two-handers", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_two_hand"] = true })

  local ok = policy.apply({ picks = { mh = weapon("INVTYPE_WEAPONMAINHAND"), oh = nil } }, context)

  A.falsy(ok)
end)

test("an empty mainhand is illegal by default, even with an offhand item present", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_shield"] = true })

  local ok = policy.apply({ picks = { mh = nil, oh = weapon("INVTYPE_SHIELD") } }, context)

  A.falsy(ok)
end)

test("an empty mainhand is legal ONLY when the assignment's own emptyAllowed.mh explicitly permits it", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_shield"] = true })

  local ok = policy.apply(
    { picks = { mh = nil, oh = weapon("INVTYPE_SHIELD") }, emptyAllowed = { mh = true } }, context)

  A.truthy(ok)
end)

test("emptyAllowed.mh never excuses a REAL mainhand item that a spec actually rejects", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_main_hand_one_hand"] = true })

  -- Even with emptyAllowed.mh true, a two-hander in the mainhand is still
  -- illegal for a spec that doesn't allow two-handers -- the hint only
  -- ever matters when the pick is actually nil.
  local ok = policy.apply(
    { picks = { mh = weapon("INVTYPE_2HWEAPON"), oh = nil }, emptyAllowed = { mh = true } }, context)

  A.falsy(ok)
end)

test("emptyAllowed.mh does not excuse a required-shield violation on an empty offhand", function()
  local addon = newAddon()
  local policy = findPolicy(addon)
  local context = capContext({ ["XIVEquip.allow_main_hand_one_hand"] = true, ["XIVEquip.require_shield"] = true })

  -- A genuinely empty mainhand is excused, but the spec's real shield
  -- requirement on the OFFHAND is a separate, unrelated rule that must
  -- still fire.
  local ok = policy.apply({ picks = { mh = nil, oh = nil }, emptyAllowed = { mh = true, oh = true } }, context)

  A.falsy(ok)
end)

return tests
