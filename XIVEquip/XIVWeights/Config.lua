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

local function profilesConfig()
  return XIVEquip.Profiles and XIVEquip.Profiles.Config
end

local function integrationsRegistry()
  return XIVEquip.Integrations and XIVEquip.Integrations.Registry
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

local function builtinForSpec(specID)
  return XIVWeights.Builtin and XIVWeights.Builtin.Defaults and XIVWeights.Builtin.Defaults.Get(tonumber(specID))
end

function Config.SpecName(specID)
  local default = builtinForSpec(specID)
  return default and default.meta and default.meta.specName or default and default.name or nil
end

local function scaleName(scale, fallback)
  if not scale then return fallback end
  return scale.name or (scale.meta and scale.meta.specName) or fallback
end

function Config.ScaleDisplayName(scaleOrID, fallback)
  if type(scaleOrID) == "table" then return scaleName(scaleOrID, fallback) end
  if type(scaleOrID) == "string" then
    local scale = Config.Repository():Get(scaleOrID)
    return scaleName(scale, fallback or scaleOrID)
  end
  return fallback
end

function Config.ResolvedScaleSourceLabel(scale)
  if scale and scale.resolution then
    local resolution = scale.resolution
    local label = tostring(resolution.sourceLabel or "Default")
    local scaleLabel = tostring(resolution.scaleLabel or scaleName(scale, "current spec"))
    if resolution.fallback then label = label .. " (Fallback)" end
    return label .. ": " .. scaleLabel
  end
  local source = scale and scale.source or {}
  local specName = scaleName(scale, source.specID and Config.SpecName(source.specID) or nil)
  if source.kind == "pawn" then return "Pawn: " .. tostring(scaleName(scale, source.key or "selected scale")) end
  if source.kind == "xivequip-default" then return "Built-in default: " .. tostring(specName or "current spec") end
  if source.kind == "xivequip-default-copy" then return "Custom spec scale: " .. tostring(specName or "current spec") end
  if source.kind == "manual" then return "Manual scale: " .. tostring(scaleName(scale, scale and scale.id or "selected scale")) end
  if source.kind == "empty" then return "No weights" end
  return "XIVWeights"
end

function Config.ResolvedScaleDisplayLabel(scale)
  local resolution = scale and scale.resolution or {}
  local sourceLabel = tostring(resolution.sourceLabel or "Default")
  local scaleLabel = tostring(resolution.scaleLabel or scaleName(scale, "current specialization"))
  if sourceLabel == "Custom" and resolution.defaultCopy == true then
    scaleLabel = "Default (" .. scaleLabel .. ")"
  end
  return sourceLabel .. " | " .. scaleLabel
end

function Config.SelectionDisplay(specID, selection, pawnEntries)
  selection = selection or Config.GetSpecSelection(specID)
  local provider = normalizeProvider(selection and selection.provider)
  local specName = Config.SpecName(specID) or ("Spec " .. tostring(specID or "unknown"))

  if provider == "default" then
    local default = builtinForSpec(specID)
    return "Built-in default", scaleName(default, specName)
  end

  if provider == "pawn" then
    local selected = selection and selection.scale
    for _, entry in ipairs(pawnEntries or {}) do
      if entry and (entry.key == selected or entry.name == selected) then
        return "Pawn", tostring(entry.name or entry.key)
      end
    end
    return "Pawn", tostring(selected or "selected scale")
  end

  local scaleID = selection and selection.scale or generatedID(specID)
  return "Manual scale", Config.ScaleDisplayName(scaleID, specName)
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

function Config.GetScaleSpecID(scale)
  if type(scale) ~= "table" then return nil end
  local meta = type(scale.meta) == "table" and scale.meta or {}
  local source = type(scale.source) == "table" and scale.source or {}
  return tonumber(meta.specID or meta.tiedToSpecID or source.specID)
end

local function normalizeProfileIntegration(provider)
  local value = tostring(provider or "pawn")
  if value == "" then return "pawn" end
  return value
end

