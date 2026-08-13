-- Core/Command.lua
local addon, XIVEquip = ...
XIVEquip              = XIVEquip or {}
XIVEquip.Commands     = XIVEquip.Commands or {}

local C               = XIVEquip.Commands
local L               = XIVEquip.L or {}
local PREFIX          = L.AddonPrefix or "XIVEquip: "
-- Settings: Core addon plumbing: settings.
local function Settings() return XIVEquip.Settings end

-- utils
-- [XIVEquip-AUTO] trim: Helper for Core module.
local function trim(s) return (tostring(s or ""):match("^%s*(.-)%s*$")) end
-- split1: Core addon plumbing: split 1.
local function split1(s)
  local a, b = tostring(s or ""):match("^(%S+)%s*(.*)$")
  return a and string.lower(a) or "", (b or ""):match("^%s*(.-)%s*$")
end
-- onoff_to_bool: Core addon plumbing: onoff to bool.
local function onoff_to_bool(tok)
  tok = string.lower(tostring(tok or ""))
  if tok == "on" or tok == "1" or tok == "true" then return true end
  if tok == "off" or tok == "0" or tok == "false" then return false end
  return nil
end

local function printPlan(plan, pending)
  plan = plan or {}
  print(PREFIX .. string.format("Plan: %d item%s%s",
    #plan,
    (#plan == 1 and "" or "s"),
    pending and " (item data pending)" or ""))

  for i, pick in ipairs(plan) do
    local slotID = pick and pick.targetSlot
    local slotName = (XIVEquip.Gear_Core and XIVEquip.Gear_Core.SLOT_LABEL and XIVEquip.Gear_Core.SLOT_LABEL[slotID])
        or ("Slot " .. tostring(slotID or "?"))
    print(PREFIX .. string.format("%d. %s -> %s  ilvl=%s score=%s source=%s",
      i,
      tostring(slotName),
      tostring((pick and pick.link) or "(unknown item)"),
      tostring((pick and pick.ilvl) or "nil"),
      tostring((pick and pick.score) or "nil"),
      tostring((pick and pick.source) or "nil")))
  end
end

-- help registry
local helplines = {}
-- C.Help: Core addon plumbing: help.
function C.Help(line) helplines[#helplines + 1] = line end

C.Help(" /xive plan – print the current equip plan without equipping anything")
C.Help(" /xive equip – equip recommended gear")
C.Help(" /xive validate – save backup.xive, unequip gear, equip recommendations, confirm slots are filled with the top-recommended item")
C.Help(" /xive smoke – run /xive test, then /xive validate if tests pass")
C.Help(" /xive status – print selected settings and active scale")
C.Help(" /xive perf – run a planning pass and print timing/counter diagnostics")

-- print_help: Core addon plumbing: print help.
local function print_help()
  print(PREFIX .. "Commands:")
  print("  /xive                            – open settings")
  print("  /xive settings                   – open settings")
  print("  /xive help                       – print this command list")
  print("  /xivequip                        – equip recommended gear")
  print("  /xive equip                      – equip recommended gear")
  print("  /xive debug on|off|toggle        – toggle debug logging")
  print("  /xive debug slot <id|clear>      – filter debug to one slot (clear = all)")
  print("  /xive startup msg on|off         – toggle login/startup message")
  print("  /xive gear msg on|off            – toggle equip/change messages")
  print("  /xive gear preview on|off        – toggle hover preview on ERG button")
  print("  /xive auto spec on|off           – auto-equip on spec change")
  print("  /xive auto sets on|off           – auto-save set on equip")
  print("  /xive status                     – print settings and active scale")
  print("  /xive plan                       – print recommended equip plan")
  print("  /xive perf                       – print planner performance diagnostics")
  print("  /xive validate                   – backup, unequip, equip recommended gear, confirm it's the top recommendation")
  print("  /xive smoke                      – run test, then validation if tests pass")
  for _, line in ipairs(helplines) do print("  " .. line) end
end

local function openSettings()
  if XIVEquip.UI and XIVEquip.UI.SettingsWindow and XIVEquip.UI.SettingsWindow.Open then
    XIVEquip.UI.SettingsWindow.Open()
  else
    print(PREFIX .. "Settings window not available yet.")
  end
end

-- command framework (hardened)
-- [XIVEquip-AUTO] ROUTES table holds command -> handler mappings; leaf handlers are functions(rest).
local namespaces = {} -- first token -> function(rest)
local ROUTES     = {} -- nested tables -> function(rest)

-- C.RegisterNamespace: Core addon plumbing: register namespace.
function C.RegisterNamespace(ns, fn)
  namespaces[string.lower(tostring(ns or ""))] = fn
end

-- toPath: Core addon plumbing: to path.
local function toPath(cmd)
  if type(cmd) == "string" then return { cmd } end
  if type(cmd) == "table" then return cmd end
  error("RegisterRoot expects string or table path")
end

-- NEW: promote leaf functions to table nodes when needed
local function ensureTableSlot(t, key)
  local v = t[key]
  if type(v) == "function" then
    -- keep the existing handler as the default for this node
    v = { [""] = v }
    t[key] = v
  elseif type(v) ~= "table" then
    v = {}
    t[key] = v
  end
  return v
end

-- NEW: robust register that supports both leaf + subcommands
local function register(path, fn)
  local p = toPath(path)
  local node = ROUTES
  for i = 1, (#p - 1) do
    local key = string.lower(tostring(p[i] or ""))
    if key ~= "" then
      node = ensureTableSlot(node, key)
    end
  end
  local leaf = string.lower(tostring(p[#p] or ""))
  if leaf == "" then return end
  local existing = node[leaf]
  if type(existing) == "table" then
    -- already has subcommands; store this as the default handler
    existing[""] = fn
  else
    node[leaf] = fn
  end
end

-- C.RegisterRoot: Core addon plumbing: register root.
function C.RegisterRoot(cmdOrPath, fn) register(cmdOrPath, fn) end

-- NEW: dispatcher that honors default handlers on table nodes ([""])
local function dispatch(msg)
  local tokens = {}
  for w in string.gmatch(tostring(msg or ""), "%S+") do tokens[#tokens + 1] = w end
  if #tokens == 0 then
    openSettings(); return
  end

  -- 1) namespace
  local head = string.lower(tokens[1])
  if namespaces[head] then
    local rest = table.concat(tokens, " ", 2)
    return namespaces[head](rest)
  end

  -- 2) deepest route with default-handlers ("")
  local node, fn, ix = ROUTES, nil, 0
  local candidateFn, candidateIx = nil, 0
  for i = 1, #tokens do
    local k = string.lower(tokens[i])
    local nxt = node[k]
    if type(nxt) == "function" then
      fn, ix = nxt, i; break
    elseif type(nxt) == "table" then
      node = nxt
      if type(node[""]) == "function" then
        candidateFn, candidateIx = node[""], i
      end
    else
      break
    end
  end
  if not fn and candidateFn then
    fn, ix = candidateFn, candidateIx
  end
  if not fn then
    -- also allow a single-token default at top level
    local one = ROUTES[head]
    if type(one) == "function" then fn, ix = one, 1 end
  end
  if not fn then
    print(PREFIX .. "Unknown command. Try /xive help"); return
  end

  local rest = table.concat(tokens, " ", ix + 1)
  return fn(rest)
end

-- slash bindings
SLASH_XIVE1 = "/xive"
-- SlashCmdList["XIVE"]: Core addon plumbing: slash cmd list xive.
SlashCmdList["XIVE"] = function(msg) dispatch(trim(msg)) end

-- handlers

C.RegisterRoot("help", function(_)
  print_help()
end)

C.RegisterRoot("settings", function(_)
  openSettings()
end)

-- /xive status
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("status", function(_)
  local S = Settings()
  local st = (S and S.Get and S:Get()) or _G.XIVEquip_Settings or {}
  print(PREFIX .. "Status")
  print(PREFIX .. "Settings schema: " .. tostring(st.SchemaVersion or "unknown"))
  print(PREFIX .. "Auto spec: " .. (((S and S.GetAutomation and S:GetAutomation("SpecEquip")) or false) and "ON" or "OFF"))
  print(PREFIX .. "Auto sets: " .. (((S and S.GetAutomation and S:GetAutomation("SaveSpecSet")) or false) and "ON" or "OFF"))
end)

-- /xive plan
-- Prints the current equip plan without attempting to equip anything.
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("plan", function(rest)
  if trim(rest) ~= "" then
    print(PREFIX .. "Usage: /xive plan")
    return
  end

  local Gear = XIVEquip.Gear
  if not (Gear and Gear.PlanBest) then
    print(PREFIX .. "Planner not available.")
    return
  end

  local _, pending, plan, result, planFailure = Gear:PlanBest()
  if planFailure then
    print(PREFIX .. "Planner failed; no plan available. Check the debug log for details.")
    return
  end

  printPlan(plan, pending)
end)

-- /xive perf
-- Performs a planning pass and prints compact timing/work counters.
C.RegisterRoot("perf", function(rest)
  if trim(rest) ~= "" then
    print(PREFIX .. "Usage: /xive perf")
    return
  end

  local Perf = XIVEquip.Diagnostics and XIVEquip.Diagnostics.Perf
  local Gear = XIVEquip.Gear
  if not (Perf and Perf.New and Gear and Gear.PlanBest) then
    print(PREFIX .. "Performance diagnostics not available.")
    return
  end

  local recorder = Perf.New(true)
  local _, pending, plan, result, planFailure = Gear:PlanBest({ planner = { perf = recorder } })
  if planFailure then
    print(PREFIX .. "Planner failed; no performance report available. Check the debug log for details.")
    return
  end

  print(PREFIX .. string.format("Perf: plan produced %d item%s%s.",
    #(plan or {}),
    #(plan or {}) == 1 and "" or "s",
    pending and " (item data pending)" or ""))
  if result and result.diagnostics and result.diagnostics.scoreSource then
    print(PREFIX .. "Score source: " .. tostring(result.diagnostics.scoreSource))
  end
  for _, line in ipairs(recorder:Lines()) do
    print(PREFIX .. line)
  end
end)

-- /xive equip
C.RegisterRoot("equip", function(rest)
  if trim(rest) ~= "" then
    print(PREFIX .. "Usage: /xive equip")
    return
  end

  if XIVEquip and XIVEquip.Gear and XIVEquip.Gear.EquipBest then
    XIVEquip.Gear:EquipBest()
  else
    print(PREFIX .. "Equip routine not available.")
  end
end)

-- /xive validate
-- Saves backup.xive, unequips supported gear slots, runs recommended equip, and reports missing slots.
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("validate", function(_)
  if XIVEquip and XIVEquip.Gear and XIVEquip.Gear.ValidateNakedEquip then
    XIVEquip.Gear:ValidateNakedEquip()
  else
    print(PREFIX .. "Validation routine not available.")
  end
end)

-- /xive smoke
-- Runs in-game regression checks, then starts validation if they pass.
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("smoke", function(_)
  if not (XIVEquip and XIVEquip.Tests and XIVEquip.Tests.Run) then
    print(PREFIX .. "Regression test routine not available.")
    return
  end
  if not (XIVEquip.Gear and XIVEquip.Gear.ValidateNakedEquip) then
    print(PREFIX .. "Validation routine not available.")
    return
  end

  local ok = XIVEquip.Tests:Run()
  if ok == false then
    print(PREFIX .. "Smoke aborted: regression tests failed.")
    return
  end

  XIVEquip.Gear:ValidateNakedEquip()
end)

-- /xive debug on|off|toggle
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("debug", function(rest)
  local S = Settings()
  if not (S and S.SetDebugEnabled and S.GetDebugEnabled) then
    print(PREFIX .. "Settings not available."); return
  end
  local sub = string.lower((rest or ""):match("^(%S*)") or "")
  if sub == "on" then
    S:SetDebugEnabled(true)
  elseif sub == "off" then
    S:SetDebugEnabled(false)
  else
    S:SetDebugEnabled(not S:GetDebugEnabled())
  end
  print(PREFIX .. "Debug: " .. (S:GetDebugEnabled() and "ON" or "OFF"))
end)

-- /xive debug slot <number|clear>
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot({ "debug", "slot" }, function(rest)
  local S = Settings(); if not (S and S.SetDebugSlot) then
    print(PREFIX .. "Settings not available."); return
  end
  local r = trim(rest)
  if r == "" or r == "clear" or r == "off" then
    S:SetDebugSlot(nil); print(PREFIX .. "Debug slot filter cleared."); return
  end
  local n = tonumber(r); if n then
    S:SetDebugSlot(n); print(PREFIX .. ("Debug slot set to %d."):format(n))
  else
    print(PREFIX .. "Usage: /xive debug slot <number|clear>")
  end
end)

-- /xive startup msg on|off
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("startup", function(rest)
  local S = Settings(); if not (S and S.SetMessage) then
    print(PREFIX .. "Settings not available."); return
  end
  local tok, rest2 = split1(rest); if tok ~= "msg" then
    print(PREFIX .. "Usage: /xive startup msg on|off"); return
  end
  local onoff = onoff_to_bool(select(1, split1(rest2))); if onoff == nil then
    print(PREFIX .. "Usage: /xive startup msg on|off"); return
  end
  S:SetMessage("Login", onoff); print(PREFIX .. "Startup message: " .. (onoff and "ON" or "OFF"))
end)

-- /xive gear msg on|off   and   /xive gear preview on|off
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("gear", function(rest)
  local S = Settings(); if not (S and S.SetMessage) then
    print(PREFIX .. "Settings not available."); return
  end
  local sub, rest2 = split1(rest); local onoff = onoff_to_bool(select(1, split1(rest2)))
  if sub == "msg" then
    if onoff == nil then
      print(PREFIX .. "Usage: /xive gear msg on|off"); return
    end
    S:SetMessage("Equip", onoff); print(PREFIX .. "Equip/change messages: " .. (onoff and "ON" or "OFF"))
  elseif sub == "preview" then
    if onoff == nil then
      print(PREFIX .. "Usage: /xive gear preview on|off"); return
    end
    S:SetMessage("Preview", onoff); print(PREFIX .. "Hover preview: " .. (onoff and "ON" or "OFF"))
  else
    print(PREFIX .. "Usage: /xive gear msg on|off  |  /xive gear preview on|off")
  end
end)

-- /xive auto spec|sets on|off
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("auto", function(rest)
  local S = Settings(); if not (S and S.SetAutomation) then
    print(PREFIX .. "Settings not available."); return
  end
  local what, rest2 = split1(rest); local onoff = onoff_to_bool(select(1, split1(rest2)))
  if (what ~= "spec" and what ~= "sets") or onoff == nil then
    print(PREFIX .. "Usage: /xive auto spec on|off  |  /xive auto sets on|off"); return
  end
  S:SetAutomation(what == "spec" and "SpecEquip" or "SaveSpecSet", onoff)
  print(PREFIX .. "Auto " .. what .. ": " .. (onoff and "ON" or "OFF"))
end)

-- /xivequip
SLASH_XIVEQUIP1 = "/xivequip"
-- SlashCmdList["XIVEQUIP"]: Core addon plumbing: slash cmd list xivequip.
SlashCmdList["XIVEQUIP"] = function()
  if XIVEquip and XIVEquip.Gear and XIVEquip.Gear.EquipBest then
    XIVEquip.Gear:EquipBest()
  else
    print(PREFIX .. "Equip routine not available.")
  end
end
