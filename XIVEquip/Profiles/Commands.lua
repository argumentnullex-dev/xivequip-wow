-- Lightweight command-line management for the profile-backed item lists.
-- The Settings UI offers the same storage through browsable Wishlist and
-- Avoidlist pages; these commands remain useful for macros and quick edits.
local addonName, XIVEquip = ...

local Commands = XIVEquip.Commands
local Profiles = XIVEquip.Profiles and XIVEquip.Profiles.Config
local PREFIX = (XIVEquip.L and XIVEquip.L.AddonPrefix) or "XIVEquip: "

if not (Commands and Commands.RegisterRoot and Profiles) then return end

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
  local action, value = tostring(rest or ""):match("^%s*(%S+)%s*(.-)%s*$")
  action = string.lower(tostring(action or ""))
  if action == "list" or action == "" then return listItems(kind) end
  if action ~= "add" and action ~= "remove" then
    print(PREFIX .. "Usage: /xive " .. (kind == "wishlist" and "wish" or "avoid")
      .. " <add|remove> <item link|itemID>")
    return
  end
  local itemID = parseItemID(value)
  if not itemID then
    print(PREFIX .. "Provide an item link or item ID.")
    return
  end
  local profile, specID = activeProfile()
  if not profile then return end
  local ok, reason = setter(profile, specID, itemID, action == "add")
  if not ok then
    print(PREFIX .. "Unable to update " .. kind .. ": " .. tostring(reason or "unknown error"))
    return
  end
  print(PREFIX .. "Item " .. tostring(itemID) .. (action == "add" and " added to " or " removed from ")
    .. kind .. " for this specialization.")
end

Commands.RegisterRoot("wish", function(rest)
  manageList("wishlist", Profiles.SetWishlistItem, rest)
end)
Commands.RegisterRoot("avoid", function(rest)
  manageList("avoidlist", Profiles.SetAvoidlistItem, rest)
end)
Commands.Help(" /xive wish <add|remove> <item link|itemID> - manage this spec's wishlist")
Commands.Help(" /xive avoid <add|remove> <item link|itemID> - manage this spec's avoidlist")
