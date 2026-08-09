-- XIVWeights/Repository.lua
-- Storage for native/manual XIVWeights scales (doc section 32). Takes an
-- injected backing-store table rather than reading XIVEquip_Settings
-- directly -- real SavedVariables wiring is Settings UI work, explicitly
-- deferred until after 2.0 feature parity (doc section 30 leaves the exact
-- settings UI/schema out of scope for this architecture pass).
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
local XIVWeights = XIVEquip.XIVWeights

local Repository = {}
XIVWeights.Repository = Repository

local Methods = {}
local RepositoryMT = { __index = Methods }

-- New(store) -> Repository. `store` defaults to a plain in-memory table;
-- pass a SavedVariables-backed table to persist scales instead.
function Repository.New(store)
  return setmetatable({ store = store or {} }, RepositoryMT)
end

function Methods:Save(scale)
  assert(scale and scale.id, "XIVWeights scale requires an id")
  self.store[scale.id] = scale
  return scale
end

function Methods:Get(id)
  return self.store[id]
end

function Methods:List()
  local out = {}
  for _, scale in pairs(self.store) do
    out[#out + 1] = scale
  end
  return out
end

function Methods:Delete(id)
  local existed = self.store[id] ~= nil
  self.store[id] = nil
  return existed
end
