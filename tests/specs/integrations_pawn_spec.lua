local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function loadPawn()
  local addon = {}
  local chunk = assert(loadfile(root .. sep .. "XIVEquip" .. sep .. "Integrations" .. sep .. "Pawn.lua"))
  chunk("XIVEquip", addon)
  return addon
end

local function installPaladinGlobals()
  _G.PawnPlayerFullName = "Talkamar-Wyrmrest Accord"
  _G.UnitName = function() return "Talkamar" end
  _G.GetRealmName = function() return "Wyrmrest Accord" end
  _G.UnitClass = function() return "Paladin", "PALADIN", 2 end
  _G.GetSpecialization = function() return 2 end
  _G.GetSpecializationInfo = function(index)
    if index == 1 then return 65, "Holy" end
    if index == 2 then return 66, "Protection" end
    if index == 3 then return 70, "Retribution" end
    return nil
  end
end

local function clearGlobals()
  _G.PawnCommon = nil
  _G.PawnPlayerFullName = nil
  _G.PawnGetScaleValues = nil
  _G.PawnGetProviderScaleValues = nil
  _G.Pawn = nil
  _G.UnitName = nil
  _G.GetRealmName = nil
  _G.UnitClass = nil
  _G.GetSpecialization = nil
  _G.GetSpecializationInfo = nil
end

local function paladinScales()
  return {
    ["Retribution"] = {
      LocalizedName = "Retribution",
      ClassID = 2,
      SpecID = 3,
      PerCharacterOptions = {
        ["Talkamar-Wyrmrest Accord"] = { Visible = true },
      },
      Values = { Strength = 10, HasteRating = 5 },
    },
    ["\"MrRobot\":PALADIN2"] = {
      LocalizedName = "Paladin: Protection",
      ClassID = 2,
      SpecID = 2,
      Provider = "MrRobot",
      PerCharacterOptions = {},
    },
    ["\"MrRobot\":PALADIN3"] = {
      LocalizedName = "Paladin: Retribution",
      ClassID = 2,
      SpecID = 3,
      Provider = "MrRobot",
      PerCharacterOptions = {},
    },
  }
end

test("Pawn bridge reads SpecID from saved scales", function()
  clearGlobals()
  installPaladinGlobals()
  _G.PawnCommon = { Scales = paladinScales() }
  local addon = loadPawn()

  local byName = {}
  for _, scale in ipairs(addon.Pawn.GetAllScales()) do byName[scale.name] = scale end

  A.equal(byName["Paladin: Protection"].spec, 2)
  A.equal(byName["Paladin: Retribution"].spec, 3)
end)

test("automatic Pawn selection prefers active class and specialization match", function()
  clearGlobals()
  installPaladinGlobals()
  _G.GetSpecialization = function() return 3 end
  _G.PawnCommon = { Scales = paladinScales() }
  local addon = loadPawn()

  local values, entry = addon.Pawn.GetBestScaleValuesForPlayer()

  A.equal(entry.name, "Retribution")
  A.equal(values.Strength, 10)
end)

test("automatic Pawn selection can use a provider scale by class and spec when no active custom scale matches", function()
  clearGlobals()
  installPaladinGlobals()
  _G.PawnCommon = { Scales = paladinScales() }
  _G.PawnGetScaleValues = function(key)
    if key == "\"MrRobot\":PALADIN2" then return { Strength = 20, Armor = 7 } end
  end
  local addon = loadPawn()

  local values, entry = addon.Pawn.GetBestScaleValuesForPlayer()

  A.equal(entry.name, "Paladin: Protection")
  A.equal(entry.key, "\"MrRobot\":PALADIN2")
  A.equal(values.Strength, 20)
end)

test("explicit Pawn scale lookup is not limited to visible active scales", function()
  clearGlobals()
  installPaladinGlobals()
  _G.PawnCommon = { Scales = paladinScales() }
  _G.PawnGetScaleValues = function(key)
    if key == "\"MrRobot\":PALADIN2" then return { Strength = 20, Armor = 7 } end
  end
  local addon = loadPawn()

  local values, entry = addon.Pawn.GetScaleValues("\"MrRobot\":PALADIN2")

  A.equal(entry.name, "Paladin: Protection")
  A.equal(values.Armor, 7)
end)

return tests
