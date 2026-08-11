-- Pawn integration bridge. This exposes Pawn scale data to XIVWeights without
-- keeping the external provider boundary separate from native scoring.
local addonName, XIVEquip = ...
XIVEquip.Pawn = XIVEquip.Pawn or {}
local Pawn = XIVEquip.Pawn

local CLASS_ID_BY_FILE = {
  WARRIOR = 1,
  PALADIN = 2,
  HUNTER = 3,
  ROGUE = 4,
  PRIEST = 5,
  DEATHKNIGHT = 6,
  SHAMAN = 7,
  MAGE = 8,
  WARLOCK = 9,
  MONK = 10,
  DRUID = 11,
  DEMONHUNTER = 12,
  EVOKER = 13,
}

local function allSavedScales()
  local common = rawget(_G, "PawnCommon")
  return type(common) == "table" and type(common.Scales) == "table" and common.Scales or {}
end

local function characterKey()
  if type(_G.PawnPlayerFullName) == "string" and _G.PawnPlayerFullName ~= "" then
    return _G.PawnPlayerFullName
  end
  local name = UnitName and UnitName("player")
  local realm = GetRealmName and GetRealmName()
  return name and realm and (name .. "-" .. realm) or nil
end

local function visibleForPlayer(options)
  local key = characterKey()
  local option = key and type(options) == "table" and options[key]
  return type(option) == "table" and option.Visible == true
end

local function normalized(value)
  return tostring(value or ""):lower():gsub("[%s%p]+", "")
end

local function contextFromSpecID(specID)
  local defaults = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Builtin and XIVEquip.XIVWeights.Builtin.Defaults
  local scale = defaults and defaults.Get and defaults.Get(tonumber(specID))
  local meta = scale and scale.meta or {}
  local classFile = meta.classFile
  local classID = CLASS_ID_BY_FILE[classFile]
  local specIndex
  for index, spec in ipairs((defaults and defaults.SpecsForClass and defaults.SpecsForClass(classFile)) or {}) do
    if tonumber(spec.id) == tonumber(specID) then
      specIndex = index
      break
    end
  end
  return classID, specIndex, normalized(meta.specName or scale and scale.name)
end

local function playerScaleContext(context)
  if context and context.specID then
    local classID, specIndex, specName = contextFromSpecID(context.specID)
    if classID or specIndex or specName ~= "" then return classID, specIndex, specName end
  end
  if context and (context.classID or context.specIndex or context.specName) then
    return tonumber(context.classID), tonumber(context.specIndex), normalized(context.specName)
  end
  local _, _, classID = UnitClass and UnitClass("player")
  local specIndex = GetSpecialization and GetSpecialization()
  local specName = specIndex and GetSpecializationInfo and select(2, GetSpecializationInfo(specIndex)) or ""
  return tonumber(classID), tonumber(specIndex), normalized(specName)
end

function Pawn.GetAllScales()
  local result = {}
  for key, scale in pairs(allSavedScales()) do
    if type(scale) == "table" then
      local values = type(scale.Values) == "table" and scale.Values or nil
      result[#result + 1] = {
        key = scale.Key or scale.Tag or key,
        name = scale.LocalizedName or scale.PrettyName or scale.Name or key,
        type = values and "custom" or (type(scale.Provider) == "string" and "provider" or "unknown"),
        source = values and "SV" or "API",
        active = visibleForPlayer(scale.PerCharacterOptions),
        values = values,
        class = scale.ClassID or scale.Class,
        -- Pawn SavedVariables use SpecID for the class-local specialization
        -- index returned by GetSpecialization(), not Blizzard's global spec ID.
        spec = scale.SpecID or scale.Spec or scale.SpecIndex,
      }
    end
  end
  return result
end

function Pawn.GetActiveScales()
  local result = {}
  for _, scale in ipairs(Pawn.GetAllScales()) do
    if scale.active then result[#result + 1] = scale end
  end
  return result
end

local function providerValues(key)
  local candidates = {
    _G.PawnGetScaleValues,
    _G.PawnGetProviderScaleValues,
    _G.Pawn and _G.Pawn.GetScaleValues,
    _G.Pawn and _G.Pawn.GetProviderScaleValues,
  }
  for _, fn in ipairs(candidates) do
    if type(fn) == "function" then
      local ok, values = pcall(fn, key)
      if ok and type(values) == "table" then return values end
    end
  end
  return nil
end

local function classMatches(scale, classID)
  local scaleClass = tonumber(scale and scale.class)
  return scaleClass == nil or classID == nil or scaleClass == classID
end

local function specMatches(scale, specIndex)
  local scaleSpec = tonumber(scale and scale.spec)
  return scaleSpec ~= nil and specIndex ~= nil and scaleSpec == specIndex
end

local function nameMatches(scale, normalizedSpec)
  if normalizedSpec == "" then return false end
  local name = normalized(scale and (scale.name or scale.key))
  return name == normalizedSpec or name:find(normalizedSpec, 1, true) ~= nil
end

local function exactMatch(scales, classID, specIndex, normalizedSpec)
  for _, scale in ipairs(scales or {}) do
    if classMatches(scale, classID) then
      if specMatches(scale, specIndex) then return scale end
    end
  end
  for _, scale in ipairs(scales or {}) do
    if classMatches(scale, classID) and nameMatches(scale, normalizedSpec) then return scale end
  end
  return nil
end

local function firstClassMatch(scales, classID)
  for _, scale in ipairs(scales or {}) do
    if classMatches(scale, classID) then return scale end
  end
  return nil
end

local function bestScaleForPlayer(context)
  local classID, specIndex, normalizedSpec = playerScaleContext(context)
  local active = Pawn.GetActiveScales()
  local all = Pawn.GetAllScales()
  return exactMatch(active, classID, specIndex, normalizedSpec)
      or exactMatch(all, classID, specIndex, normalizedSpec)
      or firstClassMatch(active, classID)
      or firstClassMatch(all, classID)
end

function Pawn.GetBestActiveScaleForPlayer(context)
  return bestScaleForPlayer(context)
end

local function valuesFor(scale)
  if not scale then return nil end
  if type(scale.values) == "table" then return scale.values end
  return providerValues(scale.key or scale.name)
end

function Pawn.GetBestScaleValuesForPlayer(context)
  local scale = bestScaleForPlayer(context)
  return valuesFor(scale), scale
end

function Pawn.GetScaleValues(keyOrName, context)
  if not keyOrName then return Pawn.GetBestScaleValuesForPlayer(context) end
  for _, scale in ipairs(Pawn.GetAllScales()) do
    if scale.key == keyOrName or scale.name == keyOrName then
      return valuesFor(scale), scale
    end
  end
  return nil, nil
end
