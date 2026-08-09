-- Tests/Regression.lua
-- In-game regression checks and fixture capture helpers.
local addon, XIVEquip = ...
XIVEquip = XIVEquip or {}
XIVEquip.Tests = XIVEquip.Tests or {}

local Tests = XIVEquip.Tests
local Cmd = XIVEquip.Commands
local PREFIX = (XIVEquip.L and XIVEquip.L.AddonPrefix) or "XIVEquip: "

local function now()
  if date then return date("!%Y-%m-%dT%H:%M:%SZ") end
  return "unknown"
end

local function printLine(text)
  print(PREFIX .. tostring(text or ""))
end

local function shallowCopy(t)
  local out = {}
  if type(t) == "table" then
    for k, v in pairs(t) do out[k] = v end
  end
  return out
end

local function restoreTable(target, snapshot)
  if type(target) ~= "table" then return end
  for k in pairs(target) do target[k] = nil end
  for k, v in pairs(snapshot or {}) do target[k] = v end
end

local function withPatchedTable(target, patch, fn)
  local original = {}
  for k in pairs(patch or {}) do original[k] = target and target[k] end
  for k, v in pairs(patch or {}) do target[k] = v end

  local ok, a, b, c = pcall(fn)

  for k in pairs(patch or {}) do target[k] = original[k] end
  if not ok then error(a, 0) end
  return a, b, c
end

local function fail(message)
  error(message or "failed", 0)
end

local function expectEqual(actual, expected, message)
  if actual ~= expected then
    fail(string.format("%s: expected %s, got %s", message or "value mismatch", tostring(expected), tostring(actual)))
  end
end

local function expectTruthy(value, message)
  if not value then fail(message or "expected truthy value") end
end

local function expectFalsy(value, message)
  if value then fail(message or "expected falsy value") end
end

