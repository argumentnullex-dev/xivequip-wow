-- XIVWeights/Providers/Default.lua
-- Provider for source-controlled built-in XIVEquip default scales.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
XIVEquip.XIVWeights.Providers = XIVEquip.XIVWeights.Providers or {}
local XIVWeights = XIVEquip.XIVWeights

local Default = {}
XIVWeights.Providers.Default = Default

local Methods = {}
local MT = { __index = Methods }

function Default.New(config)
  return setmetatable({ config = config or XIVWeights.Config }, MT)
end

function Methods:ListScales(context)
  local classFile = context and context.classFile
  local defaults = XIVWeights.Builtin and XIVWeights.Builtin.Defaults
  if classFile and defaults then
    local out = {}
    for _, spec in ipairs(defaults.SpecsForClass(classFile) or {}) do
      local scale = defaults.Get(spec.id)
      if scale then out[#out + 1] = scale end
    end
    return out
  end
  return defaults and defaults.List() or {}
end

function Methods:Resolve(selection, context)
  local specID = context and context.specID
  if specID and XIVWeights.Builtin and XIVWeights.Builtin.Defaults then
    local scale = XIVWeights.Builtin.Defaults.Get(specID)
    if scale then return scale end
  end
  error("Default provider: specID is required")
end
