-- Localization.lua
local addonName, XIVEquip = ...
XIVEquip = XIVEquip or {}
XIVEquip.L = XIVEquip.L or {}
local L = XIVEquip.L

-- General
L.AddonPrefix            = "|cff33ff99XIVEquip:|r "
L.ButtonTooltip          = "Equip Recommended Gear"
L.CannotCombat           = "Cannot equip while in combat."
L.NoComparer             = "No comparer available."
L.NoUpgrades             = "No upgrades found."
L.ReplacedWith           = "Replaced %s with %s."

-- Startup / status messages
L.Loaded_Format          = "Loaded v%s. Using %s."
L.Loaded_Default_Pawn    = "Default comparer: Pawn"
L.Loaded_Default_Ilvl    = "Default comparer: ilvl"
L.Loaded_Using_Name      = "%s comparer"
L.Warn_Unknown           = "Warning: selected comparer not recognized. Fell back to default."
L.Warn_Unavailable       = "Warning: selected comparer is unavailable. Fell back to default."

-- Settings: main panel
L.Settings_Title         = "XIVEquip"
L.Settings_Desc          = "FFXIV-style 'Equip Recommended Gear' using Pawn when available."
L.Settings_Default       = "Default (Pawn -> ilvl)"
L.Settings_ActiveLabel   = "Active comparer"
L.Settings_LoginMsgs     = "Show login/startup messages"
L.Settings_EquipMsgs     = "Show equip/change messages"
L.Settings_License       = "Based on the 'Equip Recommended Gear' feature in FFXIV. © Code-Ninja. MIT-style license."

-- Auto-spec / equipment set
L.Settings_AutoSpecHeader  = "Auto-save target per spec"
L.Settings_AutoSpecEquip   = "Auto-equip on spec change"
L.Settings_AutoSpecSaveSet = "Auto-save spec equipment set after equip"
L.Settings_AutoSpecRowFmt  = "%s:"
L.Settings_AutoSpecAutoFmt = "Auto (%s.xiv)"
L.SpecAuto_NoEM            = "Cannot save equipment set: Equipment Manager API not available."
L.SpecAuto_Saved           = "Saved equipment set '%s'."

-- Weapons UI (modes / bias)
L.Settings_WeaponModeLabel   = "Weapon combo mode"
L.Settings_WeaponMode_Auto   = "Auto (all legal combos)"
L.Settings_WeaponMode_2H     = "Only 2H"
L.Settings_WeaponMode_Dual1H = "Only dual 1H"
L.Settings_WeaponMode_Dual2H = "Only dual 2H (Titan's Grip)"
L.Settings_WeaponMode_MHShield  = "Only 1H + Shield"
L.Settings_WeaponMode_MHOffhand = "Only 1H + Off-hand"

L.Settings_WeaponBiasLabel   = "Spec bias (Fury/Frost)"
L.Settings_WeaponBias_Auto   = "Auto by talents (Fury/Frost)"
L.Settings_WeaponBias_Pref2H = "Prefer 2H on ties"
L.Settings_WeaponBias_PrefDW = "Prefer Dual-wield on ties"
L.Settings_WeaponBias_Pref1H = "Prefer 1H + Shield/Off-hand on ties"
L.Settings_WeaponBias_None   = "No preference"

-- Pawn comparer hints
L.Pawn_NoActiveScale = "Pawn couldn’t provide a score; enable a scale in Pawn or set one in XIVEquip settings."

-- Pawn settings panel (strings also have sensible fallbacks in the code)
L.Settings_PawnDesc         = "Choose which Pawn scale XIVEquip should use. You can set a global default and per-spec overrides."
L.Settings_PawnDefaultLabel = "Default (fallback) Pawn scale name"
L.Settings_PawnPerSpecHdr   = "Per-spec overrides"
L.Settings_PawnUseSpec      = "Use spec name"
L.Settings_PawnUseClass     = "Use Class: Spec"
