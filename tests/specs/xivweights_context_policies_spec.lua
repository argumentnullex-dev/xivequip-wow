-- tests/specs/xivweights_context_policies_spec.lua
-- The built-in class/spec-derived context policies, cross-checked against
-- Gear/Weapons.lua's policyForSpec() (lines 33-106) -- the source of truth
-- these were ported from. Weapons.lua itself is untouched; this proves the
-- port is faithful for representative classes/specs.

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function buildContext(character, dualWielding)
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)

  local resolved = addon.Policies.Resolver.Finalize(addon.Policies.DefaultRegistry:Pending())
  -- UnitClass/UnitLevel require a unit token in the real API -- asserting
  -- it here catches a regression to the argument-less call this policy
  -- used to make.
  local runtime = {
    UnitClass = function(unit)
      assert(unit == "player", "UnitClass should be called with the 'player' unit token")
      return character.className or character.classFile, character.classFile, 1
    end,
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return character.specID, character.specName end,
    UnitLevel = function(unit)
      assert(unit == "player", "UnitLevel should be called with the 'player' unit token")
      return 80
    end,
    IsDualWielding = function() return dualWielding == true end,
  }

  return addon.Evaluation.ContextBuilder.BuildContext(resolved, runtime)
end

local function cap(context, name)
  return context.capabilities["XIVEquip." .. name]
end

test("Fury Warrior (spec 72): two-hand, dual-wield, offhand weapon, and Titan's Grip all allowed", function()
  local context = buildContext({ classFile = "WARRIOR", specID = 72, specName = "Fury" })

  A.truthy(cap(context, "allow_two_hand"))
  A.truthy(cap(context, "allow_dual_wield"))
  A.truthy(cap(context, "allow_offhand_weapon"))
  A.truthy(cap(context, "titan_grip"))
  A.falsy(cap(context, "allow_shield"))
  A.falsy(cap(context, "require_shield"))
end)

test("Protection Paladin (spec 66): one-hand and shield required, no two-hand", function()
  local context = buildContext({ classFile = "PALADIN", specID = 66, specName = "Protection" })

  A.falsy(cap(context, "allow_two_hand"))
  A.truthy(cap(context, "allow_main_hand_one_hand"))
  A.truthy(cap(context, "allow_shield"))
  A.truthy(cap(context, "require_shield"))
end)

test("Frost Mage: two-hand, one-hand, and holdable off-hand all allowed (class default, spec-independent)", function()
  local context = buildContext({ classFile = "MAGE", specID = 64, specName = "Frost" })

  A.truthy(cap(context, "allow_two_hand"))
  A.truthy(cap(context, "allow_main_hand_one_hand"))
  A.truthy(cap(context, "allow_holdable"))
  A.falsy(cap(context, "allow_shield"))
end)

test("Guardian Druid (spec 104): two-hand only, no main-hand one-hand", function()
  local context = buildContext({ classFile = "DRUID", specID = 104, specName = "Guardian" })

  A.truthy(cap(context, "allow_two_hand"))
  A.falsy(cap(context, "allow_main_hand_one_hand"))
end)

test("Restoration Druid (spec 105): the DRUID else-branch allows one-hand and holdable", function()
  local context = buildContext({ classFile = "DRUID", specID = 105, specName = "Restoration" })

  A.truthy(cap(context, "allow_two_hand"))
  A.truthy(cap(context, "allow_main_hand_one_hand"))
  A.truthy(cap(context, "allow_holdable"))
end)

test("Enhancement Shaman (spec 263): dual-wield, no two-hand", function()
  local context = buildContext({ classFile = "SHAMAN", specID = 263, specName = "Enhancement" })

  A.falsy(cap(context, "allow_two_hand"))
  A.truthy(cap(context, "allow_dual_wield"))
  A.truthy(cap(context, "allow_offhand_weapon"))
end)

test("Restoration Shaman: the SHAMAN else-branch allows shield and holdable", function()
  local context = buildContext({ classFile = "SHAMAN", specID = 264, specName = "Restoration" })

  A.truthy(cap(context, "allow_shield"))
  A.truthy(cap(context, "allow_holdable"))
  A.falsy(cap(context, "allow_dual_wield"))
end)

test("Rogue: dual-wield, no two-hand, regardless of spec", function()
  local context = buildContext({ classFile = "ROGUE", specID = 259, specName = "Assassination" })

  A.falsy(cap(context, "allow_two_hand"))
  A.truthy(cap(context, "allow_dual_wield"))
  A.truthy(cap(context, "allow_offhand_weapon"))
end)

test("an unmapped/unknown class file falls through to plain defaults", function()
  local context = buildContext({ classFile = "SOMETHING_FUTURE", specID = 1 })

  A.truthy(cap(context, "allow_two_hand"))
  A.truthy(cap(context, "allow_main_hand_one_hand"))
  A.falsy(cap(context, "allow_dual_wield"))
  A.falsy(cap(context, "allow_shield"))
end)

test("armor proficiency subclass matches the class -> plate/mail/leather/cloth map", function()
  A.equal(buildContext({ classFile = "WARRIOR" }).armorProficiencySubclass, 4)
  A.equal(buildContext({ classFile = "HUNTER" }).armorProficiencySubclass, 3)
  A.equal(buildContext({ classFile = "ROGUE" }).armorProficiencySubclass, 2)
  A.equal(buildContext({ classFile = "MAGE" }).armorProficiencySubclass, 1)
end)

test("live dual-wielding overrides a spec that doesn't normally allow it", function()
  local context = buildContext({ classFile = "PALADIN", specID = 66, specName = "Protection" }, true)

  A.truthy(cap(context, "allow_dual_wield"), "the live override should force this true")
  A.truthy(cap(context, "allow_offhand_weapon"), "the live override should force this true")
  A.truthy(cap(context, "allow_shield"), "the class/spec capability set by the earlier policy should be untouched")
end)

test("without live dual-wielding, the override leaves the class/spec default alone", function()
  local context = buildContext({ classFile = "PALADIN", specID = 66, specName = "Protection" }, false)

  A.falsy(cap(context, "allow_dual_wield"))
end)

return tests
