local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function join(...)
  return table.concat({ ... }, sep)
end

local function loadAddonFile(rel, addon)
  local chunk = assert(loadfile(join(root, "XIVEquip", rel)))
  chunk("XIVEquip", addon)
end

local function itemLink(id)
  return "|Hitem:" .. tostring(id) .. "::::::::::::|h[item-" .. tostring(id) .. "]|h"
end

local function containsMessage(messages, text)
  for _, msg in ipairs(messages or {}) do
    if tostring(msg):find(text, 1, true) then return true end
  end
  return false
end

local function newHarness(config)
  config = config or {}
  local timers = {}
  local printed = {}
  local logs = {}
  local equipped = config.equipped or {}
  local setIDs = {}
  local saves = {}
  local creates = {}
  local ignores = {}
  local unignores = {}
  local uses = {}
  local iconMods = {}
  local pickups = {}
  local backpackMoves = 0
  local passStarts, passEnds = 0, 0
  for name, setID in pairs(config.existingSets or {}) do
    setIDs[name] = setID
  end

  local addon = {
    L = {
      AddonPrefix = "XIVEquip: ",
      NoUpgrades = "No upgrades found.",
      CannotCombat = "Cannot equip while in combat.",
      ReplacedWith = "Replaced %s with %s.",
      SpecAuto_Saved = "Saved equipment set '%s'.",
    },
    Log = {
      Debug = function(msg) logs[#logs + 1] = tostring(msg) end,
      Info = function(msg) logs[#logs + 1] = tostring(msg) end,
      Warn = function(msg) logs[#logs + 1] = tostring(msg) end,
      Error = function(msg) logs[#logs + 1] = tostring(msg) end,
      Debugf = function(_, ...) logs[#logs + 1] = table.concat({ ... }, " ") end,
    },
    Comparers = {
      StartPass = function()
        passStarts = passStarts + 1
        return {}
      end,
      EndPass = function()
        passEnds = passEnds + 1
      end,
    },
    Settings = {
      GetMessage = function(_, key)
        if key == "Equip" then return config.showEquip ~= false end
        return true
      end,
      GetAutomation = function(_, key)
        if key == "SaveSpecSet" then return config.autoSave == true end
        return false
      end,
      GetPlannerMode = function()
        return config.plannerMode or "legacy"
      end,
    },
  }

  _G.print = function(text) table.insert(printed, tostring(text)) end
  _G.C_Timer = {
    After = function(_, fn)
      table.insert(timers, fn)
    end,
  }
  _G.InCombatLockdown = function()
    if type(config.combat) == "function" then return config.combat() == true end
    return config.combat == true
  end
  _G.GetInventoryItemLink = function(_, slot)
    return equipped[slot]
  end
  _G.IsInventoryItemLocked = function(slot)
    if type(config.locked) == "function" then return config.locked(slot) == true end
    return config.locked == true
  end
  _G.GetItemInfo = function(link)
    local bindType = config.bindTypes and config.bindTypes[link] or nil
    return "item", link, nil, 1, 1, nil, nil, nil, nil, nil, nil, nil, nil, bindType
  end
  _G.GetDetailedItemLevelInfo = function() return 1 end
  _G.GetItemInfoInstant = function() return nil end
  _G.UnitClass = function() return "Player", "WARRIOR" end
  _G.UnitLevel = function() return 80 end
  _G.ClearCursor = function() config.cursorCleared = true end
  _G.PickupInventoryItem = function(slot)
    pickups[#pickups + 1] = slot
    config.cursorSlot = slot
  end
  _G.PutItemInBackpack = function()
    backpackMoves = backpackMoves + 1
    if config.cursorSlot then
      equipped[config.cursorSlot] = nil
      config.cursorSlot = nil
    end
  end
  _G.GetSpecialization = function() return 1 end
  _G.GetSpecializationInfo = function() return 1, "Arms", nil, 123 end
  _G.C_Item = {
    DoesItemExist = function() return false end,
    IsBound = function(loc)
      return loc and loc.bound == true
    end,
  }
  _G.ItemLocation = {
    CreateFromEquipmentSlot = function(_, slot)
      return { equipmentSlot = slot }
    end,
  }
  _G.C_EquipmentSet = {
    GetEquipmentSetID = function(name)
      return setIDs[name]
    end,
    CreateEquipmentSet = function(name)
      creates[#creates + 1] = name
      setIDs[name] = setIDs[name] or (#creates + 100)
    end,
    SaveEquipmentSet = function(setID)
      saves[#saves + 1] = setID
    end,
    UseEquipmentSet = function(setID)
      uses[#uses + 1] = setID
      if config.useEquipmentSet then return config.useEquipmentSet(setID, equipped) end
      for _, slotID in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }) do
        equipped[slotID] = nil
      end
      return true
    end,
    IgnoreSlotForSave = function(slotID)
      ignores[#ignores + 1] = slotID
    end,
    UnignoreSlotForSave = function(slotID)
      unignores[#unignores + 1] = slotID
    end,
    ModifyEquipmentSetIcon = function(setID, icon)
      iconMods[#iconMods + 1] = { setID = setID, icon = icon }
    end,
  }

  loadAddonFile("Global" .. sep .. "Constants.lua", addon)
  loadAddonFile("Core" .. sep .. "GearCore.lua", addon)

  addon.Gear_Core.equipByBasics = config.equipByBasics or function(pick)
    equipped[pick.targetSlot] = pick.link
    return pick.link
  end

  loadAddonFile("Gear" .. sep .. "Interface.lua", addon)
  -- Default stub is idempotent: once `equipped` matches a plan entry, that
  -- entry drops out. Gear:ValidateNakedEquip now re-plans after equipping to
  -- confirm nothing further is recommended (see Gear/Interface.lua's
  -- checkFullyOptimal), so a static "always return the full plan" stub would
  -- incorrectly look like there's always more to do.
  if not config.keepPlanBest then
    addon.Gear.PlanBest = config.planBest or function()
      local remaining = {}
      for _, pick in ipairs(config.plan or {}) do
        if equipped[pick.targetSlot] ~= pick.link then
          table.insert(remaining, pick)
        end
      end
      return {}, false, remaining
    end
  end

  local function runTimers(maxSteps)
    maxSteps = maxSteps or 100
    local steps = 0
    while #timers > 0 do
      steps = steps + 1
      if steps > maxSteps then error("timer queue did not settle") end
      local fn = table.remove(timers, 1)
      fn()
    end
  end

  return addon, {
    runTimers = runTimers,
    equipped = equipped,
    printed = printed,
    logs = logs,
    saves = saves,
    creates = creates,
    ignores = ignores,
    unignores = unignores,
    uses = uses,
    iconMods = iconMods,
    pickups = pickups,
    backpackMoves = function() return backpackMoves end,
    passStarts = function() return passStarts end,
    passEnds = function() return passEnds end,
  }
end

test("empty plan ends the comparer pass once and does not save", function()
  local addon, raw = newHarness({ plan = {}, autoSave = true })

  local result = addon.Gear:EquipBest()

  A.equal(result.completed, true)
  A.equal(result.planned_count, 0)
  A.equal(raw.passStarts(), 1)
  A.equal(raw.passEnds(), 1)
  A.equal(#raw.saves, 0)
  A.truthy(containsMessage(raw.printed, "No upgrades found."))
end)

test("verified equip success updates result and saves when enabled", function()
  local newLink = itemLink(201)
  local completedResult
  local addon, raw = newHarness({
    autoSave = true,
    equipped = { [1] = itemLink(101) },
    plan = { { targetSlot = 1, link = newLink } },
  })

  local result = addon.Gear:EquipBest({
    saveDelay = 0,
    onComplete = function(r)
      completedResult = {
        set_saved = r.set_saved,
        save_scheduled = r.save_scheduled,
      }
    end,
  })
  A.equal(result.save_scheduled, false)
  A.equal(result.set_saved, false)
  raw.runTimers()

  A.equal(raw.equipped[1], newLink)
  A.equal(result.succeeded, 1)
  A.equal(result.failed, 0)
  A.equal(result.save_scheduled, true)
  A.equal(result.set_saved, true)
  A.equal(completedResult.set_saved, false)
  A.equal(completedResult.save_scheduled, true)
  A.equal(#raw.saves, 1)
  A.equal(raw.ignores[1], 4)
  A.equal(raw.ignores[2], 19)
  A.equal(raw.unignores[1], 4)
  A.equal(raw.unignores[2], 19)
  A.equal(raw.passEnds(), 1)
end)

test("explicit native planner path executes through the existing equip runner without a legacy comparer pass", function()
  local newLink = itemLink(301)
  local addon, raw = newHarness({
    keepPlanBest = true,
    equipped = { [1] = itemLink(101) },
    plan = {},
  })
  local nativeCalled = false
  addon.Gear.PlanBestNative = function()
    nativeCalled = true
    return {
      {
        slot = 1,
        oldLink = itemLink(101),
        newLink = newLink,
      },
    }, false, {
      { targetSlot = 1, link = newLink },
    }, { score = 1 }
  end

  local result = addon.Gear:EquipBest({ planner = "native" })
  raw.runTimers()

  A.truthy(nativeCalled, "explicit native planner path should call PlanBestNative")
  A.equal(raw.passStarts(), 0)
  A.equal(raw.passEnds(), 0)
  A.equal(result.succeeded, 1)
  A.equal(raw.equipped[1], newLink)
end)

test("planner mode native routes normal equip through the native planner", function()
  local newLink = itemLink(303)
  local addon, raw = newHarness({
    keepPlanBest = true,
    plannerMode = "native",
    equipped = { [1] = itemLink(101) },
  })
  local nativeCalled = false
  addon.Gear.PlanBestNative = function()
    nativeCalled = true
    return {
      { slot = 1, oldLink = itemLink(101), newLink = newLink },
    }, false, {
      { targetSlot = 1, link = newLink },
    }, { score = 1 }
  end

  local result = addon.Gear:EquipBest()
  raw.runTimers()

  A.truthy(nativeCalled, "planner mode native should call PlanBestNative")
  A.equal(raw.passStarts(), 0)
  A.equal(raw.passEnds(), 0)
  A.equal(result.succeeded, 1)
  A.equal(raw.equipped[1], newLink)
end)

test("explicit legacy planner overrides native planner mode", function()
  local legacyLink = itemLink(304)
  local addon, raw = newHarness({
    plannerMode = "native",
    equipped = { [1] = itemLink(101) },
    plan = { { targetSlot = 1, link = legacyLink } },
  })
  addon.Gear.PlanBestNative = function()
    error("native planner should not be called")
  end

  local result = addon.Gear:EquipBest({ planner = "legacy" })
  raw.runTimers()

  A.equal(raw.passStarts(), 1)
  A.equal(raw.passEnds(), 1)
  A.equal(result.succeeded, 1)
  A.equal(raw.equipped[1], legacyLink)
end)

test("explicit unequip plan step clears the target slot through the verified executor", function()
  local oldOffhand = itemLink(317)
  local addon, raw = newHarness({
    equipped = { [17] = oldOffhand },
    plan = { { action = "unequip", targetSlot = 17 } },
  })

  local result = addon.Gear:EquipBest()
  raw.runTimers()

  A.equal(result.succeeded, 1)
  A.equal(result.failed, 0)
  A.equal(raw.pickups[1], 17)
  A.equal(raw.backpackMoves(), 1)
  A.equal(raw.equipped[17], nil)
end)

test("native planner failure aborts without equipping or invoking legacy planners", function()
  local newLink = itemLink(302)
  local oldLink = itemLink(101)
  local legacyCalled = false
  local addon, raw = newHarness({
    keepPlanBest = true,
    equipped = { [1] = oldLink },
  })
  addon.Armor = {
    PlanBest = function()
      legacyCalled = true
      return {}, false, {
        { targetSlot = 1, link = newLink },
      }
    end,
  }
  addon.Jewelry = { PlanBest = function() return {}, false, {} end }
  addon.Weapons = { PlanBest = function() return {}, false, {} end }
  addon.Gear.PlanBestNative = function()
    error("native planner failed")
  end

  local result = addon.Gear:EquipBest({ planner = "native" })
  raw.runTimers()

  A.equal(legacyCalled, false, "native failure must not invoke legacy planners")
  A.equal(raw.passStarts(), 0)
  A.equal(raw.passEnds(), 0)
  A.equal(result.completed, true)
  A.equal(result.succeeded, 0)
  A.equal(result.failed, 1)
  A.equal(raw.equipped[1], oldLink)
  A.truthy(containsMessage(raw.printed, "Native 2.0 planner failed; no gear was equipped."))
  A.truthy(containsMessage(raw.logs, "native planner failed"))
end)

test("native planner failure prints even when normal equip messages are disabled", function()
  local addon, raw = newHarness({
    keepPlanBest = true,
    showEquip = false,
    equipped = { [1] = itemLink(101) },
  })
  addon.Gear.PlanBestNative = function()
    error("native planner failed")
  end

  local result = addon.Gear:EquipBest({ planner = "native" })
  raw.runTimers()

  A.equal(result.completed, true)
  A.equal(result.failed, 1)
  A.truthy(containsMessage(raw.printed, "Native 2.0 planner failed; no gear was equipped."))
end)

test("legacy StartPass failure does not call EndPass", function()
  local addon, raw = newHarness({ keepPlanBest = true })
  addon.Comparers.StartPass = function()
    error("start failed")
  end

  local ok = pcall(function() addon.Gear:EquipBest({ planner = "legacy" }) end)

  A.falsy(ok)
  A.equal(raw.passEnds(), 0)
end)

test("legacy planning exception after comparer acquisition releases exactly once", function()
  local addon, raw = newHarness({ keepPlanBest = true })
  addon.Gear.PlanBest = function()
    error("planner exploded")
  end

  local ok = pcall(function() addon.Gear:EquipBest({ planner = "legacy" }) end)

  A.falsy(ok)
  A.equal(raw.passStarts(), 1)
  A.equal(raw.passEnds(), 1)
end)

test("ordinary auto-save does not overwrite an existing set's icon", function()
  local newLink = itemLink(201)
  local addon, raw = newHarness({
    autoSave = true,
    existingSets = { ["Arms.xive"] = 55 },
    equipped = { [1] = itemLink(101) },
    plan = { { targetSlot = 1, link = newLink } },
  })

  addon.Gear:EquipBest({ saveDelay = 0 })
  raw.runTimers()

  A.equal(#raw.saves, 1)
  A.equal(#raw.creates, 0, "an already-existing set should not be recreated")
  A.equal(#raw.iconMods, 0, "ordinary auto-save must not touch the existing set's icon")
end)

test("explicit spec set saves exclude shirt and tabard", function()
  local addon, raw = newHarness()

  addon.Gear:SaveEquippedToSpecSet()

  A.equal(raw.creates[1], "Arms.xive")
  A.equal(#raw.saves, 1)
  A.equal(raw.ignores[1], 4)
  A.equal(raw.ignores[2], 19)
  A.equal(raw.unignores[1], 4)
  A.equal(raw.unignores[2], 19)
end)

test("validation backs up, equips Birthday Suit, equips plan, and reports missing slots", function()
  local head = itemLink(101)
  local shirt = itemLink(104)
  local tabard = itemLink(119)
  local ring = itemLink(211)
  local addon, raw = newHarness({
    existingSets = { ["Birthday Suit"] = 42 },
    equipped = {
      [1] = head,
      [4] = shirt,
      [19] = tabard,
    },
    plan = {
      { targetSlot = 1, link = head },
      { targetSlot = 11, link = ring },
    },
  })

  local state = addon.Gear:ValidateNakedEquip({ nakedDelay = 0, validationDelay = 0 })
  raw.runTimers()
  local result = state.result

  A.equal(raw.creates[1], "backup.xive")
  A.equal(raw.ignores[1], 4)
  A.equal(raw.ignores[2], 19)
  A.equal(raw.uses[1], 42)
  A.equal(raw.backpackMoves(), 0)
  A.equal(raw.equipped[4], shirt)
  A.equal(raw.equipped[19], tabard)
  A.equal(raw.equipped[1], head)
  A.equal(raw.equipped[11], ring)
  A.equal(result.succeeded, 2)
  A.equal(#raw.saves, 1)
  A.truthy(containsMessage(raw.printed, "Validation failed: missing"))
  A.truthy(containsMessage(raw.printed, "Ring 2"))
  A.truthy(containsMessage(raw.printed, "Trinket 1"))
end)

test("validation saves the spec set after expected slots are filled", function()
  local plan = {}
  local equipped = {
    [4] = itemLink(104),
    [19] = itemLink(119),
  }
  for _, slotID in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) do
    table.insert(plan, { targetSlot = slotID, link = itemLink(300 + slotID) })
  end

  local addon, raw = newHarness({
    existingSets = { ["Birthday Suit"] = 42 },
    equipped = equipped,
    plan = plan,
  })

  local state = addon.Gear:ValidateNakedEquip({ nakedDelay = 0, validationDelay = 0 })
  raw.runTimers()

  A.truthy(state.result, "validation should run equip plan")
  A.equal(raw.creates[1], "backup.xive")
  A.equal(raw.creates[2], "Arms.xive")
  A.equal(#raw.saves, 2)
  A.equal(raw.ignores[1], 4)
  A.equal(raw.ignores[2], 19)
  A.equal(raw.ignores[3], 4)
  A.equal(raw.ignores[4], 19)
  A.truthy(containsMessage(raw.printed, "Validation passed: expected slots are equipped."))
  A.truthy(containsMessage(raw.printed, "Saved equipment set 'Arms.xive'."))
end)

test("validation fails and does not save when the post-equip re-plan still recommends a change", function()
  local plan = {}
  local equipped = {
    [4] = itemLink(104),
    [19] = itemLink(119),
  }
  for _, slotID in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) do
    table.insert(plan, { targetSlot = slotID, link = itemLink(300 + slotID) })
  end

  local calls = 0
  local addon, raw = newHarness({
    existingSets = { ["Birthday Suit"] = 42 },
    equipped = equipped,
    planBest = function()
      calls = calls + 1
      if calls == 1 then return {}, false, plan end
      -- The re-plan after equipping: pretend a better head item is still
      -- available, so the equipped result isn't actually optimal.
      return {}, false, { { targetSlot = 1, link = itemLink(999) } }
    end,
  })

  addon.Gear:ValidateNakedEquip({ nakedDelay = 0, validationDelay = 0 })
  raw.runTimers()

  A.equal(calls, 2)
  A.equal(raw.passStarts(), 2)
  A.equal(raw.passEnds(), 2)
  A.equal(raw.creates[1], "backup.xive")
  A.falsy(raw.creates[2], "spec set should not be created when validation fails")
  A.equal(#raw.saves, 1, "only backup.xive should be saved")
  A.truthy(containsMessage(raw.printed, "Validation failed: equipped gear is not the top recommendation"))
  A.truthy(containsMessage(raw.printed, "Head"))
  A.falsy(containsMessage(raw.printed, "Validation passed"))
end)

test("validation fails and does not save when the post-equip re-plan is still pending", function()
  local plan = {}
  local equipped = {
    [4] = itemLink(104),
    [19] = itemLink(119),
  }
  for _, slotID in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) do
    table.insert(plan, { targetSlot = slotID, link = itemLink(300 + slotID) })
  end

  local calls = 0
  local addon, raw = newHarness({
    existingSets = { ["Birthday Suit"] = 42 },
    equipped = equipped,
    planBest = function()
      calls = calls + 1
      if calls == 1 then return {}, false, plan end
      return {}, true, {}
    end,
  })

  addon.Gear:ValidateNakedEquip({ nakedDelay = 0, validationDelay = 0 })
  raw.runTimers()

  A.equal(calls, 2)
  A.equal(raw.passStarts(), 2)
  A.equal(raw.passEnds(), 2)
  A.equal(raw.creates[1], "backup.xive")
  A.falsy(raw.creates[2], "spec set should not be created while optimality is unconfirmed")
  A.equal(#raw.saves, 1, "only backup.xive should be saved")
  A.truthy(containsMessage(raw.printed, "Validation failed: item data is still loading"))
  A.falsy(containsMessage(raw.printed, "Validation passed"))
end)

test("native validation failure is not treated as fully optimal and does not save", function()
  local plan = {}
  local equipped = {
    [4] = itemLink(104),
    [19] = itemLink(119),
  }
  for _, slotID in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) do
    table.insert(plan, { targetSlot = slotID, link = itemLink(500 + slotID) })
  end

  local calls = 0
  local addon, raw = newHarness({
    keepPlanBest = true,
    plannerMode = "native",
    existingSets = { ["Birthday Suit"] = 42 },
    equipped = equipped,
  })
  addon.Gear.PlanBestNative = function()
    calls = calls + 1
    if calls == 1 then return {}, false, plan, { score = 1 } end
    error("native validation failed")
  end

  addon.Gear:ValidateNakedEquip({ nakedDelay = 0, validationDelay = 0 })
  raw.runTimers()

  A.equal(calls, 2)
  A.equal(raw.creates[1], "backup.xive")
  A.falsy(raw.creates[2], "spec set should not be created when native validation fails")
  A.equal(#raw.saves, 1, "only backup.xive should be saved")
  A.truthy(containsMessage(raw.printed, "Validation failed: planner failed during post-equip verification"))
  A.falsy(containsMessage(raw.printed, "Validation passed"))
end)

test("validation aborts when Birthday Suit set is missing", function()
  local head = itemLink(101)
  local addon, raw = newHarness({
    equipped = { [1] = head },
    plan = { { targetSlot = 1, link = itemLink(201) } },
  })

  local state = addon.Gear:ValidateNakedEquip({ nakedDelay = 0, validationDelay = 0 })
  raw.runTimers()

  A.falsy(state)
  A.equal(raw.creates[1], "backup.xive")
  A.equal(#raw.uses, 0)
  A.equal(raw.equipped[1], head)
  A.equal(raw.passStarts(), 0)
  A.truthy(containsMessage(raw.printed, "could not equip Birthday Suit"))
end)

test("auto-save disabled never saves after verified success", function()
  local addon, raw = newHarness({
    autoSave = false,
    equipped = { [1] = itemLink(101) },
    plan = { { targetSlot = 1, link = itemLink(201) } },
  })

  local result = addon.Gear:EquipBest()
  raw.runTimers()

  A.equal(result.succeeded, 1)
  A.equal(result.set_saved, false)
  A.equal(#raw.saves, 0)
end)

test("verified partial success still saves the resulting set when auto-save is enabled", function()
  local firstLink = itemLink(201)
  local secondLink = itemLink(202)
  local equipped = { [1] = itemLink(101), [3] = itemLink(103) }
  local addon, raw = newHarness({
    autoSave = true,
    equipped = equipped,
    plan = {
      { targetSlot = 1, link = firstLink },
      { targetSlot = 3, link = secondLink },
    },
    equipByBasics = function(pick)
      if pick.targetSlot == 1 then
        equipped[pick.targetSlot] = pick.link
      end
    end,
  })

  local result = addon.Gear:EquipBest({ saveDelay = 0 })
  raw.runTimers()

  A.equal(result.succeeded, 1)
  A.equal(result.failed, 1)
  A.equal(result.save_scheduled, true)
  A.equal(result.set_saved, true)
  A.equal(#raw.saves, 1)
end)

test("equip exception records failure and still ends the pass once", function()
  local addon, raw = newHarness({
    autoSave = true,
    equipped = { [1] = itemLink(101) },
    plan = { { targetSlot = 1, link = itemLink(201) } },
    equipByBasics = function()
      error("protected call failed")
    end,
  })

  local result = addon.Gear:EquipBest()
  raw.runTimers()

  A.equal(result.failed, 1)
  A.equal(result.succeeded, 0)
  A.equal(result.set_saved, false)
  A.equal(#raw.saves, 0)
  A.equal(raw.passEnds(), 1)
end)

test("permanently locked slot times out without hanging", function()
  local addon, raw = newHarness({
    locked = true,
    equipped = { [1] = itemLink(101) },
    plan = { { targetSlot = 1, link = itemLink(201) } },
  })

  local result = addon.Gear:EquipBest({ maxLockRetries = 2 })
  raw.runTimers()

  A.equal(result.timed_out, 1)
  A.equal(result.succeeded, 0)
  A.equal(raw.passEnds(), 1)
end)

test("unbound BoE is reported as manual-required and does not save", function()
  local boe = itemLink(201)
  local addon, raw = newHarness({
    autoSave = true,
    equipped = { [1] = itemLink(101) },
    bindTypes = { [boe] = 2 },
    plan = { { targetSlot = 1, link = boe, loc = { bound = false } } },
    equipByBasics = function() end,
  })

  local result = addon.Gear:EquipBest()
  raw.runTimers()

  A.equal(result.manual_required, 1)
  A.equal(result.succeeded, 0)
  A.equal(result.set_saved, false)
  A.equal(#raw.saves, 0)
  A.truthy(containsMessage(raw.printed, "Bind on Equip"))
end)

test("pending item data retries and later applies the available plan", function()
  local calls = 0
  local completed = 0
  local link = itemLink(201)
  local addon, raw = newHarness({
    equipped = { [1] = itemLink(101) },
    planBest = function()
      calls = calls + 1
      if calls == 1 then return {}, true, {} end
      return {}, false, { { targetSlot = 1, link = link } }
    end,
  })

  local first = addon.Gear:EquipBest({
    retryDelay = 0,
    maxDataRetries = 1,
    onComplete = function() completed = completed + 1 end,
  })
  raw.runTimers()
  local final = addon.Gear:GetLastEquipResult()

  A.equal(first.pending_data, true)
  A.equal(first.completed, false)
  A.equal(calls, 2)
  A.equal(completed, 1)
  A.equal(final.succeeded, 1)
  A.equal(raw.equipped[1], link)
  A.equal(raw.passStarts(), 2)
  A.equal(raw.passEnds(), 2)
  A.falsy(containsMessage(raw.printed, "No upgrades found."))
end)

test("combat during locked-slot wait skips the plan before protected equip", function()
  local combat = false
  local lockChecks = 0
  local equipAttempts = 0
  local addon, raw = newHarness({
    combat = function() return combat end,
    equipped = { [1] = itemLink(101) },
    locked = function()
      lockChecks = lockChecks + 1
      if lockChecks == 1 then
        combat = true
        return true
      end
      return false
    end,
    plan = { { targetSlot = 1, link = itemLink(201) } },
    equipByBasics = function()
      equipAttempts = equipAttempts + 1
    end,
  })

  local result = addon.Gear:EquipBest({ maxLockRetries = 3 })
  raw.runTimers()

  A.equal(equipAttempts, 0)
  A.equal(result.skipped, 1)
  A.equal(result.failed, 0)
  A.equal(raw.passEnds(), 1)
end)

test("pending item data reaches a bounded timeout", function()
  local calls = 0
  local addon, raw = newHarness({
    planBest = function()
      calls = calls + 1
      return {}, true, {}
    end,
  })

  local result = addon.Gear:EquipBest({ maxDataRetries = 0 })

  A.equal(calls, 1)
  A.equal(result.pending_data, true)
  A.equal(result.timed_out, 1)
  A.equal(result.completed, true)
  A.equal(raw.passEnds(), 1)
end)

test("combat during execution skips remaining steps and prevents save", function()
  local combat = false
  local firstLink = itemLink(201)
  local secondLink = itemLink(202)
  local equipped = { [1] = itemLink(101), [3] = itemLink(103) }
  local addon, raw = newHarness({
    autoSave = true,
    combat = function() return combat end,
    equipped = equipped,
    plan = {
      { targetSlot = 1, link = firstLink },
      { targetSlot = 3, link = secondLink },
    },
    equipByBasics = function(pick)
      equipped[pick.targetSlot] = pick.link
      combat = true
    end,
  })

  local result = addon.Gear:EquipBest()
  raw.runTimers()

  A.equal(result.succeeded, 1)
  A.equal(result.skipped, 1)
  A.equal(result.set_saved, false)
  A.equal(#raw.saves, 0)
end)

return tests
