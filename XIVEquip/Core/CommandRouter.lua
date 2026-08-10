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

local function setComparerSetting(key)
  local S = Settings()
  if S and S.SetComparerName then return S:SetComparerName(key) end
  if S and S.SetComparerLabel then return S:SetComparerLabel(key) end
  _G.XIVEquip_Settings = _G.XIVEquip_Settings or {}
  _G.XIVEquip_Settings.Comparer = _G.XIVEquip_Settings.Comparer or {}
  _G.XIVEquip_Settings.Comparer.Selected = key
end

local function scoreWithComparer(cmp, subject, slotID)
  if not cmp then return nil, "no-comparer" end
  if cmp.DebugScore then
    local ok, v, src, entry = pcall(cmp.DebugScore, subject, slotID)
    if ok and type(v) == "number" then return v, src, entry end
  end
  if cmp.ScoreItem then
    local ok, v = pcall(cmp.ScoreItem, subject, slotID)
    if ok and type(v) == "number" then return v, cmp.Label end
  end
  return nil, "no-score"
end

local function comparerHeader(cmp, resolution)
  if cmp and type(cmp.GetActiveTooltipHeader) == "function" then
    local ok, header = pcall(cmp.GetActiveTooltipHeader)
    if ok and header and header ~= "" then return header end
  end
  local key = resolution and resolution.resolved_key
  local label = cmp and cmp.Label or key or "unknown"
  return "Comparer: " .. tostring(label)
end

local function acquireComparerPass(M)
  if not (M and type(M.StartPass) == "function") then return nil end
  if type(M.AcquirePass) == "function" then return M:AcquirePass() end

  local cmp, resolution = M:StartPass()
  local closed = false
  return {
    comparer = cmp,
    resolution = resolution,
    Close = function()
      if closed then return end
      closed = true
      if M and type(M.EndPass) == "function" then M:EndPass() end
    end,
    EndPass = function(selfLease)
      return selfLease:Close()
    end,
  }
end

local function releaseComparerPass(lease)
  if not lease then return end
  if type(lease.Close) == "function" then
    lease:Close()
  elseif type(lease.EndPass) == "function" then
    lease:EndPass()
  end
end

local function errorDetail(err)
  local text = tostring(err or "unknown error")
  if debugstack then return text .. "\n" .. tostring(debugstack(2) or "") end
  if debug and type(debug.traceback) == "function" then return debug.traceback(text, 2) end
  return text
end

local function parsePlannerOverride(rest, usage)
  local want = string.lower(trim(rest))
  if want == "" then return nil end
  if want == "legacy" then return "legacy" end
  if want == "native" then return "native" end
  return nil, usage
end

local function configuredPlannerMode()
  local S = Settings()
  if S and type(S.GetPlannerMode) == "function" then return S:GetPlannerMode() end
  return "legacy"
end

local function effectivePlannerMode(override)
  if override == "legacy" or override == "native" then return override end
  return configuredPlannerMode()
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

C.Help(" /xive score <link> [scale] – score with resolved comparer; if [scale] is given, try Pawn scale")
C.Help(" /xive diag – print equipped gear and per-slot scores using the active comparer")
C.Help(" /xive plan [legacy|native] – print the current equip plan without equipping anything")
C.Help(" /xive equip [legacy|native] – equip recommended gear")
C.Help(" /xive compare – compare legacy and native planner output and save an analysis log")
C.Help(" /xive planner <legacy|native|status> – choose the planner used by normal equip")
C.Help(" /xive validate – save backup.xive, unequip gear, equip recommendations, confirm slots are filled with the top-recommended item")
C.Help(" /xive smoke – run /xive test, then /xive validate if tests pass")
C.Help(" /xive status – print selected settings and resolved runtime comparer")

