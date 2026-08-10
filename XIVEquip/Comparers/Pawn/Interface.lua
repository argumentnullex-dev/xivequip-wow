-- Comparers/Pawn/Interface.lua
-- Clean, focused interface between XIVEquip and Pawn scales
local addonName, XIVEquip = ...
XIVEquip = XIVEquip or {}
XIVEquip.Pawn = XIVEquip.Pawn or {}

local Pawn = XIVEquip.Pawn

-- Opt-in debug: enable through XIVEquip.Settings or the mirrored XIVEquip_Debug global.
local function _debugEnabled()
    return _G.XIVEquip_Debug == true
end

-- logDebug: Comparer integration: log debug.
local function logDebug(fmt, ...)
    if not _debugEnabled() then return end
    if XIVEquip and XIVEquip.Log and XIVEquip.Log.Debugf then
        XIVEquip.Log.Debugf("force", fmt, ...)
    else
        local ok, msg = pcall(string.format, fmt, ...)
        if ok then print((XIVEquip and XIVEquip.L and XIVEquip.L.AddonPrefix or "XIVEquip: ") .. msg) end
    end
end

-- Small helpers: safe access to Pawn saved scales
local function readAllSVScalesFromPawn()
    local Common = rawget(_G, "PawnCommon")
    if type(Common) ~= "table" or type(Common.Scales) ~= "table" then return {} end
    return Common.Scales
end

-- Character key building & visibility checker
-- [XIVEquip-AUTO] currentCharPieces: Helper for Pawn module.
local function currentCharPieces()
    return UnitName("player"), GetRealmName()
end

-- buildCharKey: Comparer integration: build char key.
local function buildCharKey()
    if type(_G.PawnPlayerFullName) == "string" and _G.PawnPlayerFullName ~= "" then
        return _G.PawnPlayerFullName
    end
    local name, realm = currentCharPieces()
    if not name or not realm then return nil end
    return name .. "-" .. realm
end

-- isVisibleForThisChar: Comparer integration: is visible for this char.
local function isVisibleForThisChar(pco)
    if type(pco) ~= "table" then return false end
    local charKey = buildCharKey()
    if not charKey then return false end
    local v = pco[charKey]
    return type(v) == "table" and v.Visible == true
end

-- Public: return list of all scales (normalized entries)
function Pawn.GetAllScales()
    local out = {}
    local Scales = readAllSVScalesFromPawn()
    for key, s in pairs(Scales) do
        if type(s) == "table" then
            local hasValues  = (type(s.Values) == "table")
            local isProvider = (not hasValues) and (type(s.Provider) == "string")
            local name       = s.LocalizedName or s.PrettyName or s.Name or key
            local visible    = isVisibleForThisChar(s.PerCharacterOptions)
            out[#out + 1]    = {
                key         = s.Key or s.Tag or key,
                name        = name,
                type        = hasValues and "custom" or (isProvider and "provider" or "unknown"),
                source      = hasValues and "SV" or (isProvider and "API" or "SV"),
                active      = visible,
                valueSource = hasValues and "SV" or "API",
                values      = hasValues and s.Values or nil,
                class       = s.ClassID or s.Class,
                spec        = s.Spec or s.SpecIndex,
            }
        end
    end
    return out
end

