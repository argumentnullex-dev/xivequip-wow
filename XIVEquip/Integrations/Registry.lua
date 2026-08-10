-- Ordered registry for live scale integrations. Importers are separate.
local addonName, XIVEquip = ...
XIVEquip.Integrations = XIVEquip.Integrations or {}

local Registry = {
  entries = {},
}
XIVEquip.Integrations.Registry = Registry

local function contextRuntime(context)
  return context and context.runtime
end

function Registry:Register(entry)
  assert(type(entry) == "table" and entry.id, "Integration requires an id")
  assert(type(entry.Resolve) == "function", "Integration requires Resolve")
  self.entries[entry.id] = entry
end

function Registry:Get(id)
  return self.entries[id]
end

function Registry:List()
  local out = {}
  for _, entry in pairs(self.entries) do out[#out + 1] = entry end
  table.sort(out, function(a, b)
    local ap = tonumber(a.automaticPriority) or 0
    local bp = tonumber(b.automaticPriority) or 0
    if ap ~= bp then return ap > bp end
    return tostring(a.id) < tostring(b.id)
  end)
  return out
end

function Registry:IsAvailable(id, context)
  local entry = self:Get(id)
  if not entry then return false end
  if type(entry.IsAvailable) ~= "function" then return true end
  local ok, available = pcall(entry.IsAvailable, context)
  return ok and available == true
end

function Registry:Resolve(id, context, selection)
  local entry = self:Get(id)
  if not entry then return nil, "integration-unavailable" end
  if not self:IsAvailable(id, context) then return nil, "integration-unavailable" end
  local ok, scale, reason = pcall(entry.Resolve, context, selection)
  if ok and scale then return scale, nil, entry end
  return nil, reason or (ok and "integration-scale-missing" or scale), entry
end

function Registry:ResolveAutomatic(context)
  for _, entry in ipairs(self:List()) do
    if self:IsAvailable(entry.id, context) then
      local scale, reason, resolvedEntry = self:Resolve(entry.id, context)
      if scale then return scale, resolvedEntry end
      if reason then
        -- Continue through the support hierarchy when an installed provider
        -- has no suitable scale for this specialization.
      end
    end
  end
  return nil, "no-suitable-integration-scale"
end

local function pawnEntry(context)
  local runtime = contextRuntime(context)
  return runtime and runtime.PawnProvider and runtime.PawnProvider()
end

Registry:Register({
  id = "pawn",
  label = "Pawn",
  automaticPriority = 1000,
  IsAvailable = function(context)
    local runtime = contextRuntime(context)
    if runtime and runtime.IsAddOnLoaded and not runtime.IsAddOnLoaded("Pawn") then return false end
    return pawnEntry(context) ~= nil
  end,
  ListScales = function(context)
    local provider = pawnEntry(context)
    return provider and provider:ListScales({ specID = context and context.specID }) or {}
  end,
  Resolve = function(context, selection)
    local provider = pawnEntry(context)
    if not provider then return nil, "integration-unavailable" end
    local ok, scale = pcall(function()
      return provider:Resolve(selection, { specID = context and context.specID })
    end)
    if ok and scale then return scale end
    return nil, "integration-scale-missing"
  end,
})

return Registry
