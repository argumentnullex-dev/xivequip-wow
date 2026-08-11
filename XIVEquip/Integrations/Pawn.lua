-- Pawn integration bridge. This exposes Pawn scale data to XIVWeights without
-- keeping the external provider boundary separate from native scoring.
local addonName, XIVEquip = ...
XIVEquip.Pawn = XIVEquip.Pawn or {}
local Pawn = XIVEquip.Pawn

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
        spec = scale.Spec or scale.SpecIndex,
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

local function bestActiveScale()
  local _, _, classID = UnitClass and UnitClass("player")
  local index = GetSpecialization and GetSpecialization()
  local specName = index and GetSpecializationInfo and select(2, GetSpecializationInfo(index)) or ""
  local normalizedSpec = tostring(specName):lower():gsub("[%s%p]+", "")
  local firstForClass
  for _, scale in ipairs(Pawn.GetActiveScales()) do
    if scale.class == nil or scale.class == classID then
      firstForClass = firstForClass or scale
      local name = tostring(scale.name or scale.key):lower():gsub("[%s%p]+", "")
      if name == normalizedSpec or name:find(normalizedSpec, 1, true) then return scale end
    end
  end
  return firstForClass
end

function Pawn.GetBestActiveScaleForPlayer()
  return bestActiveScale()
end

local function valuesFor(scale)
  if not scale then return nil end
  if type(scale.values) == "table" then return scale.values end
  return providerValues(scale.key or scale.name)
end

function Pawn.GetBestScaleValuesForPlayer()
  local scale = bestActiveScale()
  return valuesFor(scale), scale
end

function Pawn.GetScaleValues(keyOrName)
  if not keyOrName then return Pawn.GetBestScaleValuesForPlayer() end
  for _, scale in ipairs(Pawn.GetActiveScales()) do
    if scale.key == keyOrName or scale.name == keyOrName then
      return valuesFor(scale), scale
    end
  end
  return nil, nil
end
