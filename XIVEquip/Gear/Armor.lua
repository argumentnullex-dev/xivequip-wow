-- Armor.lua
local addonName, XIVEquip = ...
local Core = XIVEquip.Gear_Core

local A = {}
XIVEquip.Armor = A

local playerArmorSubclass = Core.playerArmorSubclass
local tryChooseAppend     = Core.tryChooseAppend

-- PlanBest returns (changes, pending, plan); accepts shared `used` table
-- [XIVEquip-AUTO] A:PlanBest: Helper for Gear module.
function A:PlanBest(cmp, opts, used)
  opts = opts or {}
  used = used or {}

  local expectedArmor = playerArmorSubclass()
  local plan, changes = {}, {}
  local hadPending = false

  -- Armor order (no weapons/cloak/jewelry here)
  for _, slotID in ipairs({ 1,3,5,6,7,8,9,10 }) do
    local _, _, _, pending = tryChooseAppend(plan, changes, slotID, cmp, expectedArmor, used)
    hadPending = hadPending or pending == true
  end

  return changes, hadPending, plan
end
