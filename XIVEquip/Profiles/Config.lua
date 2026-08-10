-- Profile storage and character assignment for the v2 settings model.
local addonName, XIVEquip = ...
XIVEquip.Profiles = XIVEquip.Profiles or {}

local Profiles = {}
XIVEquip.Profiles.Config = Profiles

local function settings()
  if XIVEquip.Settings and XIVEquip.Settings.Get then return XIVEquip.Settings:Get() end
  _G.XIVEquip_Settings = _G.XIVEquip_Settings or {}
  return _G.XIVEquip_Settings
end

local function store()
  local st = settings()
  st.Profiles = type(st.Profiles) == "table" and st.Profiles or {}
  st.Profiles.ModelVersion = 1
  st.Profiles.ByClass = type(st.Profiles.ByClass) == "table" and st.Profiles.ByClass or {}
  st.Profiles.CharacterAssignments = type(st.Profiles.CharacterAssignments) == "table"
      and st.Profiles.CharacterAssignments or {}
  return st.Profiles
end

local function normalizeClass(classFile)
  if not classFile or tostring(classFile) == "" then return nil end
  return string.upper(tostring(classFile))
end

local function normalizeName(value)
  return tostring(value or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function defaultProfile(classFile)
  local normalized = normalizeClass(classFile)
  local id = Profiles.DefaultProfileID(normalized)
  return {
    id = id,
    name = "Default",
    classFile = normalized,
    automatic = true,
    manual = {
      mode = "default",
      customOverrides = {},
      integration = {
        provider = "pawn",
        overrides = {},
      },
    },
  }
end

function Profiles.DefaultProfileID(classFile)
  return string.lower(normalizeClass(classFile) or "unknown") .. ":default"
end

function Profiles.CharacterKey(name, realm)
  name = normalizeName(name)
  realm = normalizeName(realm)
  if name == "" then return nil end
  if realm == "" then realm = "unknown-realm" end
  return name .. "-" .. realm
end

function Profiles.EnsureClass(classFile)
  classFile = normalizeClass(classFile)
  if not classFile then return nil end

  local profiles = store()
  local classStore = profiles.ByClass[classFile]
  if type(classStore) ~= "table" then
    classStore = { DefaultProfileID = Profiles.DefaultProfileID(classFile), Items = {} }
    profiles.ByClass[classFile] = classStore
  end
  classStore.Items = type(classStore.Items) == "table" and classStore.Items or {}

  local defaultID = classStore.DefaultProfileID or Profiles.DefaultProfileID(classFile)
  classStore.DefaultProfileID = defaultID
  local default = classStore.Items[defaultID]
  if type(default) ~= "table" or default.classFile ~= classFile then
    default = defaultProfile(classFile)
    classStore.Items[defaultID] = default
  end
  return classStore
end

function Profiles.GetDefault(classFile)
  local classStore = Profiles.EnsureClass(classFile)
  if not classStore then return nil end
  return classStore.Items[classStore.DefaultProfileID]
end

function Profiles.Get(classFile, profileID)
  local classStore = Profiles.EnsureClass(classFile)
  if not classStore then return nil end
  return classStore.Items[profileID or classStore.DefaultProfileID]
end

function Profiles.AssignCharacter(characterKey, classFile, profileID)
  classFile = normalizeClass(classFile)
  local profile = Profiles.Get(classFile, profileID)
  if not profile then return nil, "unknown-profile" end
  local key = normalizeName(characterKey)
  if key == "" then return nil, "missing-character" end
  store().CharacterAssignments[key] = {
    classFile = classFile,
    profileID = profile.id,
  }
  return profile
end

function Profiles.GetForCharacter(characterKey, classFile)
  classFile = normalizeClass(classFile)
  local default = Profiles.GetDefault(classFile)
  if not default then return nil end
  local assignment = characterKey and store().CharacterAssignments[characterKey] or nil
  if type(assignment) == "table"
      and normalizeClass(assignment.classFile) == classFile then
    local selected = Profiles.Get(classFile, assignment.profileID)
    if selected then return selected end
  end
  if characterKey then
    store().CharacterAssignments[characterKey] = {
      classFile = classFile,
      profileID = default.id,
    }
  end
  return default
end

local function currentContext(runtime)
  runtime = runtime or {}
  local unitClass = runtime.UnitClass or _G.UnitClass
  local unitName = runtime.UnitName or _G.UnitName
  local realmName = runtime.GetRealmName or _G.GetRealmName
  local getSpec = runtime.GetSpecialization or _G.GetSpecialization
  local getSpecInfo = runtime.GetSpecializationInfo or _G.GetSpecializationInfo

  local classFile
  if type(unitClass) == "function" then
    local _, resolvedClass = unitClass("player")
    classFile = resolvedClass
  end

  local name, realm
  if type(unitName) == "function" then name, realm = unitName("player") end
  if (not realm or realm == "") and type(realmName) == "function" then realm = realmName() end

  local specID
  if type(getSpec) == "function" and type(getSpecInfo) == "function" then
    local index = getSpec()
    if index then specID = select(1, getSpecInfo(index)) end
  end

  return {
    classFile = normalizeClass(classFile),
    characterKey = Profiles.CharacterKey(name, realm),
    specID = tonumber(specID),
  }
end

function Profiles.CurrentContext(runtime)
  return currentContext(runtime)
end

function Profiles.EnsureCurrent(runtime)
  local context = currentContext(runtime)
  if not context.classFile then return nil, "class-unavailable" end
  return Profiles.GetForCharacter(context.characterKey, context.classFile), context
end

function Profiles.GetForSpec(specID, runtime)
  local context = currentContext(runtime)
  if not context.classFile then return nil, context end
  local defaults = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Builtin
      and XIVEquip.XIVWeights.Builtin.Defaults
  if defaults and defaults.ClassForSpec then
    context.classFile = defaults.ClassForSpec(specID) or context.classFile
  end
  return Profiles.GetForCharacter(context.characterKey, context.classFile), context
end

function Profiles.List(classFile)
  local classStore = Profiles.EnsureClass(classFile)
  local out = {}
  if not classStore then return out end
  for _, profile in pairs(classStore.Items) do out[#out + 1] = profile end
  table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return out
end

return Profiles
