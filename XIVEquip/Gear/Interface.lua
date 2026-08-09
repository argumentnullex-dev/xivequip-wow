-- Gear.lua
local addonName, XIVEquip = ...
local L                   = XIVEquip.L
local Comparers           = XIVEquip.Comparers
local Hooks               = XIVEquip.Hooks
local Settings            = XIVEquip.Settings

local Core                = XIVEquip.Gear_Core

local C                   = {}
XIVEquip.Gear             = C

local equipByBasics       = Core.equipByBasics

-- Upvalue to coalesce multiple save requests
local _pendingSpecSaveToken

local SET_EXCLUDED_SLOTS  = { 4, 19 } -- Shirt, Tabard
local VALIDATION_SLOTS    = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
local NAKED_SET_NAME      = "Birthday Suit"

local function callSlotSaveIgnore(slotID, ignored)
  local method = ignored and "IgnoreSlotForSave" or "UnignoreSlotForSave"
  if C_EquipmentSet and type(C_EquipmentSet[method]) == "function" then
    pcall(C_EquipmentSet[method], slotID)
  end

  local legacy = ignored and _G.EquipmentManager_IgnoreSlotForSave or _G.EquipmentManager_UnignoreSlotForSave
  if type(legacy) == "function" then pcall(legacy, slotID) end
end

local function withSetExcludedSlots(fn)
  for _, slotID in ipairs(SET_EXCLUDED_SLOTS) do callSlotSaveIgnore(slotID, true) end
  local ok, a, b, c = pcall(fn)
  for _, slotID in ipairs(SET_EXCLUDED_SLOTS) do callSlotSaveIgnore(slotID, false) end
  if not ok then return false, a end
  return true, a, b, c
end

local function saveNamedEquipmentSet(setName, icon)
  if type(C_EquipmentSet) ~= "table" or not C_EquipmentSet.GetEquipmentSetID then return nil, "api_unavailable" end

  local setID = C_EquipmentSet.GetEquipmentSetID(setName)
  if not setID then
    if C_EquipmentSet.CreateEquipmentSet then
      pcall(C_EquipmentSet.CreateEquipmentSet, setName, icon or 134400)
      setID = C_EquipmentSet.GetEquipmentSetID(setName)
    end
  elseif icon and C_EquipmentSet.ModifyEquipmentSetIcon then
    pcall(C_EquipmentSet.ModifyEquipmentSetIcon, setID, icon)
  end

  if not setID then return nil, "create_failed" end
  if not C_EquipmentSet.SaveEquipmentSet then return nil, "save_unavailable" end

  local ok = withSetExcludedSlots(function()
    C_EquipmentSet.SaveEquipmentSet(setID)
  end)
  if not ok then return nil, "save_failed" end
  return setID
end

local function useEquipmentSet(setName)
  if type(C_EquipmentSet) ~= "table" or not C_EquipmentSet.GetEquipmentSetID then return nil, "api_unavailable" end

  local setID = C_EquipmentSet.GetEquipmentSetID(setName)
  if not setID then return nil, "missing_set" end

  if type(C_EquipmentSet.UseEquipmentSet) == "function" then
    local ok, result = pcall(C_EquipmentSet.UseEquipmentSet, setID)
    if ok and result ~= false then return setID end
  end

  if type(_G.EquipmentManager_EquipSet) == "function" then
    local ok, result = pcall(_G.EquipmentManager_EquipSet, setName)
    if ok and result ~= false then return setID end
  end

  return nil, "use_failed"
end

local function currentSpecSetNameIcon()
  local specIndex = GetSpecialization and GetSpecialization()
  local specName, specIcon = "Spec", nil
  if specIndex and GetSpecializationInfo then
    local _, sName, _, sIcon = GetSpecializationInfo(specIndex)
    if sName and sName ~= "" then specName = sName end
    specIcon = sIcon
  end
  return (specName or "Spec") .. ".xive", specIcon or 134400
end


-- =========================
-- Public API
-- =========================

