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

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

local function profileNameExists(classStore, name, exceptID)
  name = string.lower(normalizeName(name))
  for id, profile in pairs(classStore.Items or {}) do
    if id ~= exceptID and string.lower(normalizeName(profile.name)) == name then return true end
  end
  return false
end

local function profileID(classFile, classStore)
  local prefix = string.lower(normalizeClass(classFile)) .. ":profile:"
  local number = 1
  while classStore.Items[prefix .. tostring(number)] do number = number + 1 end
  return prefix .. tostring(number)
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

function Profiles.Create(classFile, name, sourceID)
  local classStore = Profiles.EnsureClass(classFile)
  if not classStore then return nil, "class-unavailable" end
  name = normalizeName(name)
  if name == "" then return nil, "missing-name" end
  if profileNameExists(classStore, name) then return nil, "duplicate-name" end

  local profile
  if sourceID then
    local source = classStore.Items[sourceID]
    if not source then return nil, "unknown-profile" end
    profile = copy(source)
  else
    profile = defaultProfile(classFile)
  end
  profile.id = profileID(classFile, classStore)
  profile.name = name
  profile.classFile = normalizeClass(classFile)
  classStore.Items[profile.id] = profile
  return profile
end

function Profiles.Duplicate(classFile, sourceID, name)
  local source = Profiles.Get(classFile, sourceID)
  if not source then return nil, "unknown-profile" end
  return Profiles.Create(classFile, name, source.id)
end

function Profiles.Rename(classFile, profileIDValue, name)
  local classStore = Profiles.EnsureClass(classFile)
  local profile = classStore and classStore.Items[profileIDValue]
  if not profile then return nil, "unknown-profile" end
  name = normalizeName(name)
  if name == "" then return nil, "missing-name" end
  if profileNameExists(classStore, name, profile.id) then return nil, "duplicate-name" end
  profile.name = name
  return profile
end

function Profiles.Delete(classFile, profileIDValue)
  local classStore = Profiles.EnsureClass(classFile)
  if not classStore then return nil, "class-unavailable" end
  if profileIDValue == classStore.DefaultProfileID then return nil, "default-profile" end
  if not classStore.Items[profileIDValue] then return nil, "unknown-profile" end

  classStore.Items[profileIDValue] = nil
  local assignments = store().CharacterAssignments
  for characterKey, assignment in pairs(assignments) do
    if type(assignment) == "table"
        and normalizeClass(assignment.classFile) == normalizeClass(classFile)
        and assignment.profileID == profileIDValue then
      assignments[characterKey] = {
        classFile = normalizeClass(classFile),
        profileID = classStore.DefaultProfileID,
      }
    end
  end
  return true
end

function Profiles.Usage(classFile, profileIDValue)
  local profile = Profiles.Get(classFile, profileIDValue)
  if not profile then return nil end
  local characters = {}
  for characterKey, assignment in pairs(store().CharacterAssignments) do
    if type(assignment) == "table"
        and normalizeClass(assignment.classFile) == normalizeClass(classFile)
        and assignment.profileID == profile.id then
      characters[#characters + 1] = characterKey
    end
  end
  table.sort(characters)
  return { count = #characters, characters = characters }
end

local function manualState(profile)
  if type(profile) ~= "table" then return nil end
  profile.manual = type(profile.manual) == "table" and profile.manual or {}
  profile.manual.customOverrides = type(profile.manual.customOverrides) == "table"
      and profile.manual.customOverrides or {}
  profile.manual.integration = type(profile.manual.integration) == "table"
      and profile.manual.integration or {}
  profile.manual.integration.provider = profile.manual.integration.provider or "pawn"
  profile.manual.integration.overrides = type(profile.manual.integration.overrides) == "table"
      and profile.manual.integration.overrides or {}
  return profile.manual
end

function Profiles.SetAutomatic(profile, enabled)
  if type(profile) ~= "table" then return nil, "profile-required" end
  profile.automatic = enabled == true
  return profile
end

function Profiles.SetManualMode(profile, mode)
  local manual = manualState(profile)
  mode = string.lower(tostring(mode or ""))
  if not manual then return nil, "profile-required" end
  if mode ~= "default" and mode ~= "custom" and mode ~= "integration" then
    return nil, "invalid-manual-mode"
  end
  manual.mode = mode
  return profile
end

function Profiles.SetCustomOverride(profile, specID, scaleID)
  local manual = manualState(profile)
  if not manual then return nil, "profile-required" end
  specID = tonumber(specID)
  if not specID then return nil, "spec-required" end
  local config = XIVEquip.XIVWeights and XIVEquip.XIVWeights.Config
  local scale = config and config.Repository and config.Repository():Get(scaleID)
  if not scale then return nil, "unknown-scale" end
  local owner = config.GetScaleSpecID and config.GetScaleSpecID(scale)
  if owner ~= specID then return nil, "scale-spec-mismatch" end
  manual.customOverrides[specID] = scaleID
  return profile
end

function Profiles.ClearCustomOverride(profile, specID)
  local manual = manualState(profile)
  if not manual then return nil, "profile-required" end
  manual.customOverrides[tonumber(specID)] = nil
  return profile
end

function Profiles.ClearCustomScaleReferences(scaleID)
  local profiles = store()
  for _, classStore in pairs(profiles.ByClass) do
    for _, profile in pairs((classStore and classStore.Items) or {}) do
      local manual = manualState(profile)
      for specID, selectedID in pairs(manual.customOverrides) do
        if selectedID == scaleID then manual.customOverrides[specID] = nil end
      end
    end
  end
end

function Profiles.SetIntegrationProvider(profile, providerID)
  local manual = manualState(profile)
  if not manual then return nil, "profile-required" end
  providerID = tostring(providerID or "")
  local registry = XIVEquip.Integrations and XIVEquip.Integrations.Registry
  if providerID == "" or not (registry and registry:Get(providerID)) then
    return nil, "unknown-integration"
  end
  manual.integration.provider = providerID
  return profile
end

function Profiles.SetIntegrationOverride(profile, specID, externalScaleID)
  local manual = manualState(profile)
  if not manual then return nil, "profile-required" end
  specID = tonumber(specID)
  externalScaleID = tostring(externalScaleID or "")
  if not specID then return nil, "spec-required" end
  if externalScaleID == "" then return nil, "scale-required" end
  manual.integration.overrides[specID] = externalScaleID
  return profile
end

function Profiles.ClearIntegrationOverride(profile, specID)
  local manual = manualState(profile)
  if not manual then return nil, "profile-required" end
  manual.integration.overrides[tonumber(specID)] = nil
  return profile
end

return Profiles
