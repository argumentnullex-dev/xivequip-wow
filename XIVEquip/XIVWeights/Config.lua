-- XIVWeights/Config.lua
-- SavedVariables-facing configuration for native XIVWeights resolution.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
local XIVWeights = XIVEquip.XIVWeights

local Config = {}
XIVWeights.Config = Config

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local function settings()
  if XIVEquip.Settings and XIVEquip.Settings.Get then return XIVEquip.Settings:Get() end
  _G.XIVEquip_Settings = _G.XIVEquip_Settings or {}
  return _G.XIVEquip_Settings
end

local function weightsSettings()
  local st = settings()
  st.XIVWeights = type(st.XIVWeights) == "table" and st.XIVWeights or {}
  st.XIVWeights.Scales = type(st.XIVWeights.Scales) == "table" and st.XIVWeights.Scales or {}
  st.XIVWeights.Specs = type(st.XIVWeights.Specs) == "table" and st.XIVWeights.Specs or {}
  st.XIVWeights.Integrations = type(st.XIVWeights.Integrations) == "table" and st.XIVWeights.Integrations or {}
  st.XIVWeights.Integrations.Pawn = type(st.XIVWeights.Integrations.Pawn) == "table" and st.XIVWeights.Integrations.Pawn or {}
  return st.XIVWeights
end

local function generatedID(specID)
  return "spec:" .. tostring(specID)
end

local function normalizeProvider(provider)
  local key = string.lower(tostring(provider or "default"))
  if key == "xivequip" or key == "default" or key == "builtin" then return "default" end
  if key == "manual" then return "manual" end
  if key == "pawn" then return "pawn" end
  return "default"
end

local function normalizeScale(scale)
  scale = copy(scale)
  scale.weights = scale.weights or {}
  scale.meta = scale.meta or {}
  return XIVWeights.NewScale(scale)
end

function Config.GeneratedScaleID(specID)
  return generatedID(specID)
end

function Config.CreateSpecScale(specID)
  local default = XIVWeights.Builtin and XIVWeights.Builtin.Defaults and XIVWeights.Builtin.Defaults.Get(specID)
  if not default then return nil, "missing-default" end
  local scale = normalizeScale(default)
  scale.id = generatedID(specID)
  scale.name = (scale.meta and scale.meta.specName) or scale.name or ("Spec " .. tostring(specID))
  scale.source = {
    kind = "xivequip-default-copy",
    specID = tonumber(specID),
    defaultID = default.id,
    defaultVersion = default.meta and default.meta.defaultVersion,
  }
  scale.meta = scale.meta or {}
  scale.meta.specID = tonumber(specID)
  scale.meta.tiedToSpecID = tonumber(specID)
  scale.meta.generatedFromDefaultID = default.id
  scale.meta.generatedFromDefaultVersion = default.meta and default.meta.defaultVersion
  scale.meta.userEditable = true
  return scale
end

function Config.EnsureSpecScale(specID)
  local xw = weightsSettings()
  local id = generatedID(specID)
  if type(xw.Scales[id]) == "table" then return normalizeScale(xw.Scales[id]) end
  local scale, reason = Config.CreateSpecScale(specID)
  if not scale then return nil, reason end
  xw.Scales[id] = scale
  return scale
end

