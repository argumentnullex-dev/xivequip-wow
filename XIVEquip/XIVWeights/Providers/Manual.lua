-- XIVWeights/Providers/Manual.lua
-- The native/manual XIVWeights Provider (doc section 11, section 32):
-- resolves scales the user has stored directly in a Repository. No external
-- source, no conversion step -- the Repository already holds normalized
-- XIVWeights.Scale records.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
XIVEquip.XIVWeights.Providers = XIVEquip.XIVWeights.Providers or {}
local XIVWeights = XIVEquip.XIVWeights

local Manual = {}
XIVWeights.Providers.Manual = Manual

local Methods = {}
local ManualMT = { __index = Methods }

-- New(repository) -> Manual provider, per the Provider contract:
--   provider:ListScales(context)
--   provider:Resolve(selection, context)
function Manual.New(repository)
  assert(repository, "Manual provider requires a Repository")
  return setmetatable({ repository = repository }, ManualMT)
end

function Methods:ListScales(context)
  return self.repository:List()
end

-- Resolve(selection, context) -> Scale. `selection` is the stored scale id.
function Methods:Resolve(selection, context)
  local scale = self.repository:Get(selection)
  assert(scale, "Manual provider: unknown scale id '" .. tostring(selection) .. "'")
  return scale
end