-- Pawn.GetActiveScales: Comparer integration: get active scales.
function Pawn.GetActiveScales()
    local all = Pawn.GetAllScales() or {}
    local act = {}
    for _, r in ipairs(all) do if r.active then act[#act + 1] = r end end
    return act
end

-- Try to ask possible Pawn API functions for provider values (if exposed)
-- [XIVEquip-AUTO] tryGetProviderValues: Helper for Pawn module.
local function tryGetProviderValues(keyOrName)
    local cands = {
        _G.PawnGetScaleValues,
        _G.PawnGetProviderScaleValues,
        (_G.Pawn and _G.Pawn.GetScaleValues),
        (_G.Pawn and _G.Pawn.GetProviderScaleValues),
    }
    for _, fn in ipairs(cands) do
        if type(fn) == "function" then
            local ok, vals = pcall(fn, keyOrName)
            if ok and type(vals) == "table" then return vals end
        end
    end
    return nil
end

-- Minimal BlizzKey -> PawnKey map used when scoring an item
local STATMAP = {
    -- primaries
    ITEM_MOD_STRENGTH                = "Strength",
    ITEM_MOD_STRENGTH_SHORT          = "Strength",
    ITEM_MOD_AGILITY                 = "Agility",
    ITEM_MOD_AGILITY_SHORT           = "Agility",
    ITEM_MOD_INTELLECT               = "Intellect",
    ITEM_MOD_INTELLECT_SHORT         = "Intellect",
    ITEM_MOD_STAMINA                 = "Stamina",
    ITEM_MOD_STAMINA_SHORT           = "Stamina",

    -- armor / resistance
    ITEM_MOD_ARMOR                   = "Armor",
    ITEM_MOD_ARMOR_SHORT             = "Armor",
    RESISTANCE0_NAME                 = "Armor",

    -- ratings
    ITEM_MOD_CRIT_RATING             = "CritRating",
    ITEM_MOD_CRIT_RATING_SHORT       = "CritRating",
    ITEM_MOD_HASTE_RATING            = "HasteRating",
    ITEM_MOD_HASTE_RATING_SHORT      = "HasteRating",
    ITEM_MOD_MASTERY_RATING          = "MasteryRating",
    ITEM_MOD_MASTERY_RATING_SHORT    = "MasteryRating",
    ITEM_MOD_VERSATILITY             = "Versatility",
    ITEM_MOD_VERSATILITY_SHORT       = "Versatility",

    -- other ratings
    ITEM_MOD_AVOIDANCE_RATING        = "AvoidanceRating",
    ITEM_MOD_DODGE_RATING            = "DodgeRating",
    ITEM_MOD_PARRY_RATING            = "ParryRating",
    ITEM_MOD_LIFESTEAL               = "Leech",
    ITEM_MOD_SPEED_RATING            = "MovementSpeed",
    ITEM_MOD_SPEED_RATING_SHORT      = "MovementSpeed",

    -- sockets
    EMPTY_SOCKET_PRISMATIC           = "PrismaticSocket",
    EMPTY_SOCKET_PRISMATIC1          = "PrismaticSocket",

    -- weapon damage / dps
    ITEM_MIN_DAMAGE                  = "MinDamage",
    ITEM_MAX_DAMAGE                  = "MaxDamage",
    ITEM_MOD_DAMAGE_PER_SECOND       = "Dps",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Dps",
}

local GetItemStats = GetItemStats or (C_Item and C_Item.GetItemStats)

-- GetItemStatsCompat: Comparer integration: get item stats compat.
local function GetItemStatsCompat(itemLink)
    if type(GetItemStats) == "function" then
        return GetItemStats(itemLink)
    end
    return nil
end

-- AddSocketedGemStatsFromTooltip: Reads the parent item's tooltip and adds gem (or other "extra") secondary stats
-- by computing (tooltip total) - (base GetItemStats value). This avoids double-counting base stats.
local function AddSocketedGemStatsFromTooltip(stats, itemLink)
    if type(stats) ~= "table" or type(itemLink) ~= "string" then return end
    if not C_TooltipInfo or type(C_TooltipInfo.GetHyperlink) ~= "function" then return end

    -- Helper: escape magic characters for Lua patterns
    local function escapePattern(s)
        return (s:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
    end

    -- Build label->statKey map using whatever globals exist in this client.
    -- Important: prefer SHORT keys when available so we match what GetItemStats tends to populate.
    local labelToStatKey = {}

    -- Crit
    if _G.ITEM_MOD_CRIT_RATING_SHORT then labelToStatKey[_G.ITEM_MOD_CRIT_RATING_SHORT] = "ITEM_MOD_CRIT_RATING_SHORT" end
    if _G.ITEM_MOD_CRIT_RATING then
        labelToStatKey[_G.ITEM_MOD_CRIT_RATING] = labelToStatKey[_G.ITEM_MOD_CRIT_RATING] or "ITEM_MOD_CRIT_RATING"
    end

    -- Haste
    if _G.ITEM_MOD_HASTE_RATING_SHORT then labelToStatKey[_G.ITEM_MOD_HASTE_RATING_SHORT] = "ITEM_MOD_HASTE_RATING_SHORT" end
    if _G.ITEM_MOD_HASTE_RATING then
        labelToStatKey[_G.ITEM_MOD_HASTE_RATING] = labelToStatKey[_G.ITEM_MOD_HASTE_RATING] or "ITEM_MOD_HASTE_RATING"
    end

    -- Mastery
    if _G.ITEM_MOD_MASTERY_RATING_SHORT then
        labelToStatKey[_G.ITEM_MOD_MASTERY_RATING_SHORT] =
        "ITEM_MOD_MASTERY_RATING_SHORT"
    end
    if _G.ITEM_MOD_MASTERY_RATING then
        labelToStatKey[_G.ITEM_MOD_MASTERY_RATING] = labelToStatKey[_G.ITEM_MOD_MASTERY_RATING] or
            "ITEM_MOD_MASTERY_RATING"
    end

    -- Versatility
    if _G.ITEM_MOD_VERSATILITY_SHORT then labelToStatKey[_G.ITEM_MOD_VERSATILITY_SHORT] = "ITEM_MOD_VERSATILITY_SHORT" end
    if _G.ITEM_MOD_VERSATILITY then
        labelToStatKey[_G.ITEM_MOD_VERSATILITY] = labelToStatKey[_G.ITEM_MOD_VERSATILITY] or "ITEM_MOD_VERSATILITY"
    end

    if next(labelToStatKey) == nil then return end

    local tip = C_TooltipInfo.GetHyperlink(itemLink)
    if type(tip) ~= "table" or type(tip.lines) ~= "table" then return end

    -- 1) Accumulate tooltip totals per statKey
    local totals = {}
    for _, line in ipairs(tip.lines) do
        local text = line and line.leftText
        if type(text) == "string" and text:find("%+") then
            -- We intentionally do NOT require a "Socketed:" prefix (it's often not present in C_TooltipInfo text)
            for label, statKey in pairs(labelToStatKey) do
                -- Match "+<number> <label>" anywhere in the line
                local pattern = "%+%s*(%d+)%s*" .. escapePattern(label)
                local amtStr = text:match(pattern)
                local amt = tonumber(amtStr)
                if amt and amt > 0 then
                    totals[statKey] = (totals[statKey] or 0) + amt
                end
            end
        end
    end

    -- 2) Add only the delta over base stats (prevents doubling)
    -- Also dedupe statKeys in case both LONG and SHORT labels map to different keys.
    local seenStatKey = {}
    for _, statKey in pairs(labelToStatKey) do
        if not seenStatKey[statKey] then
            seenStatKey[statKey] = true

            local t = totals[statKey] or 0
            local base = stats[statKey] or 0
            local extra = t - base

            if extra > 0 then
                stats[statKey] = base + extra
            end
        end
    end
end

-- Parse tooltip to extract min/max damage and speed (Retail DF)
-- [XIVEquip-AUTO] GetWeaponDamageAndSpeed: Returns weapon damage and speed.
local function GetWeaponDamageAndSpeed(link)
    if not link or not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then return nil end
    local tip = C_TooltipInfo.GetHyperlink(link)
    if not tip or not tip.lines then return nil end

    local minD, maxD, speed
    -- grab: Comparer integration: grab.
    local function grab(s)
        if type(s) ~= "string" then return end
        local a, b = s:match("(%d+)%s*%-%s*(%d+)%s+[Dd]amage")
        if a and b then minD, maxD = tonumber(a), tonumber(b) end
        local sp = s:match("[Ss]peed%s+([%d%.]+)")
        if sp then speed = tonumber(sp) end
    end

    for _, line in ipairs(tip.lines) do
        if line.leftText then grab(line.leftText) end
        if line.rightText then grab(line.rightText) end
    end
    return minD, maxD, speed
end

-- Compute a numeric score for an itemLink given a values table

-- [XIVEquip-AUTO] computeScoreFromValues: Computes a score used to compare candidate items.
local function computeScoreFromValues(itemLink, values, slot)
    if not itemLink or type(values) ~= "table" then return nil end
    local stats = GetItemStatsCompat(itemLink)
    if type(stats) ~= "table" then return nil end

    -- Add stats from socketed gems (tooltip-based; localized; synchronous)
    AddSocketedGemStatsFromTooltip(stats, itemLink)

    local dbgslot = slot or "force"
    if _debugEnabled() then
        local parts = {}
        for k, v in pairs(stats) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
        table.sort(parts)
        if XIVEquip and XIVEquip.Log and XIVEquip.Log.Debugf then
            XIVEquip.Log.Debugf(dbgslot, "[score] stats tokens: %s", table.concat(parts, ", "))
        else
            logDebug("[score] stats tokens: %s", table.concat(parts, ", "))
        end
    end
    local score = 0

    -- Debug: print a compact list of common weights if logger available
    if XIVEquip and XIVEquip.Log and XIVEquip.Log.Debugf then
        -- tv: Comparer integration: tv.
        local function tv(k) return tostring(values and values[k]) end
        XIVEquip.Log.Debugf(dbgslot,
            "[score] weights: Armor=%s Strength=%s Stamina=%s Haste=%s Crit=%s Vers=%s MaxDamage=%s MinDamage=%s Dps=%s Avoid=%s Leech=%s Speed=%s",
            tv("Armor"), tv("Strength"), tv("Stamina"), tv("HasteRating"), tv("CritRating"), tv("Versatility"),
            tv("MaxDamage"), tv("MinDamage"), tv("Dps"), tv("AvoidanceRating"), tv("Leech"), tv("MovementSpeed"))
    end

    local total = 0

    -- First: non-damage stats (skip Min/Max/Dps keys)
    for blizzKey, pawnKey in pairs(STATMAP) do
        if pawnKey ~= "MinDamage" and pawnKey ~= "MaxDamage" and pawnKey ~= "Dps" then
            local amt = stats[blizzKey]
            local w = values[pawnKey]
            if type(amt) == "number" and type(w) == "number" then
                local add = amt * w
                total = total + add
                if XIVEquip and XIVEquip.Log and XIVEquip.Log.Debugf then
                    XIVEquip.Log.Debugf(dbgslot, "[score] %s (%s): %s × %s = %s", tostring(pawnKey), tostring(blizzKey),
                        tostring(amt), tostring(w), tostring(add))
                end
            end
        end
    end

    -- Weapon damage handling: prefer Min/Max + speed; if not available, fall back to DPS
    local minW = values and tonumber(values.MinDamage)
    local maxW = values and tonumber(values.MaxDamage)
    local dpsW = values and tonumber(values.Dps)

    local minStat = stats.ITEM_MIN_DAMAGE
    local maxStat = stats.ITEM_MAX_DAMAGE
    local dpsStat = stats.ITEM_MOD_DAMAGE_PER_SECOND or stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT or stats.Dps

    -- Try to get tooltip-derived min/max/speed if min/max weights exist but stats lack them
    if (minW or maxW) and (not minStat or not maxStat) then
        local tmin, tmax, tspeed = GetWeaponDamageAndSpeed(itemLink)
        if tmin and tmax then
            minStat = minStat or tmin
            maxStat = maxStat or tmax
            dpsStat = dpsStat or (tspeed and ((tmin + tmax) / 2) / tspeed)
        end
    end

    -- If we have min/max weights, apply them preferentially
    if (minW or maxW) then
        if type(minStat) == "number" and type(minW) == "number" then
            local add = minStat * minW; total = total + add
            if XIVEquip and XIVEquip.Log and XIVEquip.Log.Debugf then
                XIVEquip.Log.Debugf(dbgslot, "[score] MinDamage (ITEM_MIN_DAMAGE): %s × %s = %s", tostring(minStat),
                    tostring(minW), tostring(add))
            end
        end
        if type(maxStat) == "number" and type(maxW) == "number" then
            local add = maxStat * maxW; total = total + add
            if XIVEquip and XIVEquip.Log and XIVEquip.Log.Debugf then
                XIVEquip.Log.Debugf(dbgslot, "[score] MaxDamage (ITEM_MAX_DAMAGE): %s × %s = %s", tostring(maxStat),
                    tostring(maxW), tostring(add))
            end
        end
    else
        -- No Min/Max weights: if DPS weight exists, use DPS stat
        if dpsW and type(dpsStat) == "number" then
            local add = dpsStat * dpsW; total = total + add
            if XIVEquip and XIVEquip.Log and XIVEquip.Log.Debugf then
                XIVEquip.Log.Debugf(dbgslot, "[score] Dps (ITEM_MOD_DAMAGE_PER_SECOND): %s × %s = %s", tostring(dpsStat),
                    tostring(dpsW), tostring(add))
            end
        end
    end

    -- Debug: total
    if XIVEquip and XIVEquip.Log and XIVEquip.Log.Debugf then
        XIVEquip.Log.Debugf(dbgslot, "[score] TOTAL (computed) = %s", tostring(total))
    end

    return total
end

-- Score an item when given a scale entry (custom or provider).
-- Returns: value|nil, sourceTag ("SV"|"API"|"no-values"), err|nil
local function scoreItemWithEntry(itemLink, entry, slot)
    if not entry then return nil, "no-scale" end
    -- Custom (values saved in SV)
    if entry.type == "custom" and type(entry.values) == "table" then
        local s = computeScoreFromValues(itemLink, entry.values, slot)
        if type(s) == "number" then return s, "SV", nil end
        return nil, "SV", "no-stats"
    end
    -- Provider: try API values
    if entry.type == "provider" or not entry.values then
        local keyOrName = entry.key or entry.name
        local vals = tryGetProviderValues(keyOrName)
        if type(vals) == "table" then
            local s = computeScoreFromValues(itemLink, vals, slot)
            if type(s) == "number" then return s, "API", nil end
            return nil, "API", "no-stats"
        end
        return nil, "API", "no-api-values"
    end
    return nil, "no-scoring-path"
end

-- Choose a single best active scale for the player's current spec/class.
-- Logic: exact spec name match preferred, then class filter, else first active.
local function chooseBestActiveScaleForPlayer()
    local _, _, classID = UnitClass("player")
    local specIndex = GetSpecialization() or 0
    local specName = (specIndex > 0 and select(2, GetSpecializationInfo(specIndex))) or ""
    local act = Pawn.GetActiveScales() or {}
    if #act == 0 then return nil end
    -- helper normalizer
    local function norm(s) return tostring(s or ""):lower():gsub("[%s%p]+", "") end
    local normSpec = norm(specName)
    local firstByClass
    for _, r in ipairs(act) do
        if (r.class == nil) or (r.class == classID) then
            firstByClass = firstByClass or r
            local rn = norm(r.name or r.key)
            if rn == normSpec then return r end
            if rn:find(normSpec, 1, true) then return r end
        end
    end
    return firstByClass or act[1]
end

-- Public: expose the chosen active scale entry (used by other modules).
function Pawn.GetBestActiveScaleForPlayer()
    return chooseBestActiveScaleForPlayer()
end

-- Public: get the values table for the chosen active scale.
-- Returns: valuesTable|nil, scaleEntry|nil
function Pawn.GetBestScaleValuesForPlayer()
    local entry = chooseBestActiveScaleForPlayer()
    if not entry then return nil, nil end
    if entry.type == "custom" and type(entry.values) == "table" then
        return entry.values, entry
    end
    -- provider: try API values
    local keyOrName = entry.key or entry.name
    local vals = tryGetProviderValues(keyOrName)
    if type(vals) == "table" then
        return vals, entry
    end
    return nil, entry
end

function Pawn.GetScaleValues(keyOrName)
    if not keyOrName then return Pawn.GetBestScaleValuesForPlayer() end
    for _, entry in ipairs(Pawn.GetActiveScales() or {}) do
        if entry and (entry.key == keyOrName or entry.name == keyOrName) then
            if entry.type == "custom" and type(entry.values) == "table" then
                return entry.values, entry
            end
            local vals = tryGetProviderValues(entry.key or entry.name)
            if type(vals) == "table" then return vals, entry end
            return nil, entry
        end
    end
    return nil, nil
end

-- Public: baseline assumption for "what is a gem worth" when estimating empty-socket potential.
-- User configurable via XIVEquip_Settings.SocketAssumption.SecondaryAmount.
function Pawn.GetSocketAssumptionSecondaryAmount()
    local s = _G.XIVEquip_Settings
    local v = s and s.SocketAssumption and s.SocketAssumption.SecondaryAmount
    v = tonumber(v)
    if v and v > 0 then return v end
    return 10
end

-- Public scorer: score by link using the chosen active scale
function Pawn.ScoreItemLink(itemLink, slot)
    if not itemLink then return nil, "no-link" end
    local best = chooseBestActiveScaleForPlayer()
    if not best then return nil, "no-active-scale" end
    -- Debug: chosen scale
    if XIVEquip and XIVEquip.Log and XIVEquip.Log.Debugf then
        -- log choice using provided slot (if any) so lines can be filtered
        local dbgslot = slot or "force"
        XIVEquip.Log.Debugf(dbgslot, "[score] choose: name=%s key=%s type=%s src=%s spec=%s", tostring(best.name),
            tostring(best.key), tostring(best.type), tostring(best.source), tostring(best.spec))
    end
    local v, src, err = scoreItemWithEntry(itemLink, best, slot)
    return v, src or err, best
end

-- Public: simple tooltip header for UI
function Pawn.GetTooltipHeader()
    local specIndex = GetSpecialization() or 0
    local specName = (specIndex > 0 and select(2, GetSpecializationInfo(specIndex))) or nil
    local scaleEntry = chooseBestActiveScaleForPlayer()
    local scaleDisplay = scaleEntry and (scaleEntry.name or scaleEntry.key) or nil
    if scaleDisplay and specName then
        return string.format("Comparer: Pawn  |  Scale: %s (Spec: %s)", scaleDisplay, specName)
    elseif scaleDisplay then
        return string.format("Comparer: Pawn  |  Scale: %s", scaleDisplay)
    elseif specName then
        return string.format("Comparer: Pawn  |  Spec: %s", specName)
    else
        return "Comparer: Pawn"
    end
end

-- ------------------------------------------------------------
-- Unusable item-type flags (Pawn scales)
-- ------------------------------------------------------------

-- Pawn can mark certain weights as "unusable" (the red X toggle in the Weights UI). This manifests as a -1000000 weight value.
-- XIVEquip uses this to avoid suggesting weapons (or offhands) that the player/spec/scale considers unusable.

-- Pawn can mark certain item-type stats as "unusable" (the red X toggle in the Weights UI).
-- In many builds, Pawn stores "unusable" as a large negative weight (commonly -1000000).

-- Treat <= this as "unusable". (We keep it a little loose in case Pawn changes exact value.)
local PAWN_UNUSABLE_WEIGHT = -999999

-- isStatMarkedUnusable: Checks several known Pawn storage shapes, including numeric sentinel weights.
local function isStatMarkedUnusable(values, pawnKey)
    if type(values) ~= "table" or type(pawnKey) ~= "string" then
        -- XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] invalid args values=%s pawnKey=%s",
        --   tostring(type(values)), tostring(pawnKey))
        return false
    end

    -- Most common (for item-type stats): Values["IsWarglaive"] = -1000000
    local raw = rawget(values, pawnKey)
    if type(raw) == "number" then
        if raw <= PAWN_UNUSABLE_WEIGHT then
            -- XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] match via numeric sentinel %s=%s",
            --   tostring(pawnKey), tostring(raw))
            return true
        end
        -- Useful debug for "why not unusable"
        -- XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] numeric but not unusable %s=%s",
        --   tostring(pawnKey), tostring(raw))
        return false
    end

    -- Common alternate shape in some Pawn versions: Values.UnusableStats["IsSword2H"] = true
    local us = rawget(values, "UnusableStats")
    if type(us) == "table" and (us[pawnKey] == true or us[pawnKey] == 1) then
        -- XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] match via Values.UnusableStats[%s]=%s",
        --   tostring(pawnKey), tostring(us[pawnKey]))
        return true
    end

    -- Some versions store a per-stat table with an Unusable flag.
    if type(raw) == "table" then
        local flag = raw.Unusable or raw.unusable or raw.IsUnusable or raw.isUnusable
        if flag == true or flag == 1 then
            -- XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] match via table flag on %s",
            --   tostring(pawnKey))
            return true
        end

        -- Sometimes it's { Value = <n>, Unusable = <bool> } or { Value = -1000000 }
        local val = raw.Value or raw.value
        if type(val) == "number" and val <= PAWN_UNUSABLE_WEIGHT then
            --XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] match via table Value sentinel %s.Value=%s",
            --  tostring(pawnKey), tostring(val))
            return true
        end
    end

    -- Rare shape: separate key like "IsSword2H_Unusable" or "IsSword2HUnusable".
    local k2 = pawnKey .. "_Unusable"
    local k3 = pawnKey .. "Unusable"
    local r2 = rawget(values, k2)
    local r3 = rawget(values, k3)

    if r2 == true or r2 == 1 then
        --XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] match via key %s=%s", tostring(k2), tostring(r2))
        return true
    end
    if r3 == true or r3 == 1 then
        --XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] match via key %s=%s", tostring(k3), tostring(r3))
        return true
    end

    return false