function Config.EnsureClassSpecScales(classFile)
  local defaults = XIVWeights.Builtin and XIVWeights.Builtin.Defaults
  local specs = defaults and defaults.SpecsForClass(classFile) or {}
  local out = {}
  for _, spec in ipairs(specs) do
    local scale = Config.EnsureSpecScale(spec.id)
    if scale then out[#out + 1] = scale end
  end
  return out
end

function Config.ResetSpecScale(specID)
  local xw = weightsSettings()
  local scale, reason = Config.CreateSpecScale(specID)
  if not scale then return nil, reason end
  xw.Scales[scale.id] = scale
  xw.Specs[tonumber(specID)] = { provider = "manual", scale = scale.id }
  return scale
end

function Config.Repository()
  return XIVWeights.Repository.New(weightsSettings().Scales)
end

function Config.GetSpecSelection(specID)
  local xw = weightsSettings()
  local key = tonumber(specID)
  local sel = type(xw.Specs[key]) == "table" and xw.Specs[key] or nil
  if not sel then
    sel = { provider = "default", scale = nil }
    xw.Specs[key] = sel
  end
  sel.provider = normalizeProvider(sel.provider)
  if sel.provider == "manual" and not sel.scale then sel.scale = generatedID(key) end
  return sel
end

function Config.SetSpecSelection(specID, provider, scaleID)
  local xw = weightsSettings()
  local key = tonumber(specID)
  xw.Specs[key] = {
    provider = normalizeProvider(provider),
    scale = scaleID,
  }
end

function Config.SaveScale(scale)
  assert(scale and scale.id, "XIVWeights.Config.SaveScale requires a scale id")
  local repo = Config.Repository()
  return repo:Save(normalizeScale(scale))
end

function Config.DeleteScale(id)
  return Config.Repository():Delete(id)
end

function Config.CreateManualScale(id, name, weights)
  local scale = XIVWeights.NewScale({
    id = id,
    name = name,
    source = { kind = "manual" },
    weights = weights or { strength = 1.0 },
    meta = { userEditable = true },
  })
  local ok, err = Config.ValidateAuthoredWeights(scale)
  if not ok then return nil, err end
  return Config.SaveScale(scale)
end

function Config.DuplicateScale(sourceID, newID, newName)
  local source = Config.Repository():Get(sourceID)
  if not source then return nil, "Source scale not found." end
  local copyScale = copy(source)
  copyScale.id = newID
  copyScale.name = newName
  copyScale.source = { kind = "manual", duplicatedFrom = sourceID }
  copyScale.meta = copyScale.meta or {}
  copyScale.meta.userEditable = true
  copyScale.meta.duplicatedFrom = sourceID
  return Config.SaveScale(copyScale)
end

function Config.ListManualScales()
  return Config.Repository():List()
end

function Config.ResolveForSpec(specID, runtime)
  local sel = Config.GetSpecSelection(specID)
  local provider = sel.provider
  local scale

  if provider == "default" then
    local defaultProvider = XIVWeights.Providers.Default.New(Config)
    local ok, resolved = pcall(function() return defaultProvider:Resolve(nil, { specID = specID }) end)
    if ok and resolved then scale = resolved end
  elseif provider == "pawn" then
    local pawnProvider = runtime and runtime.PawnProvider and runtime.PawnProvider()
    if pawnProvider then
      local ok, resolved = pcall(function() return pawnProvider:Resolve(sel.scale, { specID = specID }) end)
      if ok and resolved then scale = resolved end
    end
  else
    local repo = Config.Repository()
    local manualProvider = XIVWeights.Providers.Manual.New(repo)
    local id = sel.scale
    id = id or generatedID(specID)
    local ok, resolved = pcall(function() return manualProvider:Resolve(id, { specID = specID }) end)
    if ok and resolved then scale = resolved end
  end

  if not scale then
    scale = XIVWeights.Builtin and XIVWeights.Builtin.Defaults and XIVWeights.Builtin.Defaults.Get(specID)
  end
  if not scale then
    scale = XIVWeights.NewScale({ id = "fallback:empty", source = { kind = "empty" }, weights = {} })
  end

  local default = XIVWeights.Builtin and XIVWeights.Builtin.Defaults and XIVWeights.Builtin.Defaults.Get(specID)
  return XIVWeights.Resolver.Resolve(scale, default)
end

function Config.ValidateAuthoredWeights(scale)
  if type(scale) ~= "table" then return false, "Scale is required." end
  if tostring(scale.name or ""):match("^%s*$") then return false, "Scale name is required." end
  local weights = scale.weights
  if type(weights) ~= "table" then return false, "Scale weights are required." end

  local hasOne = false
  for _, feature in ipairs(XIVWeights.FEATURES or {}) do
    local raw = weights[feature]
    if raw ~= nil then
      local value = tonumber(raw)
      if not value or value < 0 or value > 1 then
        return false, "Weight for " .. tostring(feature) .. " must be between 0 and 1."
      end
      if value == 1 then hasOne = true end
    end
  end
  if not hasOne then return false, "At least one top weight must be exactly 1.0." end
  return true
end