function Config.GetProfileSelection(specID, runtime)
  local Profiles = profilesConfig()
  if not Profiles then return nil, nil end

  local profile, context = Profiles.GetForSpec(specID, runtime)
  if not profile then return nil, context end

  if profile.automatic ~= false then
    return {
      provider = "automatic",
      scale = nil,
      mode = "automatic",
      profile = profile,
    }, context
  end

  local manual = type(profile.manual) == "table" and profile.manual or {}
  local mode = string.lower(tostring(manual.mode or "default"))
  if mode == "custom" then
    local overrides = type(manual.customOverrides) == "table" and manual.customOverrides or {}
    local selected = overrides[tonumber(specID)]
    return {
      provider = selected and "manual" or "default",
      scale = selected,
      mode = "custom",
      profile = profile,
    }, context
  end

  if mode == "integration" then
    local integration = type(manual.integration) == "table" and manual.integration or {}
    local overrides = type(integration.overrides) == "table" and integration.overrides or {}
    return {
      provider = normalizeProfileIntegration(integration.provider or "pawn"),
      scale = overrides[tonumber(specID)],
      mode = "integration",
      profile = profile,
    }, context
  end

  return {
    provider = "default",
    scale = nil,
    mode = "default",
    profile = profile,
  }, context
end

function Config.ListIntegrations()
  local registry = integrationsRegistry()
  return registry and registry:List() or {}
end

function Config.SaveScale(scale)
  assert(scale and scale.id, "XIVWeights.Config.SaveScale requires a scale id")
  local sourceKind = scale.source and scale.source.kind
  if sourceKind == "manual" or sourceKind == "xivequip-default-copy" then
    local specID = Config.GetScaleSpecID(scale)
    if not specID then return nil, "scale-spec-required" end
    scale.meta = scale.meta or {}
    scale.meta.specID = specID
  end
  local repo = Config.Repository()
  return repo:Save(normalizeScale(scale))
end

function Config.DeleteScale(id)
  local deleted = Config.Repository():Delete(id)
  if deleted and XIVEquip.Profiles and XIVEquip.Profiles.Config
      and XIVEquip.Profiles.Config.ClearCustomScaleReferences then
    XIVEquip.Profiles.Config.ClearCustomScaleReferences(id)
  end
  return deleted
end

function Config.CreateManualScale(id, name, weights, specID)
  specID = tonumber(specID)
  if not specID then return nil, "spec-required" end
  local default = builtinForSpec(specID)
  if not default then return nil, "unknown-spec" end
  weights = weights or copy(default.weights)
  local scale = XIVWeights.NewScale({
    id = id,
    name = name,
    source = { kind = "manual" },
    weights = weights,
    meta = {
      userEditable = true,
      specID = specID,
      classFile = default and default.meta and default.meta.classFile or nil,
      specName = default and default.meta and default.meta.specName or nil,
    },
  })
  local ok, err = Config.ValidateAuthoredWeights(scale)
  if not ok then return nil, err end
  return Config.SaveScale(scale)
end

function Config.DuplicateScale(sourceID, newID, newName)
  local source = Config.Repository():Get(sourceID)
  if not source then return nil, "Source scale not found." end
  local specID = Config.GetScaleSpecID(source)
  if not specID then return nil, "Source scale has no specialization owner." end
  local copyScale = copy(source)
  copyScale.id = newID
  copyScale.name = newName
  copyScale.source = { kind = "manual", duplicatedFrom = sourceID }
  copyScale.meta = copyScale.meta or {}
  copyScale.meta.userEditable = true
  copyScale.meta.duplicatedFrom = sourceID
  copyScale.meta.specID = specID
  return Config.SaveScale(copyScale)
end

function Config.NewManualScaleSeed(specID)
  local default = builtinForSpec(specID)
  if default and default.weights then return copy(default.weights) end
  local defaults = XIVWeights.Builtin and XIVWeights.Builtin.Defaults
  local primary = defaults and defaults.PrimaryForSpec and defaults.PrimaryForSpec(specID) or nil
  primary = primary or "strength"
  return { [primary] = 1.0 }
end

function Config.ListManualScales()
  return Config.Repository():List()
end

local function resolveSelection(specID, sel, runtime)
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

  return scale
end