-- print_help: Core addon plumbing: print help.
local function print_help()
  print(PREFIX .. "Commands:")
  print("  /xive                            – open settings")
  print("  /xive settings                   – open settings")
  print("  /xivequip                        – equip recommended gear")
  print("  /xive equip [legacy|native]      – equip recommended gear")
  print("  /xive use <comparer>             – set comparer by key or label (default, Pawn, ilvl)")
  print("  /xive debug on|off|toggle        – toggle debug logging")
  print("  /xive debug slot <id|clear>      – filter debug to one slot (clear = all)")
  print("  /xive startup msg on|off         – toggle login/startup message")
  print("  /xive gear msg on|off            – toggle equip/change messages")
  print("  /xive gear preview on|off        – toggle hover preview on ERG button")
  print("  /xive auto spec on|off           – auto-equip on spec change")
  print("  /xive auto sets on|off           – auto-save set on equip")
  print("  /xive planner legacy|native      – choose planner for normal equip")
  print("  /xive planner status             – show planner mode")
  print("  /xive status                     – print settings and comparer status")
  print("  /xive diag                       – print equipped gear and scores")
  print("  /xive plan [legacy|native]       – print recommended equip plan")
  print("  /xive compare                    – compare legacy/native plans and save a log")
  print("  /xive validate                   – backup, unequip, equip recommended gear, confirm it's the top recommendation")
  print("  /xive smoke                      – run test, then validation if tests pass")
  print("  /xive score <link> [scale]       – score; [scale] uses Pawn if available")
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
    print(PREFIX .. "Unknown command. Try /xive"); return
  end

  local rest = table.concat(tokens, " ", ix + 1)
  return fn(rest)
end

-- slash bindings
SLASH_XIVE1 = "/xive"
-- SlashCmdList["XIVE"]: Core addon plumbing: slash cmd list xive.
SlashCmdList["XIVE"] = function(msg) dispatch(trim(msg)) end

-- handlers

-- /xive use <comparer>
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("use", function(rest)
  local want = trim(rest)
  if want == "" then
    print(PREFIX .. "Usage: /xive use <default|pawn|ilvl|Item Level>"); return
  end
  local M = XIVEquip.Comparers
  if not (M and M.All and M.CanonicalKey) then
    print(PREFIX .. "Comparers core not loaded."); return
  end
  local key = M:CanonicalKey(want)
  if not key then
    print(PREFIX .. "No comparer matching '" .. want .. "'."); return
  end
  setComparerSetting(key)
  local lease = acquireComparerPass(M)
  local resolution = lease and lease.resolution
  local cmp = lease and lease.comparer
  local active = cmp and (cmp.Label or resolution.resolved_key) or M:GetDisplayLabel(key)
  releaseComparerPass(lease)
  if resolution and resolution.fallback_used then
    print(PREFIX .. "Comparer set to: " .. M:GetDisplayLabel(key) .. " (using " .. tostring(active) .. ")")
  elseif resolution and not resolution.comparer then
    print(PREFIX .. "Comparer set to: " .. M:GetDisplayLabel(key) .. " but it is unavailable.")
  else
    print(PREFIX .. "Comparer set to: " .. tostring(active))
  end
end)

C.RegisterRoot("settings", function(_)
  openSettings()
end)

-- /xive planner <legacy|native|status>
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("planner", function(rest)
  local want = string.lower(trim(rest))
  local S = Settings()
  if not (S and S.GetPlannerMode and S.SetPlannerMode) then
    print(PREFIX .. "Settings not available.")
    return
  end

  if want == "" or want == "status" then
    print(PREFIX .. "Planner mode: " .. tostring(S:GetPlannerMode()))
    return
  end

  if want == "legacy" or want == "1" or want == "1.0" then
    S:SetPlannerMode("legacy")
    print(PREFIX .. "Planner mode set to: legacy")
    return
  end

  if want == "native" or want == "2" or want == "2.0" or want == "v2" then
    S:SetPlannerMode("native")
    print(PREFIX .. "Planner mode set to: native")
    return
  end

  print(PREFIX .. "Usage: /xive planner <legacy|native|status>")
end)

