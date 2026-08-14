-- Gear.lua
local addonName, XIVEquip = ...
local L                   = XIVEquip.L
local Hooks               = XIVEquip.Hooks
local Settings            = XIVEquip.Settings

local Core                = XIVEquip.Gear_Core

local C                   = {}
XIVEquip.Gear             = C

local equipByBasics       = Core.equipByBasics

-- Upvalue to coalesce multiple save requests
local _pendingSpecSaveToken

-- =========================
-- BOE bind-confirmation waiting
-- =========================
-- Only one Blizzard bind-confirmation popup can ever be pending at a time
-- (single player, and _runEquipPlan only moves to the next plan step once
-- the current one fully resolves), so a single module-level slot -- not one
-- per _runEquipPlan call -- correctly models "the confirmation currently
-- being waited on, if any".
local _boeConfirmFrame = (type(CreateFrame) == "function") and CreateFrame("Frame") or nil
local _activeBindWait
local _bindGeneration = 0

local function bindConfirmationCard()
  return XIVEquip.UI and XIVEquip.UI.BindConfirmationCard
end

local function showBindConfirmationCard(details)
  local card = bindConfirmationCard()
  if card and type(card.Show) == "function" then pcall(card.Show, details) end
end

local function hideBindConfirmationCard()
  local card = bindConfirmationCard()
  if card and type(card.Hide) == "function" then pcall(card.Hide) end
end

local BIND_WAIT_EVENTS = {
  "EQUIP_BIND_CONFIRM", "EQUIP_BIND_REFUNDABLE_CONFIRM", "EQUIP_BIND_TRADEABLE_CONFIRM",
  "PLAYER_EQUIPMENT_CHANGED",
}
local BIND_CONFIRM_EVENT_SET = {
  EQUIP_BIND_CONFIRM = true, EQUIP_BIND_REFUNDABLE_CONFIRM = true, EQUIP_BIND_TRADEABLE_CONFIRM = true,
}
-- StaticPopupDialogs keys for the three bind-confirm dialog skins (retail
-- Blizzard_StaticPopup_Game/GameDialogDefs.lua): EQUIP_BIND, EQUIP_BIND_REFUNDABLE,
-- EQUIP_BIND_TRADEABLE. All three share identical OnAccept (EquipPendingItem)
-- and OnCancel/OnHide (CancelPendingEquip) semantics.
local BIND_DIALOG_WHICH = {
  EQUIP_BIND = true, EQUIP_BIND_REFUNDABLE = true, EQUIP_BIND_TRADEABLE = true,
}

if _boeConfirmFrame then
  _boeConfirmFrame:SetScript("OnEvent", function(_, event, arg1)
    if not _activeBindWait then return end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
      _activeBindWait.onEquipmentChanged(arg1)
    elseif BIND_CONFIRM_EVENT_SET[event] then
      -- Confirms Blizzard really did enter a pending-equip state for our
      -- slot (and, if the dialog skin changes mid-flight -- e.g. Blizzard
      -- switching from EQUIP_BIND_REFUNDABLE to EQUIP_BIND for the same
      -- item -- lets onDialogHidden below tell that apart from a real
      -- close). Not itself required for success detection: that's
      -- PLAYER_EQUIPMENT_CHANGED's job.
      _activeBindWait.confirmSeen = (_activeBindWait.confirmSeen or 0) + 1
      _activeBindWait.showCard()
    end
  end)
end

-- Never touches StaticPopupDialogs["EQUIP_BIND"/"EQUIP_BIND_REFUNDABLE"/
-- "EQUIP_BIND_TRADEABLE"] -- OnAccept/OnCancel/OnHide stay exactly
-- Blizzard's own. hooksecurefunc is a pure post-call observer: it cannot run
-- before, replace, or block the original. Hook StaticPopup_OnHide rather than
-- StaticPopup_Hide: Blizzard's popup buttons call dialog:Hide() directly, so
-- the latter is not involved when the user clicks either OK or Cancel.
-- This only tells us that a matching dialog closed, never why, which is why
-- success is still decided solely by PLAYER_EQUIPMENT_CHANGED above.
if type(hooksecurefunc) == "function" then
  hooksecurefunc("StaticPopup_OnHide", function(dialog)
    local which = dialog and dialog.which
    if _activeBindWait and BIND_DIALOG_WHICH[which] then
      hideBindConfirmationCard()
      _activeBindWait.onDialogHidden()
    end
  end)
