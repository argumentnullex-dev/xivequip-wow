-- Lightweight command-line management for the profile-backed item lists.
-- Add-only by design: the Settings UI's Wishlist/Avoidlist tabs already
-- offer a Remove button per row, which is strictly easier than typing a
-- remove command, so these only ever add (or list with no argument).
local addonName, XIVEquip = ...

local Commands = XIVEquip.Commands
local Profiles = XIVEquip.Profiles and XIVEquip.Profiles.Config
local PREFIX = (XIVEquip.L and XIVEquip.L.AddonPrefix) or "XIVEquip: "

if not (Commands and Commands.RegisterRoot and Profiles) then return end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function parseItemID(value)
  value = tostring(value or "")
  return tonumber(value:match("|Hitem:(%d+)") or value:match("item:(%d+)") or value:match("^(%d+)$"))
end

local function activeProfile()
  local profile, context = Profiles.EnsureCurrent()
  if not profile or not context or not context.specID then
    print(PREFIX .. "Unable to identify your active profile and specialization.")
    return nil
  end
  return profile, context.specID
end

local function listItems(kind)
  local profile, specID = activeProfile()
  if not profile then return end
  local preferences = Profiles.GetSpecPreferences(profile, specID)
  local ids = {}
  for itemID in pairs(preferences[kind] or {}) do ids[#ids + 1] = tonumber(itemID) end
  table.sort(ids)
  if #ids == 0 then
    print(PREFIX .. kind .. " is empty for this specialization.")
    return
  end
  print(PREFIX .. kind .. " for this specialization: " .. table.concat(ids, ", "))
end

local function manageList(kind, setter, rest)
  local value = trim(rest)
  if value == "" or string.lower(value) == "list" then return listItems(kind) end
  local itemID = parseItemID(value)
  if not itemID then
    print(PREFIX .. "Provide an item link or item ID.")
    return
  end
  local profile, specID = activeProfile()
  if not profile then return end
  local ok, reason = setter(profile, specID, itemID, true)
  if not ok then
    print(PREFIX .. "Unable to update " .. kind .. ": " .. tostring(reason or "unknown error"))
    return
  end
  print(PREFIX .. "Item " .. tostring(itemID) .. " added to " .. kind .. " for this specialization.")
end

Commands.RegisterRoot("wish", function(rest)
  manageList("wishlist", Profiles.SetWishlistItem, rest)
end)
Commands.RegisterRoot("avoid", function(rest)
  manageList("avoidlist", Profiles.SetAvoidlistItem, rest)
end)
Commands.Help(" /xive wish <item link|itemID> - add to this spec's wishlist (no argument lists it)")
Commands.Help(" /xive avoid <item link|itemID> - add to this spec's avoidlist (no argument lists it)")