-- /xive status
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("status", function(_)
  local S = Settings()
  local st = (S and S.Get and S:Get()) or _G.XIVEquip_Settings or {}
  local M = XIVEquip.Comparers
  local cmp, resolution
  local lease = acquireComparerPass(M)
  if lease then
    cmp, resolution = lease.comparer, lease.resolution
  end

  local configured = (resolution and resolution.configured_key)
      or (S and S.GetComparerName and S:GetComparerName())
      or "default"
  local resolved = (resolution and resolution.resolved_key) or "none"
  local label = (cmp and cmp.Label) or resolved
  local fallback = resolution and resolution.fallback_used and "yes" or "no"

  print(PREFIX .. "Status")
  print(PREFIX .. "Settings schema: " .. tostring(st.SchemaVersion or "legacy"))
  print(PREFIX .. "Configured comparer: " .. tostring(configured))
  print(PREFIX .. "Resolved comparer: " .. tostring(label))
  print(PREFIX .. "Comparer fallback: " .. fallback)
  print(PREFIX .. "Planner mode: " .. tostring((S and S.GetPlannerMode and S:GetPlannerMode()) or "legacy"))
  print(PREFIX .. "Auto spec: " .. (((S and S.GetAutomation and S:GetAutomation("SpecEquip")) or false) and "ON" or "OFF"))
  print(PREFIX .. "Auto sets: " .. (((S and S.GetAutomation and S:GetAutomation("SaveSpecSet")) or false) and "ON" or "OFF"))

  releaseComparerPass(lease)
end)

-- /xive plan [legacy|native]
-- Prints the current equip plan without attempting to equip anything.
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("plan", function(rest)
  local override, usage = parsePlannerOverride(rest, "Usage: /xive plan [legacy|native]")
  if usage then
    print(PREFIX .. usage)
    return
  end

  local Gear = XIVEquip.Gear
  if not (Gear and Gear.PlanBest) then
    print(PREFIX .. "Planner not available.")
    return
  end

  local mode = effectivePlannerMode(override)
  if mode == "native" then
    local _, pending, plan, result, nativeFailure = Gear:PlanBest(nil, { planner = "native" })
    if nativeFailure then
      print(PREFIX .. "Native 2.0 planner failed; no plan available. Check the debug log for details.")
      return
    end

    local diag = result and result.diagnostics or {}
    print(PREFIX .. "Planner: native 2.0")
    print(PREFIX .. "Score source: " .. tostring(diag.scoreSource or "unknown"))
    printPlan(plan, pending)
    return
  end

  local M = XIVEquip.Comparers
  if not (M and M.StartPass) then
    print(PREFIX .. "Comparer core not loaded.")
    return
  end

  local lease
  local cmp, resolution
  local ok, errOrChanges, pending, plan = xpcall(function()
    lease = acquireComparerPass(M)
    cmp, resolution = lease and lease.comparer, lease and lease.resolution
    return Gear:PlanBest(cmp, { planner = "legacy" })
  end, errorDetail)
  releaseComparerPass(lease)
  if not ok then
    print(PREFIX .. "Legacy planner failed; no plan available. Check the debug log for details.")
    if XIVEquip.Log and type(XIVEquip.Log.Error) == "function" then
      XIVEquip.Log.Error("Legacy planner failure: " .. tostring(errOrChanges))
    end
    return
  end

  print(PREFIX .. "Planner: legacy")
  print(PREFIX .. comparerHeader(cmp, resolution))
  printPlan(plan, pending)
end)

local function identityFromLink(link)
  if type(link) ~= "string" then return nil end
  return link:match("|Hitem:([^|]+)") or link:match("item:([^|]+)") or link
end

local function is2H(equipLoc)
  return equipLoc == "INVTYPE_2HWEAPON"
      or equipLoc == "INVTYPE_RANGED"
      or equipLoc == "INVTYPE_RANGEDRIGHT"
      or equipLoc == "INVTYPE_THROWN"