function Config.ResolveResultForSpec(specID, runtime)
  local profileSelection, context = Config.GetProfileSelection(specID, runtime)
  local sel = profileSelection or Config.GetSpecSelection(specID)
  local configuredSelection = copy(sel)
  local fallback = false
  local fallbackReason
  local scale

  local integrationEntry
  if sel.provider == "automatic" then
    local registry = integrationsRegistry()
    if registry then
      local automaticEntry
      scale, automaticEntry = registry:ResolveAutomatic({ specID = specID, runtime = runtime })
      integrationEntry = type(automaticEntry) == "table" and automaticEntry or nil
    else
      local pawnProvider = runtime and runtime.PawnProvider and runtime.PawnProvider()
      if pawnProvider then
        local ok, resolved = pcall(function() return pawnProvider:Resolve(nil, { specID = specID }) end)
        if ok and resolved then scale = resolved end
      end
    end
    if not scale then
      -- Default is the final legitimate member of Automatic's hierarchy.
      -- Reaching it is normal and must not create a warning state.
      fallback = false
      fallbackReason = nil
      sel = { provider = "default", scale = nil, mode = "automatic", profile = sel.profile }
    end
  end

  if sel.mode == "integration" and not scale then
    local registry = integrationsRegistry()
    if registry then
      local resolved, reason, entry = registry:Resolve(sel.provider, {
        specID = specID,
        runtime = runtime,
      }, sel.scale)
      scale = resolved
      fallbackReason = reason
      integrationEntry = scale and entry or nil
    end
    if not scale then
      fallback = true
      fallbackReason = fallbackReason or "integration-unavailable"
      -- Keep the configured Integration in the profile. The effective
      -- selection becomes Default so an external key can never resolve
      -- accidentally through the manual-scale provider.
      sel = {
        provider = "default",
        scale = nil,
        mode = "integration",
        profile = sel.profile,
      }
    end
  end

  if not scale then scale = resolveSelection(specID, sel, runtime) end

  local sourceKind = "default"
  local sourceLabel = "Default"
  if not scale then
    scale = XIVWeights.Builtin and XIVWeights.Builtin.Defaults and XIVWeights.Builtin.Defaults.Get(specID)
    fallback = true
    fallbackReason = fallbackReason or "scale-unavailable"
  end
  if not scale then
    scale = XIVWeights.NewScale({ id = "fallback:empty", source = { kind = "empty" }, weights = {} })
    fallback = true
    fallbackReason = fallbackReason or "no-default-scale"
    sourceKind = "default"
    sourceLabel = "Default"
  end

  -- Resolve the source label after fallback selection so automatic default
  -- resolution is visible to callers instead of inheriting a nil label.
  if integrationEntry then
    sourceKind = "integration"
    sourceLabel = integrationEntry.label or integrationEntry.id
  elseif scale and scale.source and scale.source.kind == "pawn" then
    sourceKind = "integration"
    sourceLabel = "Pawn"
  elseif scale and scale.source and scale.source.kind == "manual" then
    sourceKind = "custom"
    sourceLabel = "Custom"
  elseif scale and scale.source and scale.source.kind == "xivequip-default-copy" then
    sourceKind = "custom"
    sourceLabel = "Custom"
  end

  local default = XIVWeights.Builtin and XIVWeights.Builtin.Defaults and XIVWeights.Builtin.Defaults.Get(specID)
  local effective = XIVWeights.Resolver.Resolve(scale, default)
  effective.resolution = {
    sourceKind = sourceKind,
    sourceLabel = sourceLabel,
    scaleLabel = scaleName(scale, Config.SpecName(specID) or "current spec"),
    automatic = sel.mode == "automatic",
    fallback = fallback,
    fallbackReason = fallbackReason,
    automaticResolution = sel.mode == "automatic" and sourceKind or nil,
    profileID = sel.profile and sel.profile.id or nil,
    configuredProvider = configuredSelection and configuredSelection.provider,
    configuredMode = configuredSelection and configuredSelection.mode,
    defaultCopy = scale and scale.source and scale.source.kind == "xivequip-default-copy",
  }
  return {
    scale = effective,
    profile = sel.profile,
    selection = sel,
    configuredSelection = configuredSelection,
    context = context,
    fallback = fallback,
    fallbackReason = fallbackReason,
  }
end

function Config.ResolveForSpec(specID, runtime)
  return Config.ResolveResultForSpec(specID, runtime).scale
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