-- Save the current equipment into a "Spec.xive" set *after* spec has stabilized.
-- Delay defaults to ~0.7s; bumped if needed.
-- [XIVEquip-AUTO] C:_saveSpecSetSoon: Helper for Gear module.
function C:_saveSpecSetSoon(delay, result)
  delay = delay or 0.7
  local token = {}
  _pendingSpecSaveToken = token

  -- Callback used in Interface.lua to run inline logic.
  C_Timer.After(delay, function()
    -- If a newer request came in, skip this one
    if _pendingSpecSaveToken ~= token then return end
    if InCombatLockdown() then return end

    -- Re-read the *current* spec now (don't use any captured value)
    local idx      = GetSpecialization()
    local specName = (idx and select(2, GetSpecializationInfo(idx))) or "Unknown"
    local setName  = string.format("%s.xive", specName)

    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetID then
      print((L.AddonPrefix or "XIVEquip: ") ..
        (L.SpecAuto_NoEM or "Cannot save equipment set: Equipment Manager API not available."))
      return
    end

    local setID = saveNamedEquipmentSet(setName, nil)
    if setID then
      if result then result.set_saved = true end
      if not Settings or not Settings.GetMessage or Settings:GetMessage("Equip") then
        print((L.AddonPrefix or "XIVEquip: ") .. string.format(L.SpecAuto_Saved or "Saved equipment set '%s'.", setName))
      end
    end
  end)
end

function C:PlanBestNative(opts)
  opts = opts or {}
  local Planner = XIVEquip.Planning and XIVEquip.Planning.Coordinator
  local PlanBuilder = XIVEquip.Planning and XIVEquip.Planning.PlanBuilder
  if not (Planner and Planner.Plan and PlanBuilder and PlanBuilder.Build) then
    return nil, "native_planner_unavailable"
  end

  local result = Planner.Plan(opts.native or {})
  local changes, pending, plan = PlanBuilder.Build(result)
  C._lastRecommendationResult = result
  C._socketPotential = {}
  C._boeReminders = {}
  return changes, pending, plan, result
end

function C:GetLastRecommendationResult()
  return C._lastRecommendationResult
end

local function wantsNativePlanner(opts)
  if opts and (opts.planner == "native" or opts.useNativePlanner == true) then return true end
  if opts and (opts.planner == "legacy" or opts.useNativePlanner == false) then return false end
  return Settings and type(Settings.GetPlannerMode) == "function" and Settings:GetPlannerMode() == "native"
end

local function nativeFailureDetail(err)
  local text = tostring(err or "native planner failed")
  if debugstack then return text .. "\n" .. tostring(debugstack(2) or "") end
  if debug and type(debug.traceback) == "function" then return debug.traceback(text, 2) end
  return text
end

local function logNativePlannerFailure(detail)
  local message = "Native 2.0 planner failed; aborting without legacy fallback: " .. tostring(detail or "unknown error")
  if XIVEquip.Log and type(XIVEquip.Log.Error) == "function" then
    XIVEquip.Log.Error(message)
  elseif XIVEquip.Log and type(XIVEquip.Log.Warn) == "function" then
    XIVEquip.Log.Warn(message)
  end
end

-- PlanBest returns (changes, pending, plan)
-- [XIVEquip-AUTO] C:PlanBest: Helper for Gear module.
function C:PlanBest(cmp, opts)
  opts = opts or {}
  if wantsNativePlanner(opts) then
    local ok, changes, pendingOrErr, plan, result = xpcall(function()
      return C:PlanBestNative(opts)
    end, nativeFailureDetail)
    if ok and changes then return changes, pendingOrErr, plan, result end

    local detail = pendingOrErr or changes or "native planner failed"
    logNativePlannerFailure(detail)
    return nil, false, nil, nil, detail
  end

  -- Reset per-pass socket potential messages
  if Core and type(Core.ClearSocketPotential) == "function" then
    Core.ClearSocketPotential()
  end

  if Core and type(Core.ClearBoEReminders) == "function" then
    Core.ClearBoEReminders()
  end

  local used = {}
  local plan, changes = {}, {}
  local hadPending = false

  -- Orchestrate planners in this order
  local planners = {
    XIVEquip.Armor,
    XIVEquip.Jewelry,
    XIVEquip.Weapons,
  }

  for _, planner in ipairs(planners) do
    -- No fallbacks: assume modules are loaded and expose PlanBest
    local pChanges, pPending, pPlan = planner:PlanBest(cmp, opts, used)

    for _, r in ipairs(pChanges or {}) do table.insert(changes, r) end
    for _, p in ipairs(pPlan or {}) do table.insert(plan, p) end
    hadPending = hadPending or (pPending == true)
  end

  -- Capture socket potential records for UI / equip messages
  C._socketPotential = (Core and type(Core.GetSocketPotential) == "function") and (Core.GetSocketPotential() or {}) or {}
  C._boeReminders = (Core and type(Core.GetBoEReminders) == "function") and (Core.GetBoEReminders() or {}) or {}


  return changes, hadPending, plan
end

-- Public: get socket potential records from the last planning pass
function C:GetSocketPotential()
  return C._socketPotential or {}
end

function C:GetBoEReminders()
  return C._boeReminders or {}
end

local function newEquipRunResult(plan, pending)
  return {
    planned_count = #(plan or {}),
    succeeded = 0,
    failed = 0,
    manual_required = 0,
    skipped = 0,
    timed_out = 0,
    pending_data = pending == true,
    set_saved = false,
    save_scheduled = false,
    completed = false,
    messages = {},
    steps = {},
  }
end

local function addResultMessage(result, text)
  if not (result and text) then return end
  table.insert(result.messages, text)
end

local function printResult(result, text)
  addResultMessage(result, text)
  print((L.AddonPrefix or "XIVEquip: ") .. text)
end

local function itemID(link)
  return Core.itemIDFromLink and Core.itemIDFromLink(link) or nil
end

local function pickLinkFor(pick)
  pick = pick or {}
  return pick.newLink
      or (pick.bag and pick.slot and GetContainerItemLink and GetContainerItemLink(pick.bag, pick.slot))
      or (pick.fromSlot and GetInventoryItemLink("player", pick.fromSlot))
      or pick.link
      or ""
end

local function pickSlotFor(pick)
  pick = pick or {}
  return pick.targetSlot
      or (pick.equipLoc and Core.INV_BY_EQUIPLOC and Core.INV_BY_EQUIPLOC[pick.equipLoc])
end

local function isSlotLocked(slotID)
  return slotID and IsInventoryItemLocked and IsInventoryItemLocked(slotID)
end

local function isUnboundBoE(pick, link)
  if not (link and link ~= "" and GetItemInfo) then return false end
  local bindType = select(14, GetItemInfo(link))
  if bindType ~= 2 then return false end
  if pick and pick.loc and C_Item and type(C_Item.IsBound) == "function" then
    local ok, bound = pcall(C_Item.IsBound, pick.loc)
    if ok and bound then return false end
  end
  return true
end

function C:GetLastEquipResult()
  return C._lastEquipResult
end

function C:_completeEquipRun(result, comparerOwner, showEquip, opts)
  opts = opts or {}
  if result.completed then return result end
  result.completed = true

  if opts.failureMessage then
    printResult(result, opts.failureMessage)
  elseif showEquip then
    if result.pending_data and result.planned_count == 0 then
      printResult(result, opts.pendingMessage or "Item data is still loading; try again shortly.")
    elseif result.planned_count == 0 then
      printResult(result, L.NoUpgrades or "No upgrades found.")
    elseif result.succeeded == 0 and (result.failed + result.manual_required + result.timed_out + result.skipped) > 0 then
      printResult(result, "Upgrade plan did not complete.")
    end
  end

  if comparerOwner and type(comparerOwner.EndPass) == "function" then
    comparerOwner:EndPass()
  end

  local autoSave = opts.autoSave
  if autoSave == nil then
    autoSave = Settings and Settings.GetAutomation and Settings:GetAutomation("SaveSpecSet")
  end

  if result.succeeded > 0 and autoSave and not InCombatLockdown() then
    result.save_scheduled = true
    C:_saveSpecSetSoon(opts.saveDelay or 0.7, result)
  end

  if opts.onComplete then opts.onComplete(result) end
  return result
end

function C:_runEquipPlan(plan, opts)
  opts = opts or {}
  plan = plan or {}
  local showEquip = opts.showEquip == true
  local result = opts.result or newEquipRunResult(plan, opts.pending)
  local maxLockRetries = opts.maxLockRetries or 20
  local lockDelay = opts.lockDelay or 0.05
  local stepDelay = opts.stepDelay or 0.05
  local verifyDelay = opts.verifyDelay or 0.10
  C._lastEquipResult = result

  local function complete()
    return C:_completeEquipRun(result, opts.comparerOwner, showEquip, opts)
  end

  if result.pending_data or #plan == 0 then
    complete()
    return result
  end

  local function step(index)
    if index > #plan then
      C_Timer.After(opts.finishDelay or 0.06, complete)
      return
    end

    if InCombatLockdown() then
      result.skipped = result.skipped + (#plan - index + 1)
      if showEquip then printResult(result, L.CannotCombat or "Cannot equip while in combat.") end
      complete()
      return
    end

    local pick = plan[index] or {}
    local slotID = pickSlotFor(pick)
    local pickLink = pickLinkFor(pick)

    local function waitForUnlockedThenEquip(attempt)
      if isSlotLocked(slotID) then
        if attempt >= maxLockRetries then
          result.timed_out = result.timed_out + 1
          table.insert(result.steps, { index = index, status = "timed_out", slot = slotID, reason = "slot_locked_before_equip" })
          C_Timer.After(stepDelay, function() step(index + 1) end)
          return
        end
        C_Timer.After(lockDelay, function() waitForUnlockedThenEquip(attempt + 1) end)
        return
      end

      if InCombatLockdown() then
        result.skipped = result.skipped + (#plan - index + 1)
        if showEquip then printResult(result, L.CannotCombat or "Cannot equip while in combat.") end
        complete()
        return
      end

      local oldLink = slotID and GetInventoryItemLink("player", slotID) or nil
      local wasBoEUnbound = isUnboundBoE(pick, pickLink)
      local ok, err = pcall(function() equipByBasics(pick) end)
      if not ok then
        result.failed = result.failed + 1
        table.insert(result.steps, { index = index, status = "failed", slot = slotID, reason = tostring(err or "equip_error") })
        C_Timer.After(stepDelay, function() step(index + 1) end)
        return
      end

      if wasBoEUnbound then
        local nowLink = slotID and GetInventoryItemLink("player", slotID) or nil
        if itemID(nowLink) ~= itemID(pickLink) then
          result.manual_required = result.manual_required + 1
          table.insert(result.steps, { index = index, status = "manual_required", slot = slotID, reason = "bind_on_equip" })
          if showEquip then
            printResult(result, string.format("%s is Bind on Equip and must be equipped manually.", tostring(pickLink or "(item)")))
          end
          if ClearCursor then ClearCursor() end
          C_Timer.After(stepDelay, function() step(index + 1) end)
          return
        end
      end

      local function verify(attempt)
        if isSlotLocked(slotID) then
          if attempt >= maxLockRetries then
            result.timed_out = result.timed_out + 1
            table.insert(result.steps, { index = index, status = "timed_out", slot = slotID, reason = "slot_locked_after_equip" })
            C_Timer.After(stepDelay, function() step(index + 1) end)
            return
          end
          C_Timer.After(lockDelay, function() verify(attempt + 1) end)
          return
        end

        local newLink = slotID and GetInventoryItemLink("player", slotID) or nil
        local intendedID = itemID(pickLink)
        local changed = newLink ~= oldLink
        local intendedEquipped = (not intendedID) or itemID(newLink) == intendedID

        if changed and intendedEquipped then
          result.succeeded = result.succeeded + 1
          table.insert(result.steps, { index = index, status = "success", slot = slotID })
          if showEquip then
            local oldText = oldLink or "|cff888888(None)|r"
            local newText = newLink or "|cff888888(None)|r"
            printResult(result, string.format(L.ReplacedWith or "Replaced %s with %s.", oldText, newText))
          end
        else
          result.failed = result.failed + 1
          table.insert(result.steps, { index = index, status = "failed", slot = slotID, reason = changed and "wrong_item" or "no_change" })
        end

        C_Timer.After(stepDelay, function() step(index + 1) end)
      end

      C_Timer.After(verifyDelay, function() verify(0) end)
    end

    waitForUnlockedThenEquip(0)
  end

  step(1)
  return result
end

local function printSocketPotential()
  local recs = C:GetSocketPotential() or {}
  for _, r in ipairs(recs) do
    local assumed = string.format("+%d %s", tonumber(r.assumedAmount) or 10,
      tostring(r.assumedStat or "best secondary"))
    local sockTxt = (tonumber(r.emptySockets) or 1) == 1 and "an empty socket" or
        (tostring(r.emptySockets) .. " empty sockets")
    local delta = tonumber(r.potentialDeltaScore) or 0
    print((L.AddonPrefix or "XIVEquip: ") .. string.format(
      "%s has %s and could potentially be an upgrade if gemmed (assumes %s): potential %+0.1f score improvement over alternative items.",
      tostring(r.link or "(item)"), sockTxt, assumed, delta))
  end
end

-- [XIVEquip-AUTO] C:EquipBest: Applies equipment changes (gear/weapons) for the addon.
function C:EquipBest(opts)
  opts = opts or {}
  if InCombatLockdown() then
    print((L.AddonPrefix or "XIVEquip: ") .. (L.CannotCombat or "Cannot equip while in combat."))
    return nil
  end

  local useNativePlanner = wantsNativePlanner(opts)
  local cmp = nil
  if not useNativePlanner then cmp = Comparers:StartPass() end
  local showEquip = not (Settings and Settings.GetMessage) or Settings:GetMessage("Equip")
  local _, pending, plan, _, nativeFailure = C:PlanBest(cmp, opts)
  plan = plan or {}

  if useNativePlanner and nativeFailure then
    local result = newEquipRunResult({}, false)
    result.failed = 1
    table.insert(result.steps, { index = 1, status = "failed", reason = "native_planner_failed", detail = tostring(nativeFailure) })
    C._lastEquipResult = result
    return C:_completeEquipRun(result, nil, showEquip, {
      failureMessage = "Native 2.0 planner failed; no gear was equipped. Check the XIVEquip debug log for details.",
      onComplete = opts.onComplete,
    })
  end

  printSocketPotential()

  local attempt = opts._pendingAttempt or 0
  local maxDataRetries = opts.maxDataRetries or 2
  if pending then
    local result = newEquipRunResult(plan, true)
    C._lastEquipResult = result
    local retrying = attempt < maxDataRetries
    local comparerOwner = nil
    if not useNativePlanner then comparerOwner = Comparers end
    if not retrying then
      result.timed_out = result.timed_out + 1
      C:_completeEquipRun(result, comparerOwner, showEquip, opts)
    elseif (not useNativePlanner) and Comparers and type(Comparers.EndPass) == "function" then
      Comparers:EndPass()
    end
    if retrying then
      C_Timer.After(opts.retryDelay or 0.25, function()
        local nextOpts = {}
        for k, v in pairs(opts) do nextOpts[k] = v end
        nextOpts._pendingAttempt = attempt + 1
        C:EquipBest(nextOpts)
      end)
    end
    return result
  end

  local comparerOwner = nil
  if not useNativePlanner then comparerOwner = Comparers end

  return C:_runEquipPlan(plan, {
    comparerOwner = comparerOwner,
    showEquip = showEquip,
    autoSave = opts.autoSave,
    saveDelay = opts.saveDelay,
    onComplete = opts.onComplete,
    maxLockRetries = opts.maxLockRetries,
    lockDelay = opts.lockDelay,
    stepDelay = opts.stepDelay,
    verifyDelay = opts.verifyDelay,
    finishDelay = opts.finishDelay,
  })
end

function C:SaveNamedEquipmentSet(setName, icon)
  return saveNamedEquipmentSet(setName, icon)
end

local function missingValidationSlots(includeOffhand)
  local missing = {}
  for _, slotID in ipairs(VALIDATION_SLOTS) do
    if not (GetInventoryItemLink and GetInventoryItemLink("player", slotID)) then
      table.insert(missing, slotID)
    end
  end
  if includeOffhand and not (GetInventoryItemLink and GetInventoryItemLink("player", 17)) then
    table.insert(missing, 17)
  end
  return missing
end

local function planIncludesSlot(result, slotID)
  for _, step in ipairs((result and result.steps) or {}) do
    if step.slot == slotID then return true end
  end
  return false
end

-- Confirms the currently-equipped gear is what PlanBest would recommend --
-- i.e. the highest-scoring legal item in every slot, not merely "a slot got
-- filled". A fresh PlanBest pass against the now-equipped state should find
-- nothing left to change; if it does, the equip wasn't actually optimal.
local function checkFullyOptimal()
  if not (Comparers and type(Comparers.StartPass) == "function") then
    return true, {}
  end
  local cmp = Comparers:StartPass()
  local _, pending, plan = C:PlanBest(cmp)
  if Comparers.EndPass then Comparers:EndPass() end
  return (not pending) and #(plan or {}) == 0, plan or {}, pending == true
end

function C:ValidateNakedEquip(opts)
  opts = opts or {}
  local nakedSetName = opts.nakedSetName or NAKED_SET_NAME
  if InCombatLockdown and InCombatLockdown() then
    print((L.AddonPrefix or "XIVEquip: ") .. (L.CannotCombat or "Cannot equip while in combat."))
    return nil
  end

  local backupID, backupErr = saveNamedEquipmentSet("backup.xive", 134400)
  if not backupID then
    print((L.AddonPrefix or "XIVEquip: ") .. "Validation aborted: could not save backup.xive (" .. tostring(backupErr or "unknown") .. ").")
    return nil
  end

  local nakedID, nakedErr = useEquipmentSet(nakedSetName)
  if not nakedID then
    print((L.AddonPrefix or "XIVEquip: ") .. "Validation aborted: could not equip " .. tostring(nakedSetName) .. " (" .. tostring(nakedErr or "unknown") .. ").")
    return nil
  end

  print((L.AddonPrefix or "XIVEquip: ") .. "Saved backup.xive and equipped " .. tostring(nakedSetName) .. ".")

  local state = {
    backupSetID = backupID,
    nakedSetID = nakedID,
    nakedSetName = nakedSetName,
  }

  C_Timer.After(opts.nakedDelay or 0.4, function()
    state.result = C:EquipBest({
      autoSave = false,
      onComplete = function(result)
        C_Timer.After(opts.validationDelay or 0.2, function()
          local missing = missingValidationSlots(planIncludesSlot(result, 17))
          if #missing == 0 then
            local optimal, remainingPlan, stillPending = checkFullyOptimal()
            if stillPending then
              print((L.AddonPrefix or "XIVEquip: ") ..
                "Validation failed: item data is still loading; could not confirm equipped gear is optimal.")
            elseif not optimal then
              local names = {}
              for _, pick in ipairs(remainingPlan) do
                local slotID = pick and pick.targetSlot
                names[#names + 1] = (Core.SLOT_LABEL and Core.SLOT_LABEL[slotID]) or ("Slot " .. tostring(slotID))
              end
              print((L.AddonPrefix or "XIVEquip: ") ..
                "Validation failed: equipped gear is not the top recommendation for " .. table.concat(names, ", ") .. ".")
            else
              print((L.AddonPrefix or "XIVEquip: ") .. "Validation passed: expected slots are equipped.")
              local setName, setIcon = currentSpecSetNameIcon()
              local setID, saveErr = saveNamedEquipmentSet(setName, setIcon)
              if setID then
                print((L.AddonPrefix or "XIVEquip: ") .. string.format(L.SpecAuto_Saved or "Saved equipment set '%s'.", setName))
              else
                print((L.AddonPrefix or "XIVEquip: ") .. "Validation passed, but could not save " .. tostring(setName) .. " (" .. tostring(saveErr or "unknown") .. ").")
              end
            end
          else
            local names = {}
            for _, slotID in ipairs(missing) do
              names[#names + 1] = (Core.SLOT_LABEL and Core.SLOT_LABEL[slotID]) or ("Slot " .. tostring(slotID))
            end
            print((L.AddonPrefix or "XIVEquip: ") .. "Validation failed: missing " .. table.concat(names, ", ") .. ".")
          end
        end)
        if opts.onComplete then opts.onComplete(result) end
      end,
    })
  end)

  return state
end

-- =========================
-- Equipment Set helper
-- =========================
-- Saves the *currently equipped* items to a gear set named "<Spec>.xive".
-- If the set doesn't exist yet, it is created (using the spec icon if available), then saved.
-- [XIVEquip-AUTO] C:SaveEquippedToSpecSet: Helper for Gear module.
function C:SaveEquippedToSpecSet()
  -- Be graceful if the API isn't available or we're in combat
  if type(C_EquipmentSet) ~= "table" or InCombatLockdown and InCombatLockdown() then return end

  local setName, specIcon = currentSpecSetNameIcon()
  return saveNamedEquipmentSet(setName, specIcon), setName
end
