local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function policy()
  local addon = {}
  Bootstrap.LoadPolicyContext(root, addon)
  for _, declaration in ipairs(addon.Policies.DefaultRegistry:Pending()) do
    if declaration.id == "XIVEquip.candidate_weapon_proficiency" then
      return declaration
    end
  end
  error("weapon proficiency policy was not registered")
end

local function set(...)
  local result = {}
  for i = 1, select("#", ...) do result[select(i, ...)] = true end
  return result
end

-- Exact expected retail matrix across every Enum.ItemWeaponSubclass value.
-- This intentionally duplicates the contract rather than sampling one item per
-- class: adding a class with a permissive fallthrough or one stray subclass
-- must fail visibly.
local EXPECTED = {
  WARRIOR = set(0, 1, 4, 5, 6, 7, 8, 10, 13, 15),
  PALADIN = set(0, 1, 4, 5, 6, 7, 8),
  HUNTER = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 18),
  ROGUE = set(0, 4, 7, 13, 15),
  PRIEST = set(4, 10, 15, 19),
  DEATHKNIGHT = set(0, 1, 4, 5, 6, 7, 8),
  SHAMAN = set(0, 1, 4, 5, 10, 13, 15),
  MAGE = set(7, 10, 15, 19),
  WARLOCK = set(7, 10, 15, 19),
  MONK = set(0, 4, 6, 7, 10, 13),
  DRUID = set(4, 5, 6, 10, 13, 15),
  DEMONHUNTER = set(0, 7, 9, 13),
  EVOKER = set(0, 1, 4, 5, 7, 8, 10, 13, 15),
}

test("weapon proficiency matrix covers every current class and weapon subclass", function()
  local subject = policy()
  for classFile, allowed in pairs(EXPECTED) do
    for subclassID = 0, 20 do
      local result = subject.apply({ equip = { itemClassID = 2, itemSubclassID = subclassID } }, {
        classFile = classFile,
        specID = classFile == "DEMONHUNTER" and 577 or 0,
      })
      if allowed[subclassID] then
        A.equal(result, nil, classFile .. " should allow weapon subclass " .. tostring(subclassID))
      else
        A.truthy(result, classFile .. " should reject weapon subclass " .. tostring(subclassID))
        A.equal(result.reason, "unsupported-weapon-proficiency")
      end
    end
  end
end)

test("Devourer adds dagger proficiency without granting it to Havoc or Vengeance", function()
  local subject = policy()
  local dagger = { equip = { itemClassID = 2, itemSubclassID = 15 } }

  A.equal(subject.apply(dagger, { classFile = "DEMONHUNTER", specID = 1480 }), nil)
  A.truthy(subject.apply(dagger, { classFile = "DEMONHUNTER", specID = 577 }))
  A.truthy(subject.apply(dagger, { classFile = "DEMONHUNTER", specID = 581 }))
end)

test("weapon proficiency policy ignores non-weapons and unknown future classes", function()
  local subject = policy()

  A.equal(subject.apply({ equip = { itemClassID = 4, itemSubclassID = 4 } }, {
    classFile = "PALADIN", specID = 66,
  }), nil)
  A.equal(subject.apply({ equip = { itemClassID = 2, itemSubclassID = 15 } }, {
    classFile = "FUTURECLASS", specID = 9999,
  }), nil)
end)

return tests