end

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

-- PlanBestImpl does the real work; PlanBest below wraps it in xpcall so a
-- planner error is reported cleanly instead of propagating raw.
function C:PlanBestImpl(opts)
  opts = opts or {}
  local Planner = XIVEquip.Planning and XIVEquip.Planning.Coordinator
  local PlanBuilder = XIVEquip.Planning and XIVEquip.Planning.PlanBuilder
  if not (Planner and Planner.Plan and PlanBuilder and PlanBuilder.Build) then
    return nil, "planner_unavailable"
  end

  local result = Planner.Plan(opts.planner or {})
  local changes, pending, plan = PlanBuilder.Build(result)
  C._lastRecommendationResult = result
  C._socketPotential = {}
  C._boeReminders = {}
  return changes, pending, plan, result
end

function C:GetLastRecommendationResult()
  return C._lastRecommendationResult
end

local function planFailureDetail(err)
  local text = tostring(err or "planner failed")
  if debugstack then return text .. "\n" .. tostring(debugstack(2) or "") end
  if debug and type(debug.traceback) == "function" then return debug.traceback(text, 2) end
  return text
end

local function logPlanFailure(detail)
  local fullDetail = tostring(detail or "unknown error")
  local summary = fullDetail:match("^[^\r\n]+") or fullDetail
  local message = "Planner failed; aborting: " .. summary
  if XIVEquip.Log and type(XIVEquip.Log.Error) == "function" then
    XIVEquip.Log.Error(message)
  elseif XIVEquip.Log and type(XIVEquip.Log.Warn) == "function" then
    XIVEquip.Log.Warn(message)
  end
  if XIVEquip.Log and type(XIVEquip.Log.Debugf) == "function" then
    XIVEquip.Log.Debugf("force", "Planner failure detail:\n%s", fullDetail)
  end
end

-- PlanBest returns (changes, pending, plan)
-- [XIVEquip-AUTO] C:PlanBest: Helper for Gear module.
function C:PlanBest(opts)
  opts = opts or {}
  local ok, changes, pendingOrErr, plan, result = xpcall(function()
    return C:PlanBestImpl(opts)
  end, planFailureDetail)
  if ok and changes then return changes, pendingOrErr, plan, result end

  local detail = pendingOrErr or changes or "planner failed"
  logPlanFailure(detail)
  return nil, false, nil, nil, detail
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
    bind_declined = 0,
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
  if pick.action == "unequip" then return "" end
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

local function unequipSlot(slotID)
  if not slotID then return nil end
  if not (PickupInventoryItem and PutItemInBackpack) then error("unequip_api_unavailable") end
  if ClearCursor then ClearCursor() end
  PickupInventoryItem(slotID)
  PutItemInBackpack()
  if ClearCursor then ClearCursor() end
end

local function isSlotLocked(slotID)
  return slotID and IsInventoryItemLocked and IsInventoryItemLocked(slotID)
end

-- Enum.ItemBind.OnEquip = 2 is classic Bind-on-Equip. Enum.ItemBind.
-- ToBnetAccountUntilEquipped = 9 is "Warbound Until Equipped" -- extremely
-- common on current-tier crafted gear and drops -- which is tradeable/
-- sendable across the Warband right up until the moment it's equipped, at
-- which point it commits (soulbinds) exactly like a classic BoE does, and
-- triggers the same EQUIP_BIND_TRADEABLE_CONFIRM popup gate. Both need the
-- same await-confirmation treatment; only 9 was missing here, which meant
-- a Warbound-Until-Equipped item was silently treated as an ordinary item
-- with no wait at all.
local NEEDS_BIND_CONFIRM = { [2] = true, [9] = true }

local function isUnboundBoE(pick, link)
  if not (link and link ~= "" and GetItemInfo) then return false end
  local bindType = select(14, GetItemInfo(link))
  if not NEEDS_BIND_CONFIRM[bindType] then return false end
  if pick and pick.loc and C_Item and type(C_Item.IsBound) == "function" then
    local ok, bound = pcall(C_Item.IsBound, pick.loc)
    if ok and bound then return false end
  end
  return true