local cases = {}
local function addCase(name, fn)
  cases[#cases + 1] = { name = name, fn = fn }
end

local function getSettings()
  _G.XIVEquip_Settings = _G.XIVEquip_Settings or {}
  if XIVEquip.Settings and XIVEquip.Settings.Initialize then
    XIVEquip.Settings:Initialize()
  end
  return _G.XIVEquip_Settings
end

local function setComparer(key)
  if XIVEquip.Settings and XIVEquip.Settings.SetComparerName then
    XIVEquip.Settings:SetComparerName(key)
  else
    getSettings().Comparer = getSettings().Comparer or {}
    getSettings().Comparer.Selected = key
  end
end

local function getComparer()
  if XIVEquip.Settings and XIVEquip.Settings.GetComparerName then
    return XIVEquip.Settings:GetComparerName()
  end
  local st = getSettings()
  return st.Comparer and st.Comparer.Selected
end

local function withSavedSettings(fn)
  local st = getSettings()
  local snapshot = shallowCopy(st)
  local comparer = shallowCopy(st.Comparer)
  local messages = shallowCopy(st.Messages)
  local automation = shallowCopy(st.Automation)
  local debug = type(st.Debug) == "table" and shallowCopy(st.Debug) or st.Debug

  local ok, err = pcall(fn)

  restoreTable(st, snapshot)
  st.Comparer = comparer
  st.Messages = messages
  st.Automation = automation
  st.Debug = debug

  if XIVEquip.Settings and XIVEquip.Settings.Get then
    XIVEquip.Settings:Get()
  end

  if not ok then error(err, 0) end
end

local function requireComparers()
  local M = XIVEquip.Comparers
  expectTruthy(M and M.Get and M.StartPass and M.EndPass, "Comparer core is not available")
  local pawn = M:Get("pawn")
  local ilvl = M:Get("ilvl")
  expectTruthy(pawn, "Pawn comparer is not registered")
  expectTruthy(ilvl, "Item Level comparer is not registered")
  return M, pawn, ilvl
end

addCase("default comparer falls back to item level when Pawn is unusable", function()
  withSavedSettings(function()
    local M, pawn = requireComparers()
    setComparer("default")
    withPatchedTable(pawn, {
      IsAvailable = function() return false end,
      PrePass = function() return false end,
    }, function()
      local cmp, resolution = M:StartPass()
      M:EndPass()
      expectTruthy(cmp, "fallback comparer should resolve")
      expectEqual(resolution.configured_key, "default", "configured key")
      expectEqual(resolution.resolved_key, "ilvl", "resolved key")
      expectTruthy(resolution.fallback_used, "fallback flag")
    end)
  end)
end)

addCase("default comparer uses Pawn when Pawn is usable", function()
  withSavedSettings(function()
    local M, pawn = requireComparers()
    setComparer("default")
    withPatchedTable(pawn, {
      IsAvailable = function() return true end,
      PrePass = function() return true end,
    }, function()
      local cmp, resolution = M:StartPass()
      M:EndPass()
      expectTruthy(cmp, "Pawn comparer should resolve")
      expectEqual(resolution.resolved_key, "pawn", "resolved key")
      expectFalsy(resolution.fallback_used, "fallback flag")
    end)
  end)
end)

addCase("explicit Pawn remains strict when unavailable", function()
  withSavedSettings(function()
    local M, pawn = requireComparers()
    setComparer("pawn")
    withPatchedTable(pawn, {
      IsAvailable = function() return false end,
      PrePass = function() return false end,
    }, function()
      local cmp, resolution = M:StartPass()
      M:EndPass()
      expectFalsy(cmp, "explicit unavailable Pawn should not fall back")
      expectEqual(resolution.configured_key, "pawn", "configured key")
      expectEqual(getComparer(), "pawn", "saved comparer")
    end)
  end)
end)

addCase("/xive use ilvl stores canonical key", function()
  withSavedSettings(function()
    requireComparers()
    SlashCmdList.XIVE("use ilvl")
    expectEqual(getComparer(), "ilvl", "saved comparer")
  end)
end)

addCase("/xive use Item Level accepts display label", function()
  withSavedSettings(function()
    requireComparers()
    SlashCmdList.XIVE("use Item Level")
    expectEqual(getComparer(), "ilvl", "saved comparer")
  end)
end)

addCase("preview setting round-trips through shared settings API", function()
  withSavedSettings(function()
    local S = XIVEquip.Settings
    expectTruthy(S and S.SetMessage and S.GetMessage, "Settings message API is not available")
    S:SetMessage("Preview", false)
    expectEqual(S:GetMessage("Preview"), false, "preview off")
    S:SetMessage("Preview", true)
    expectEqual(S:GetMessage("Preview"), true, "preview on")
  end)
end)

addCase("/xive status completes without error", function()
  withSavedSettings(function()
    expectTruthy(SlashCmdList and SlashCmdList.XIVE, "Slash command is not registered")
    SlashCmdList.XIVE("status")
  end)
end)

addCase("settings migrate to schema version 2", function()
  withSavedSettings(function()
    local st = getSettings()
    expectEqual(st.SchemaVersion, 2, "schema version")
    expectTruthy(st.Comparer and st.Comparer.Selected, "canonical comparer")
    expectEqual(type(st.Debug), "table", "debug shape")
    expectTruthy(st.Automation and st.Automation.SpecEquip ~= nil, "spec automation field")
    expectTruthy(st.Automation and st.Automation.SaveSpecSet ~= nil, "save automation field")
  end)
end)

addCase("/xive auto spec mutates canonical setting", function()
  withSavedSettings(function()
    local S = XIVEquip.Settings
    S:SetAutomation("SpecEquip", false)
    SlashCmdList.XIVE("auto spec on")
    expectEqual(S:GetAutomation("SpecEquip"), true, "spec automation")
  end)
end)

addCase("/xive auto sets mutates canonical setting", function()
  withSavedSettings(function()
    local S = XIVEquip.Settings
    S:SetAutomation("SaveSpecSet", false)
    SlashCmdList.XIVE("auto sets on")
    expectEqual(S:GetAutomation("SaveSpecSet"), true, "save automation")
  end)
end)

function Tests:Run()
  local passed, failed = 0, 0
  printLine("Regression test run started.")

  for _, case in ipairs(cases) do
    local ok, err = pcall(case.fn)
    if ok then
      passed = passed + 1
      printLine("[PASS] " .. case.name)
    else
      failed = failed + 1
      printLine("[FAIL] " .. case.name .. " - " .. tostring(err))
    end
  end

  printLine(string.format("Regression test run complete: %d passed, %d failed.", passed, failed))
  return failed == 0, passed, failed
end

local function itemRecord(link, itemLoc)
  if not link then return nil end
  local itemID = tonumber(link:match("item:(%d+)"))
  local name, _, quality, itemLevel, reqLevel, className, subclassName, _, equipLoc, icon, sellPrice, classID, subclassID, bindType =
      GetItemInfo(link)
  local instantName, _, instantQuality, instantLevel, instantMinLevel, instantClassID, instantSubclassID = nil
  if itemID and GetItemInfoInstant then
    instantName, _, instantQuality, instantLevel, instantMinLevel, instantClassID, instantSubclassID = GetItemInfoInstant(itemID)
  end

  local guid
  if itemLoc and C_Item and C_Item.GetItemGUID then
    local ok, value = pcall(C_Item.GetItemGUID, itemLoc)
    if ok then guid = value end
  end

  local currentIlvl
  if itemLoc and C_Item and C_Item.GetCurrentItemLevel then
    local ok, value = pcall(C_Item.GetCurrentItemLevel, itemLoc)
    if ok then currentIlvl = value end
  end

  return {
    itemID = itemID,
    link = link,
    guid = guid,
    name = name or instantName,
    quality = quality or instantQuality,
    itemLevel = itemLevel or instantLevel,
    currentItemLevel = currentIlvl,
    requiredLevel = reqLevel or instantMinLevel,
    className = className,
    subclassName = subclassName,
    classID = classID or instantClassID,
    subclassID = subclassID or instantSubclassID,
    equipLoc = equipLoc,
    icon = icon,
    sellPrice = sellPrice,
    bindType = bindType,
  }
end

local function equippedLocation(slotID)
  if ItemLocation and ItemLocation.CreateFromEquipmentSlot then
    return ItemLocation:CreateFromEquipmentSlot(slotID)
  end
  return nil
end

local function bagLocation(bag, slot)
  if ItemLocation and ItemLocation.CreateFromBagAndSlot then
    return ItemLocation:CreateFromBagAndSlot(bag, slot)
  end
  return nil
end

function Tests:CaptureFixture()
  local st = getSettings()
  st.TestFixtures = st.TestFixtures or {}

  local className, classFile, classID = UnitClass("player")
  local specIndex = GetSpecialization and GetSpecialization() or nil
  local specID, specName
  if specIndex and GetSpecializationInfo then
    specID, specName = GetSpecializationInfo(specIndex)
  end

  local fixture = {
    capturedAt = now(),
    character = {
      name = UnitName and UnitName("player") or nil,
      realm = GetRealmName and GetRealmName() or nil,
      level = UnitLevel and UnitLevel("player") or nil,
      className = className,
      classFile = classFile,
      classID = classID,
      specIndex = specIndex,
      specID = specID,
      specName = specName,
    },
    equipped = {},
    bags = {},
    pawn = {
      activeScales = {},
    },
  }

  local labels = XIVEquip.Const and XIVEquip.Const.SLOT_LABEL or {}
  local equippedCount = 0
  for slotID = 1, 19 do
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID) or nil
    if link then
      local loc = equippedLocation(slotID)
      local record = itemRecord(link, loc)
      if record then
        record.slotID = slotID
        record.slotName = labels[slotID] or ("Slot " .. tostring(slotID))
        fixture.equipped[slotID] = record
        equippedCount = equippedCount + 1
      end
    end
  end

  if C_Container and C_Container.GetContainerNumSlots then
    for bag = 0, NUM_BAG_SLOTS or 4 do
      local slots = C_Container.GetContainerNumSlots(bag) or 0
      for slot = 1, slots do
        local link = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot) or nil
        if link then
          local loc = bagLocation(bag, slot)
          local record = itemRecord(link, loc)
          if record then
            record.bag = bag
            record.slot = slot
            fixture.bags[#fixture.bags + 1] = record
          end
        end
      end
    end
  end

  if XIVEquip.Pawn and XIVEquip.Pawn.GetActiveScales then
    for _, scale in ipairs(XIVEquip.Pawn.GetActiveScales() or {}) do
      fixture.pawn.activeScales[#fixture.pawn.activeScales + 1] = {
        key = scale.key,
        name = scale.name,
        type = scale.type,
        source = scale.source,
        class = scale.class,
        spec = scale.spec,
      }
    end
  end

  st.TestFixtures.LastCapture = fixture
  printLine(string.format("Fixture captured: %d equipped items, %d bag items.",
    equippedCount, #fixture.bags))
  printLine("Saved to XIVEquip_Settings.TestFixtures.LastCapture.")
  return fixture
end

if Cmd and Cmd.RegisterRoot then
  Cmd.RegisterRoot("test", function()
    Tests:Run()
  end)

  Cmd.RegisterRoot({ "fixture", "capture" }, function()
    Tests:CaptureFixture()
  end)

  Cmd.RegisterRoot({ "fixture", "clear" }, function()
    local st = getSettings()
    st.TestFixtures = nil
    printLine("Captured fixtures cleared.")
  end)

  Cmd.Help(" /xive test                          - run in-game regression checks")
  Cmd.Help(" /xive fixture capture               - capture equipped and bag item fixture data")
  Cmd.Help(" /xive fixture clear                 - remove captured fixture data")
end