end

-- Map weapon subclass IDs to Pawn "IsX" keys shown in the Pawn Weights UI.
-- Uses Blizzard subclass IDs for LE_ITEM_CLASS_WEAPON (2).
local WEAPON_SUBCLASS_TO_PAWNKEY = {
    [0]  = "IsAxe1H",
    [1]  = "IsAxe2H",
    [2]  = "IsBow",
    [3]  = "IsGun",
    [4]  = "IsMace1H",
    [5]  = "IsMace2H",
    [6]  = "IsPolearm",
    [7]  = "IsSword1H",
    [8]  = "IsSword2H",
    [9]  = "IsWarglaive",
    [10] = "IsStaff",
    [11] = "IsFist", -- IMPORTANT: Pawn SV uses IsFist (not IsFistWeapon) in your data
    [12] = "IsFist",
    [13] = "IsFist",
    [15] = "IsDagger",
    [16] = "IsThrown",
    [18] = "IsCrossbow",
    [19] = "IsWand",
}

-- Public: Determine whether the chosen active Pawn scale marks this item type as unusable.
-- Returns: true|false, pawnKeyUsed|nil
function Pawn.IsItemTypeUnusable(itemID, equipLoc)
    itemID = tonumber(itemID)
    if not itemID then
        XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] invalid itemID=%s", tostring(itemID))
        return false
    end

    local values = Pawn.GetBestScaleValuesForPlayer()
    if type(values) ~= "table" then
        XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] no scale values found")
        return false
    end

    local name, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    if not classID then
        XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] item info not ready id=%s", tostring(itemID))
        return false
    end

    if classID ~= 2 then -- LE_ITEM_CLASS_WEAPON
        return false
    end

    local pawnKey = WEAPON_SUBCLASS_TO_PAWNKEY[subClassID]
    if not pawnKey then
        XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] no pawnKey for subclass=%s id=%s",
            tostring(subClassID), tostring(itemID))
        return false
    end

    XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] checking item=%s id=%s pawnKey=%s equipLoc=%s raw=%s",
        tostring(name), tostring(itemID), tostring(pawnKey), tostring(equipLoc),
        tostring(rawget(values, pawnKey)))

    if isStatMarkedUnusable(values, pawnKey) then
        XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] RESULT=true via %s", tostring(pawnKey))
        return true, pawnKey
    end

    -- Offhand weapon and frill have separate toggles in Pawn,
    -- but in your SV "IsOffHand" is the big one (and it uses the numeric sentinel too).
    if equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_HOLDABLE" then
        if isStatMarkedUnusable(values, "IsOffHand") then
            XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] RESULT=true via IsOffHand toggle id=%s", tostring(itemID))
            return true, "IsOffHand"
        end
    end

    XIVEquip.Log.Debugf(dbgslot, "[pawn-unusable] RESULT=false pawnKey=%s id=%s", tostring(pawnKey), tostring(itemID))
    return false, pawnKey
end

-- End of Interface.lua