end

local function playerAllowsTitanGrip()
  local classFile = select(2, UnitClass and UnitClass("player"))
  local specIndex = GetSpecialization and GetSpecialization()
  local specID = specIndex and GetSpecializationInfo and select(1, GetSpecializationInfo(specIndex))
  local profile = XIVEquip.Policies and XIVEquip.Policies.ClassSpecWeaponProfile
      and XIVEquip.Policies.ClassSpecWeaponProfile(classFile, specID)
  return profile and profile.allowTitanGrip == true
end

local function currentFinalIDs(slots)
  local final = {}
  for _, slotID in ipairs(slots or {}) do
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID) or nil
    final[slotID] = identityFromLink(link)
  end
  return final
end

local function applyLegacyPlan(final, plan)
  local plannedOffhand = false
  for _, pick in ipairs(plan or {}) do
    if pick and pick.targetSlot then
      final[pick.targetSlot] = identityFromLink(pick.link) or tostring(pick.itemID or "")
      if pick.targetSlot == 17 then plannedOffhand = true end
    end
  end
  for _, pick in ipairs(plan or {}) do
    if pick and pick.targetSlot == 16 and is2H(pick.equipLoc) and not plannedOffhand and not playerAllowsTitanGrip() then
      final[17] = nil
    end
  end
end

local function candidateID(candidate)
  return candidate and (identityFromLink(candidate.link) or candidate.physicalID or candidate.guid or tostring(candidate.itemID))
end

local function addonVersion()
  local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  if type(metadata) ~= "function" then return "unknown" end
  local ok, version = pcall(metadata, addon, "Version")
  if ok and version and version ~= "" then return tostring(version) end
  return "unknown"
end

local function pickSummary(pick)
  if not pick then return nil end
  local from = pick.from
  if from ~= nil and type(from) ~= "string" and type(from) ~= "number" and type(from) ~= "boolean" then
    from = tostring(from)
  end
  return {
    targetSlot = pick.targetSlot,
    itemID = pick.itemID,
    link = pick.link,
    identity = identityFromLink(pick.link) or pick.physicalID or pick.guid or (pick.itemID and tostring(pick.itemID)) or nil,
    equipLoc = pick.equipLoc,
    ilvl = pick.ilvl or pick.itemLevel,
    score = pick.score,
    source = pick.source,
    guid = pick.guid,
    physicalID = pick.physicalID,
    from = from,
    bag = pick.bag,
    slot = pick.slot,
  }
end

