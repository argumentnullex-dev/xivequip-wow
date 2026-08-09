-- XIVEquip.lua
local addonName, XIVEquip = ...
local L = XIVEquip.L

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

local status

local function addonVersion()
  local metadata
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    metadata = C_AddOns.GetAddOnMetadata
  elseif GetAddOnMetadata then
    metadata = GetAddOnMetadata
  end
  if not metadata then return nil end

  local ok, version = pcall(metadata, addonName, "Version")
  if ok and version and version ~= "" then return tostring(version) end
  return nil
end

-- message gates
-- [XIVEquip-AUTO] msgLogin: Helper for . module.
local function msgLogin(text)
  if XIVEquip.Settings and XIVEquip.Settings.GetMessage and XIVEquip.Settings:GetMessage("Login") then
    print(L.AddonPrefix .. text)
  end
end

local function msgLoaded(comparerText)
  local version = addonVersion() or "unknown"
  msgLogin(string.format(L.Loaded_Format or "Loaded v%s. Using %s.", version, tostring(comparerText or "unknown comparer")))
end

-- msgError: msg error.
local function msgError(text) print(L.AddonPrefix .. text) end
-- XIVEquip.ShouldShowEquipMsgs: should show equip msgs.
function XIVEquip.ShouldShowEquipMsgs()
  return XIVEquip.Settings and XIVEquip.Settings.GetMessage and XIVEquip.Settings:GetMessage("Equip")
end

-- Callback used in XIVEquip.lua to run inline logic.
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    if XIVEquip.Settings and XIVEquip.Settings.Initialize then
      XIVEquip.Settings:Initialize()
    end
  elseif event == "PLAYER_LOGIN" then
    -- Finalize the policy registry now, not lazily on first use: every
    -- normal addon (including a third party declaring XIVEquip as a
    -- dependency and registering via C_AddOns.GetAddOnLocalTable) has had
    -- the chance to load and call RegisterPolicy by PLAYER_LOGIN. Locking
    -- here closes the registration window -- doc 15.9's "no policy
    -- discovery/resolution/mutation in the hot path" requires the arrays
    -- to already be resolved by the time anything evaluates equipment,
    -- even though nothing evaluates against them yet (Phase 3+ work).
    if XIVEquip.Policies and XIVEquip.Policies.DefaultRegistry and XIVEquip.Policies.Resolver then
      local registry = XIVEquip.Policies.DefaultRegistry
      local ok, resolvedOrErr = pcall(XIVEquip.Policies.Resolver.Finalize, registry:Pending())
      if ok then
        XIVEquip.Policies.Resolved = resolvedOrErr
      else
        print((XIVEquip.L and XIVEquip.L.AddonPrefix or "XIVEquip: ") ..
          "Policy registry finalization failed: " .. tostring(resolvedOrErr))
      end
      registry:Lock()
    end

    if not (XIVEquip.Comparers and XIVEquip.Comparers.Initialize) then
      print((XIVEquip.L and XIVEquip.L.AddonPrefix or "XIVEquip: ") ..
        "Comparer core not loaded (check TOC order / Comparers.lua).")
      return
    end
    local status, resolution = XIVEquip.Comparers:Initialize()
    local active = (resolution and resolution.comparer and resolution.comparer.Label)
        or (XIVEquip.Comparers.GetResolvedName and XIVEquip.Comparers:GetResolvedName())
        or XIVEquip.Comparers:GetActiveName()
    if status == "default:pawn" then
      msgLoaded(L.Loaded_Default_Pawn)
    elseif status == "default:ilvl" then
      msgLoaded(L.Loaded_Default_Ilvl)
    elseif status == "saved:ok" then
      msgLoaded(string.format(L.Loaded_Using_Name, tostring(active)))
    elseif status == "saved:unknown" then
      msgLogin(L.Warn_Unknown)
    elseif status == "saved:unavailable" then
      msgLogin(L.Warn_Unavailable)
    else
      msgLoaded(string.format(L.Loaded_Using_Name, tostring(active or "ilvl")))
    end
  end
end)

-- Called by the UI button
-- [XIVEquip-AUTO] XIVEquip:EquipBestGear: Applies equipment changes (gear/weapons) for the addon.
function XIVEquip:EquipBestGear()
  if not XIVEquip.Gear or not XIVEquip.Gear.EquipBest then
    msgError(L.NoComparer)
    return
  end
  -- Debug helper: when user enabled debug, print active comparer & Pawn tooltip header
  local debugEnabled = XIVEquip.Settings and XIVEquip.Settings.GetDebugEnabled and XIVEquip.Settings:GetDebugEnabled()
  if debugEnabled then
    local act = (XIVEquip.Comparers and XIVEquip.Comparers:GetActiveName()) or "nil"
    print((L.AddonPrefix or "XIVEquip: ") .. "Debug: active comparer=" .. tostring(act))
    local cmp = XIVEquip.Comparers and XIVEquip.Comparers:GetActive()
    if cmp and type(cmp.GetActiveTooltipHeader) == "function" then
      print((L.AddonPrefix or "XIVEquip: ") .. "Debug: " .. tostring(cmp.GetActiveTooltipHeader()))
    end
  end
  XIVEquip.Gear:EquipBest()
end
