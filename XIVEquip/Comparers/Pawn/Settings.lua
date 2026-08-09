-- Comparers/Pawn/Settings.lua
-- Compatibility shim. Global/Settings.lua owns the canonical saved-variable schema.
local addon, XIVEquip = ...
XIVEquip = XIVEquip or {}
XIVEquip.Settings = XIVEquip.Settings or {}

if XIVEquip.Settings.Initialize then
  XIVEquip.Settings:Initialize()
end