end

function C:GetLastEquipResult()
  return C._lastEquipResult
end

function C:_completeEquipRun(result, showEquip, opts)
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
    elseif result.succeeded == 0 and (result.failed + result.manual_required + result.timed_out + result.skipped + result.bind_declined) > 0 then
      printResult(result, "Upgrade plan did not complete.")
    end
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
    return C:_completeEquipRun(result, showEquip, opts)
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
      local ok, err = pcall(function()
        if pick.action == "unequip" then
          unequipSlot(slotID)
        else
          -- Don't clear the cursor right after attempting to equip a
          -- possibly-unbound item: if it needs a bind confirmation, the
          -- item is parked on the cursor while Blizzard's popup is
          -- pending, and clearing it now would silently discard that
          -- state before the popup ever gets a chance to appear. finish()
          -- below (in awaitBindConfirmation) clears it once the wait
          -- actually resolves, whichever way.
          equipByBasics(pick, wasBoEUnbound)
        end
      end)
      if not ok then
        result.failed = result.failed + 1
        table.insert(result.steps, { index = index, status = "failed", slot = slotID, reason = tostring(err or "equip_error") })
        C_Timer.After(stepDelay, function() step(index + 1) end)
        return
      end

      -- An unbound BOE that didn't equip synchronously almost certainly
      -- just triggered Blizzard's own EQUIP_BIND confirmation popup. Let
      -- that popup obtain the user's confirmation click (it alone may call
      -- the protected EquipPendingItem/CancelPendingEquip) and pause this
      -- plan step until PLAYER_EQUIPMENT_CHANGED tells us it resolved --
      -- rather than assuming failure and skipping straight to manual_required.
      local function awaitBindConfirmation()
        local intendedID = itemID(pickLink)
        local generation = _bindGeneration + 1
        _bindGeneration = generation

        local resolved = false
        local wait

        local function finish(status, reason)
          if resolved then return end
          resolved = true
          if _boeConfirmFrame then
            for _, evt in ipairs(BIND_WAIT_EVENTS) do _boeConfirmFrame:UnregisterEvent(evt) end
          end
          if _activeBindWait == wait then _activeBindWait = nil end
          hideBindConfirmationCard()
          result.awaiting = nil
          if ClearCursor then ClearCursor() end

          if status == "success" then
            result.succeeded = result.succeeded + 1
            table.insert(result.steps, { index = index, status = "success", slot = slotID })
            if showEquip then
              local oldText = oldLink or "|cff888888(None)|r"
              local newText = pickLink or "|cff888888(None)|r"
              printResult(result, string.format(L.ReplacedWith or "Replaced %s with %s.", oldText, newText))
            end
          elseif status == "bind_declined" then
            result.bind_declined = result.bind_declined + 1
            table.insert(result.steps, { index = index, status = "bind_declined", slot = slotID, reason = reason or "user_cancelled" })
            if showEquip then
              printResult(result, string.format("Declined binding %s; leaving it unequipped.", tostring(pickLink or "(item)")))
            end
          else
            result.timed_out = result.timed_out + 1
            table.insert(result.steps, { index = index, status = "timed_out", slot = slotID, reason = reason or "bind_confirmation_timeout" })
          end

          C_Timer.After(stepDelay, function() step(index + 1) end)
        end

        local preview = pick.preview or {
          slot = slotID,
          slotName = (Core.SLOT_LABEL and Core.SLOT_LABEL[slotID]) or ("Slot " .. tostring(slotID)),
          oldLink = oldLink,
          newLink = pickLink,
          deltaScore = pick.deltaScore,
          deltaIlvl = pick.deltaIlvl,
        }

        wait = {
          generation = generation,
          slot = slotID,
          confirmSeen = 0,
          showCard = function() showBindConfirmationCard(preview) end,
          -- PLAYER_EQUIPMENT_CHANGED(equipSlot, hasCurrent): the only
          -- authoritative success signal -- EquipPendingItem's actual equip
          -- is a server round-trip, so it lands after the dialog has
          -- already closed, not synchronously with the accept click.
          onEquipmentChanged = function(changedSlot)
            if changedSlot ~= slotID then return end
            local newLink = GetInventoryItemLink("player", slotID)
            if (not intendedID) or itemID(newLink) == intendedID then
              finish("success")
            end
          end,
          -- The dialog's OnHide fires on BOTH accept and cancel (Blizzard's
          -- own defensive "cancel anything still pending" cleanup), so a
          -- hide alone can't distinguish them. Give a short grace window for
          -- an in-flight accept's PLAYER_EQUIPMENT_CHANGED to land first;
          -- only conclude "declined" if nothing arrived by then. If a fresh
          -- confirm event arrived after this hide (confirmSeen advanced),
          -- Blizzard just switched dialog skins for the same still-pending
          -- item -- not a real close -- so skip resolving.
          onDialogHidden = function()
            local seenAtHide = wait.confirmSeen
            C_Timer.After(opts.bindCancelGraceDelay or 1.5, function()
              if resolved then return end
              if wait.confirmSeen ~= seenAtHide then return end
              finish("bind_declined")
            end)
          end,
        }
        _activeBindWait = wait
        result.awaiting = { slot = slotID, link = pickLink, status = "awaiting_bind_confirmation" }

        if _boeConfirmFrame then
          for _, evt in ipairs(BIND_WAIT_EVENTS) do _boeConfirmFrame:RegisterEvent(evt) end
        end

        -- EquipCursorItem fires the confirmation event synchronously before
        -- this waiter can be installed. By this point Blizzard's dialog is
        -- already visible, so perform the initial companion-card show now;
        -- subsequent confirmation events (including dialog-skin switches)
        -- refresh it through the event handler above.
        wait.showCard()

        if showEquip then
          printResult(result, string.format("Confirm the bind-on-equip popup for %s to continue equipping.", tostring(pickLink or "(item)")))
        end

        -- Conservative fallback: Blizzard's dialogs never auto-timeout
        -- (timeout = 0), so this exists purely so a missing event or an
        -- unusual UI condition can't leave the executor stuck forever.
        C_Timer.After(opts.bindConfirmTimeout or 45, function() finish("timed_out") end)
      end

      if wasBoEUnbound then
        local nowLink = slotID and GetInventoryItemLink("player", slotID) or nil
        if itemID(nowLink) ~= itemID(pickLink) then
          awaitBindConfirmation()
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

  local showEquip = not (Settings and Settings.GetMessage) or Settings:GetMessage("Equip")
  local planOk, changesOrErr, pending, plan, planResult, planFailure = xpcall(function()
    return C:PlanBest(opts)
  end, planFailureDetail)
  if not planOk then
    error(changesOrErr, 0)
  end
  plan = plan or {}

  if planFailure then
    local result = newEquipRunResult({}, false)
    result.failed = 1
    table.insert(result.steps, { index = 1, status = "failed", reason = "planner_failed", detail = tostring(planFailure) })
    C._lastEquipResult = result
    return C:_completeEquipRun(result, showEquip, {
      failureMessage = "Planner failed; no gear was equipped. Check the XIVEquip debug log for details.",
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
    if not retrying then
      result.timed_out = result.timed_out + 1
      C:_completeEquipRun(result, showEquip, opts)
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

  return C:_runEquipPlan(plan, {
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
  local ok, errOrChanges, pending, plan, planResult, planFailure = xpcall(function()
    return C:PlanBest()
  end, planFailureDetail)
  if not ok or planFailure then return false, plan or {}, false, "failed", planFailure or errOrChanges end
  if pending then return false, plan or {}, true, "pending" end
  if #(plan or {}) > 0 then return false, plan or {}, false, "remaining" end
  return true, {}, false, "optimal"
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
            local optimal, remainingPlan, stillPending, validationStatus, validationError = checkFullyOptimal()
            if validationStatus == "failed" then
              print((L.AddonPrefix or "XIVEquip: ") ..
                "Validation failed: planner failed during post-equip verification; could not confirm equipped gear is optimal.")
              if XIVEquip.Log and type(XIVEquip.Log.Error) == "function" then
                XIVEquip.Log.Error("Post-equip validation planner failure: " .. tostring(validationError or "unknown error"))
              end
            elseif stillPending then
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