local function planSummary(plan)
  local out = {}
  for _, pick in ipairs(plan or {}) do out[#out + 1] = pickSummary(pick) end
  return out
end

local function candidateSummary(candidate)
  if not candidate then return nil end
  return {
    itemID = candidate.itemID,
    link = candidate.link,
    identity = candidateID(candidate),
    itemLevel = candidate.itemLevel,
    equipLoc = candidate.equip and candidate.equip.equipLoc or candidate.equipLoc,
    score = candidate.score,
    guid = candidate.guid,
    physicalID = candidate.physicalID,
    source = candidate.source,
  }
end

local function finalSlotSummary(finalSlots, slots)
  local out = {}
  for _, slotID in ipairs(slots or {}) do out[slotID] = candidateSummary(finalSlots and finalSlots[slotID]) end
  return out
end

local function resolutionSummary(resolution)
  if not resolution then return nil end
  return {
    configured_key = resolution.configured_key,
    requested_key = resolution.requested_key,
    resolved_key = resolution.resolved_key,
    fallback_used = resolution.fallback_used == true,
    reason = resolution.reason,
    comparerLabel = resolution.comparer and resolution.comparer.Label or nil,
  }
end

local function captureFixtureForLog()
  local Tests = XIVEquip.Tests
  if Tests and type(Tests.CaptureFixture) == "function" then
    local ok, fixture = xpcall(function() return Tests:CaptureFixture() end, errorDetail)
    if ok then return fixture end
    return nil, fixture
  end
  return nil, "fixture capture helper not available"
end

-- /xive compare
-- Diagnostic-only planner comparison. It does not equip, save an equipment
-- set, or treat either planner as correct. It stores the captured fixture and
-- both planner outputs in SavedVariables for later LLM-assisted analysis.
C.RegisterRoot("compare", function(_)
  local Planner = XIVEquip.Planning and XIVEquip.Planning.Coordinator
  local slots = Planner and Planner.OPTIMIZED_SLOTS
  if not (Planner and Planner.Plan and slots) then
    print(PREFIX .. "Native planner not available.")
    return
  end

  local M = XIVEquip.Comparers
  local Gear = XIVEquip.Gear
  if not (Gear and Gear.PlanBest) then
    print(PREFIX .. "Gear planner not available.")
    return
  end

  local fixture, fixtureError = captureFixtureForLog()

  local native = { ok = false, pending = false, plan = {}, error = nil, result = nil }
  local nativeOk, nativeChangesOrErr, nativePending, nativePlan, nativeResult, nativeFailure = xpcall(function()
    return Gear:PlanBest(nil, { planner = "native" })
  end, errorDetail)
  if nativeOk and not nativeFailure then
    native.ok = true
    native.pending = nativePending == true
    native.plan = nativePlan or {}
    native.result = nativeResult
  else
    native.error = tostring(nativeFailure or nativeChangesOrErr or "native planner failed")
  end

  local legacy = { ok = false, pending = false, plan = {}, error = nil, resolution = nil, comparerHeader = nil }
  if M and M.StartPass then
    local lease
    local legacyOk, legacyChangesOrErr, legacyPending, legacyPlan = xpcall(function()
      lease = acquireComparerPass(M)
      local cmp = lease and lease.comparer
      legacy.resolution = lease and lease.resolution
      legacy.comparerHeader = comparerHeader(cmp, legacy.resolution)
      return Gear:PlanBest(cmp, { planner = "legacy" })
    end, errorDetail)
    releaseComparerPass(lease)

    if legacyOk then
      legacy.ok = true
      legacy.pending = legacyPending == true
      legacy.plan = legacyPlan or {}
    else
      legacy.error = tostring(legacyChangesOrErr or "legacy planner failed")
    end
  else
    legacy.error = "comparer core not loaded"
  end

  local legacyFinal = currentFinalIDs(slots)
  applyLegacyPlan(legacyFinal, legacy.plan)

  local changed, mismatches = {}, {}
  if native.ok then
    for _, slotID in ipairs(slots) do
      local newID = candidateID(native.result and native.result.finalSlots and native.result.finalSlots[slotID])
      local oldID = legacyFinal[slotID]
      local currentID = identityFromLink(GetInventoryItemLink and GetInventoryItemLink("player", slotID) or nil)
      if newID ~= currentID then changed[#changed + 1] = slotID end
      if newID ~= oldID then mismatches[#mismatches + 1] = slotID end
    end
  end

  local S = Settings()
  local st = _G.XIVEquip_Settings or {}
  st.Diagnostics = st.Diagnostics or {}
  st.Diagnostics.PlannerCompare = {
    capturedAt = time and time() or nil,
    addonVersion = addonVersion(),
    configuredPlannerMode = configuredPlannerMode(),
    configuredComparer = S and S.GetComparerName and S:GetComparerName() or nil,
    fixture = fixture,
    fixtureError = fixtureError,
    legacy = {
      ok = legacy.ok,
      pending = legacy.pending,
      error = legacy.error,
      comparerHeader = legacy.comparerHeader,
      resolution = resolutionSummary(legacy.resolution),
      plan = planSummary(legacy.plan),
      finalIdentitiesBySlot = legacyFinal,
    },
    native = {
      ok = native.ok,
      pending = native.pending,
      error = native.error,
      plan = planSummary(native.plan),
      score = native.result and native.result.score or nil,
      diagnostics = native.result and native.result.diagnostics or nil,
      finalSlots = finalSlotSummary(native.result and native.result.finalSlots, slots),
    },
    comparison = {
      changedSlots = changed,
      mismatchSlots = mismatches,
    },
  }
  _G.XIVEquip_Settings = st

  local diag = native.result and native.result.diagnostics or {}
  print(PREFIX .. string.format("Compare: legacy=%s native=%s mismatches=%d changed=%d source=%s%s",
    legacy.ok and "ok" or "failed",
    native.ok and "ok" or "failed",
    #mismatches,
    #changed,
    tostring(diag.scoreSource or "unknown"),
    (legacy.pending or native.pending) and " (item data pending)" or ""))

  if #mismatches > 0 then
    print(PREFIX .. "Native differs from legacy in " .. tostring(#mismatches) .. " slot(s):")
    for _, slotID in ipairs(mismatches) do
      print(PREFIX .. string.format("  %s: native=%s legacy=%s",
        tostring((XIVEquip.Gear_Core and XIVEquip.Gear_Core.SLOT_LABEL and XIVEquip.Gear_Core.SLOT_LABEL[slotID]) or slotID),
        tostring(candidateID(native.result and native.result.finalSlots and native.result.finalSlots[slotID]) or "empty"),
        tostring(legacyFinal[slotID] or "empty")))
    end
  end

  if native.error then print(PREFIX .. "Native error: " .. tostring(native.error)) end
  if legacy.error then print(PREFIX .. "Legacy error: " .. tostring(legacy.error)) end
  if fixtureError then print(PREFIX .. "Fixture capture warning: " .. tostring(fixtureError)) end

  print(PREFIX .. "Saved comparison log to XIVEquip_Settings.Diagnostics.PlannerCompare.")
  print(PREFIX .. "After /reload or logout, copy WTF/Account/<ACCOUNT>/SavedVariables/XIVEquip.lua.")
end)

-- /xive equip [legacy|native]
C.RegisterRoot("equip", function(rest)
  local override, usage = parsePlannerOverride(rest, "Usage: /xive equip [legacy|native]")
  if usage then
    print(PREFIX .. usage)
    return
  end

  if XIVEquip and XIVEquip.Gear and XIVEquip.Gear.EquipBest then
    local opts = {}
    if override then opts.planner = override end
    XIVEquip.Gear:EquipBest(opts)
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

-- /xive score <link> [scale]
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("score", function(rest)
  local s = tostring(rest or "")
  local link, tail = nil, ""
  -- Try to locate a full item link (optionally prefixed with a color code) like:
  -- |cff....|Hitem:...|h[Name]|h|r  or  |Hitem:...|h[Name]|h
  local hpos = s:find("|Hitem:")
  if hpos then
    -- If there's a color code immediately before the |Hitem:, include it
    local pre = s:sub(1, hpos - 1)
    local cstart = pre:match("()|c%x%x%x%x%x%x%x%x")
    local startpos = cstart or hpos
    -- Prefer the full terminator |h|r
    local endpos = s:find("|h|r", hpos, true)
    if endpos then
      link = s:sub(startpos, endpos + 3) -- include |h|r
      tail = s:sub(endpos + 4)
    else
      -- Fallback: find the next |h
      local endpos2 = s:find("|h", hpos, true)
      if endpos2 then
        link = s:sub(startpos, endpos2 + 1)
        tail = s:sub(endpos2 + 2)
      end
    end
  else
    -- No explicit item link markers found; treat first token as the link
    local a, b = s:match("^(%S+)%s*(.*)$")
    link, tail = a, b or ""
  end
  link = link and trim(link) or nil
  tail = trim(tail or "")
  if not link or link == "" then
    print(PREFIX .. "Usage: /xive score <itemLink> [scaleName]"); return
  end
  local scaleQuery = tail

  -- If a scale is given and Pawn is available, try it first
  if scaleQuery ~= "" and XIVEquip.Pawn and type(XIVEquip.Pawn.ScoreItemLinkWithScale) == "function" then
    local v, _, entry = XIVEquip.Pawn.ScoreItemLinkWithScale(link, scaleQuery)
    if v then
      print(("%sScore: %.2f  (Pawn: %s)"):format(PREFIX, v, (entry and (entry.name or entry.key)) or scaleQuery)); return
    else
      print(PREFIX .. "Pawn scale not found: " .. scaleQuery .. " — falling back to active comparer.")
    end
  end

  local M = XIVEquip.Comparers
  local cmp, resolution
  local lease = acquireComparerPass(M)
  if lease then
    cmp, resolution = lease.comparer, lease.resolution
  end
  local v, src, entry = scoreWithComparer(cmp, link)
  releaseComparerPass(lease)

  if type(v) == "number" then
    local label = (entry and (entry.name or entry.key)) or src or (cmp and cmp.Label) or
        (resolution and resolution.resolved_key) or "active"
    print(PREFIX .. ("Score: %.2f (%s)"):format(v, label))
  else
    print(PREFIX .. "No scorer available.")
  end
end)

-- /xive diag
-- Prints currently-equipped items (non-empty slots only) along with their score under the active comparer.
-- This is intended for manual testing: swap items in a slot, re-run /xive diag, and verify the score changes.
-- [XIVEquip-AUTO] Callback: Callback used by CommandRouter.lua to respond to a timer/event/script hook.
C.RegisterRoot("diag", function(_)
  local slots = {
    { INVSLOT_HEAD,     "Head" },
    { INVSLOT_NECK,     "Neck" },
    { INVSLOT_SHOULDER, "Shoulder" },
    { INVSLOT_BACK,     "Back" },
    { INVSLOT_CHEST,    "Chest" },
    { INVSLOT_WRIST,    "Wrist" },
    { INVSLOT_HAND,     "Hands" },
    { INVSLOT_WAIST,    "Waist" },
    { INVSLOT_LEGS,     "Legs" },
    { INVSLOT_FEET,     "Feet" },
    { INVSLOT_FINGER1,  "Finger1" },
    { INVSLOT_FINGER2,  "Finger2" },
    { INVSLOT_TRINKET1, "Trinket1" },
    { INVSLOT_TRINKET2, "Trinket2" },
    { INVSLOT_MAINHAND, "MainHand" },
    { INVSLOT_OFFHAND,  "OffHand" },
  }

  local M = XIVEquip.Comparers
  local cmp, resolution
  local lease = acquireComparerPass(M)
  if lease then
    cmp, resolution = lease.comparer, lease.resolution
  end

  print(PREFIX .. comparerHeader(cmp, resolution))

  local total = 0
  for _, s in ipairs(slots) do
    local slotID, label = s[1], s[2]
    local link = GetInventoryItemLink("player", slotID)
    if link then
      local score, src = scoreWithComparer(cmp, link, slotID)
      score = tonumber(score) or 0
      total = total + score

      -- Include item level when available (purely informational).
      local ilvl
      if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, v = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok then ilvl = v end
      elseif GetDetailedItemLevelInfo then
        local ok, v = pcall(GetDetailedItemLevelInfo, link)
        if ok then ilvl = v end
      end

      if ilvl then
        print(string.format("%s%s: (ilvl %s) score=%.2f %s", PREFIX, label, tostring(ilvl), score,
          (src and ("[" .. tostring(src) .. "]") or "")))
      else
        print(string.format("%s%s: score=%.2f %s", PREFIX, label, score,
          (src and ("[" .. tostring(src) .. "]") or "")))
      end
    end
  end

  releaseComparerPass(lease)
  print(PREFIX .. string.format("Total score (sum of printed slots): %.2f", total))
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
