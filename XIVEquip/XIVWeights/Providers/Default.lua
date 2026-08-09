-- XIVWeights/Providers/Default.lua
-- Provider for the user's generated per-spec default-copy scales.
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
  if classFile and self.config and self.config.EnsureClassSpecScales then
    return self.config.EnsureClassSpecScales(classFile)
  end
  return self.config and self.config.ListManualScales and self.config.ListManualScales() or {}
end

function Methods:Resolve(selection, context)
  local specID = context and context.specID
  if selection then
    local scale = XIVWeights.Config.Repository():Get(selection)
    if scale then return scale end
  end
  if specID then return self.config.EnsureSpecScale(specID) end
  error("Default provider: specID is required")
end
