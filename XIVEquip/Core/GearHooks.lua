-- Hooks.lua
local addon, XIVEquip = ...
local Hooks = {}
XIVEquip.Hooks = Hooks

-- registry keys can be: "ALL", category string (e.g. "TRINKET"), or slotID (number)
local reg = { ALL = {} }

-- addKey: Core addon plumbing: add key.
local function addKey(key)
  if not reg[key] then reg[key] = {} end
  return reg[key]
end

-- fn(ctx) -> overrideCandidate|nil
-- ctx = { slotID, category, equipped = {loc, score, ilvl, link}, candidates = { ... }, chosen, comparer }
-- [XIVEquip-AUTO] Hooks:Register: Helper for Core module.
function Hooks:Register(key, fn)
  table.insert(addKey(key), fn)
end

-- Hooks:Unregister: Core addon plumbing: unregister.
function Hooks:Unregister(key, fn)
  local t = reg[key]; if not t then return end
  for i = #t, 1, -1 do if t[i] == fn then table.remove(t, i) end end
end

-- fireList: Core addon plumbing: fire list.
local function fireList(list, ctx)
  if not list then return nil end
  for _, fn in ipairs(list) do
    local ok, override = pcall(fn, ctx)
    if ok and override then return override end
  end
end

-- Hooks:Run: Core addon plumbing: run.
function Hooks:Run(slotID, category, ctx)
  -- Priority: slotID > category > ALL
  return fireList(reg[slotID], ctx)
      or fireList(reg[category], ctx)
      or fireList(reg.ALL, ctx)
end
