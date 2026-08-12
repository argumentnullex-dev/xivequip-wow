-- XIVWeights/Import/Serialized.lua
-- Detects and converts pasted scale data into editable native scales. This is
-- deliberately independent from live Integration providers such as Pawn.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
XIVEquip.XIVWeights.Import = XIVEquip.XIVWeights.Import or {}
local XIVWeights = XIVEquip.XIVWeights

local Serialized = {}
XIVWeights.Import.Serialized = Serialized

local aliases = {
  strength = "strength", str = "strength",
  agility = "agility", agi = "agility",
  intellect = "intellect", int = "intellect",
  stamina = "stamina", sta = "stamina",
  armor = "armor",
  bonusarmor = "bonusArmor", bonus_armour = "bonusArmor",
  criticalstrike = "criticalStrike", crit = "criticalStrike", critical = "criticalStrike",
  criticalstrikerating = "criticalStrike", critrating = "criticalStrike",
  haste = "haste", hasting = "haste", hasterating = "haste",
  mastery = "mastery", masteryrating = "mastery",
  versatility = "versatility", vers = "versatility", versatilityrating = "versatility", versrating = "versatility",
  leech = "leech", leechrating = "leech", avoidance = "avoidance", avoidancerating = "avoidance", movementspeed = "movementSpeed",
  indestructible = "indestructible",
  weapondps = "weaponDps", dps = "weaponDps", weapondamage = "weaponDps",
  weaponmindamage = "weaponMinDamage", mindamage = "weaponMinDamage",
  weaponmaxdamage = "weaponMaxDamage", maxdamage = "weaponMaxDamage",
  weaponswingintervalseconds = "weaponSwingIntervalSeconds",
  weaponswinginterval = "weaponSwingIntervalSeconds", weaponspeed = "weaponSwingIntervalSeconds",
}

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeKey(value)
  return tostring(value or ""):lower():gsub("[%s_%-]", "")
end

local function featureKey(value)
  return aliases[normalizeKey(value)]
end

local function parseNumber(value)
  value = tostring(value or ""):gsub("%%", "")
  return tonumber(value)
end

-- Small JSON reader for the JSON emitted by the Export dialog. It is kept
-- local to the importer so the addon does not need a general-purpose JSON
-- dependency just to round-trip scales.
local function jsonDecode(text)
  local index = 1
  local length = #text

  local function skipWhitespace()
    while index <= length and text:sub(index, index):match("%s") do index = index + 1 end
  end

  local parseValue
  local function parseString()
    index = index + 1
    local out = {}
    while index <= length do
      local char = text:sub(index, index)
      if char == '"' then index = index + 1; return table.concat(out) end
      if char == "\\" then
        index = index + 1
        local escaped = text:sub(index, index)
        local replacements = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        out[#out + 1] = replacements[escaped] or escaped
      else
        out[#out + 1] = char
      end
      index = index + 1
    end
    return nil, "unterminated-string"
  end

  local function parseNumberValue()
    local start = index
    while index <= length and text:sub(index, index):match("[%d%+%-%e%E%.]") do index = index + 1 end
    local number = tonumber(text:sub(start, index - 1))
    if number == nil then return nil, "invalid-number" end
    return number
  end

  local function parseArray()
    index = index + 1
    local out = {}
    skipWhitespace()
    if text:sub(index, index) == "]" then index = index + 1; return out end
    while index <= length do
      local value, reason = parseValue()
      if reason then return nil, reason end
      out[#out + 1] = value
      skipWhitespace()
      local char = text:sub(index, index)
      if char == "]" then index = index + 1; return out end
      if char ~= "," then return nil, "invalid-array" end
      index = index + 1
      skipWhitespace()
    end
    return nil, "unterminated-array"
  end

  local function parseObject()
    index = index + 1
    local out = {}
    skipWhitespace()
    if text:sub(index, index) == "}" then index = index + 1; return out end
    while index <= length do
      if text:sub(index, index) ~= '"' then return nil, "object-key-required" end
      local key, reason = parseString()
      if reason then return nil, reason end
      skipWhitespace()
      if text:sub(index, index) ~= ":" then return nil, "object-colon-required" end
      index = index + 1
      local value
      value, reason = parseValue()
      if reason then return nil, reason end
      out[key] = value
      skipWhitespace()
      local char = text:sub(index, index)
      if char == "}" then index = index + 1; return out end
      if char ~= "," then return nil, "invalid-object" end
      index = index + 1
      skipWhitespace()
    end
    return nil, "unterminated-object"
  end

  function parseValue()
    skipWhitespace()
    local char = text:sub(index, index)
    if char == '"' then return parseString() end
    if char == "{" then return parseObject() end
    if char == "[" then return parseArray() end
    if text:sub(index, index + 3) == "true" then index = index + 4; return true end
    if text:sub(index, index + 4) == "false" then index = index + 5; return false end
    if text:sub(index, index + 3) == "null" then index = index + 4; return nil end
    return parseNumberValue()
  end

  local value, reason = parseValue()
  if reason then return nil, reason end
  skipWhitespace()
  if index <= length then return nil, "trailing-data" end
  return value
end

-- Base64 (RFC 4648, standard alphabet with '=' padding). Pure Lua, no
-- WoW-specific dependency, kept local to this module for the same reason
-- the JSON reader above is -- one small self-contained implementation
-- beats a general-purpose dependency for a single round-trip use case.
-- This is a pragmatic decoder, not a hardened general-purpose validator:
-- malformed padding placed anywhere but the final 4-byte group isn't
-- specifically rejected. That's an acceptable tradeoff here because the
-- only real producer of this addon's base64 text is Serialized.EncodeBase64
-- itself (always correctly padded), and Detect/Parse below only ever treat
-- a decode result as meaningful when the decoded bytes also look like the
-- addon's own scale JSON -- garbage input either fails to decode at all or
-- decodes to bytes that don't look like JSON, either way falling through
-- safely rather than silently misinterpreting unrelated pasted text.
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP

local function base64Lookup()
  if B64_LOOKUP then return B64_LOOKUP end
  B64_LOOKUP = {}
  for i = 1, #B64_CHARS do B64_LOOKUP[B64_CHARS:byte(i)] = i - 1 end
  return B64_LOOKUP
end

local function base64Encode(data)
  data = tostring(data or "")
  local length = #data
  local out = {}
  for i = 1, length, 3 do
    local b1, b2, b3 = data:byte(i, i + 2)
    local n = (b1 << 16) | ((b2 or 0) << 8) | (b3 or 0)
    local chunkLen = math.min(3, length - i + 1)
    out[#out + 1] = B64_CHARS:sub((n >> 18 & 0x3F) + 1, (n >> 18 & 0x3F) + 1)
    out[#out + 1] = B64_CHARS:sub((n >> 12 & 0x3F) + 1, (n >> 12 & 0x3F) + 1)
    out[#out + 1] = chunkLen >= 2 and B64_CHARS:sub((n >> 6 & 0x3F) + 1, (n >> 6 & 0x3F) + 1) or "="
    out[#out + 1] = chunkLen >= 3 and B64_CHARS:sub((n & 0x3F) + 1, (n & 0x3F) + 1) or "="
  end
  return table.concat(out)
end

local function base64Decode(data)
  data = tostring(data or ""):gsub("%s+", "")
  if data == "" then return "" end
  if #data % 4 ~= 0 then return nil end
  local lookup = base64Lookup()
  local out = {}
  for i = 1, #data, 4 do
    local c1, c2, c3, c4 = data:byte(i), data:byte(i + 1), data:byte(i + 2), data:byte(i + 3)
    local v1, v2 = lookup[c1], lookup[c2]
    if not v1 or not v2 then return nil end
    local pad = 0
    local v3, v4 = 0, 0
    if c3 == 61 then -- '=' -- only valid when c4 is '=' too (2 bytes of padding)
      pad = 2
      if c4 ~= 61 then return nil end
    else
      v3 = lookup[c3]
      if not v3 then return nil end
      if c4 == 61 then
        pad = 1
      else
        v4 = lookup[c4]
        if not v4 then return nil end
      end
    end
    local n = (v1 << 18) | (v2 << 12) | (v3 << 6) | v4
    out[#out + 1] = string.char((n >> 16) & 0xFF)
    if pad < 2 then out[#out + 1] = string.char((n >> 8) & 0xFF) end
    if pad < 1 then out[#out + 1] = string.char(n & 0xFF) end
  end
  return table.concat(out)
end

Serialized.EncodeBase64 = base64Encode
Serialized.DecodeBase64 = base64Decode

local function looksLikeJSON(text)
  text = trim(text)
  return text:sub(1, 1) == "{" or text:find('"format"', 1, true) or text:find('"weights"', 1, true)
end

local function normalizeWeights(raw)
  local weights = {}
  local highest = 0
  for key, value in pairs(raw or {}) do
    local feature = featureKey(key) or (XIVWeights.FEATURE_SET and XIVWeights.FEATURE_SET[key] and key)
    local number = parseNumber(value)
    if feature and number and number >= 0 then
      weights[feature] = number
      if number > highest then highest = number end
    end
  end
  if highest <= 0 then return nil, "no-weights" end
  for feature, value in pairs(weights) do weights[feature] = value / highest end
  return weights
end

local function fromJSON(text, requestedSpecID)
  local payload, reason = jsonDecode(text)
  if type(payload) ~= "table" or type(payload.weights) ~= "table" then return nil, reason or "missing-weights" end
  local weights, weightReason = normalizeWeights(payload.weights)
  if not weights then return nil, weightReason end
  return {
    format = "native-json",
    name = payload.name,
    specID = tonumber(payload.specID) or tonumber(requestedSpecID),
    weights = weights,
  }
end

local function fromText(text, requestedSpecID, format)
  local raw = {}
  for key, value in tostring(text):gmatch("([%a][%w_%-]*)%s*[:=]%s*([%+%-]?[%d%.]+)") do
    raw[key] = parseNumber(value)
  end
  if format == "pawn" and raw.Speed ~= nil then raw.weaponSwingIntervalSeconds = raw.Speed end
  local weights, reason = normalizeWeights(raw)
  if not weights then return nil, reason end
  local name = tostring(text):match("[Pp]awn:%s*[Vv]%d+:%s*%\"([^\"]+)%\"")
  return { format = format or "text", name = name, specID = tonumber(requestedSpecID), weights = weights }
end

-- resolveJSONText(text) -> jsonText | nil
-- text is already JSON, or is a base64 encoding of JSON (accepted per the
-- addon's own Export dialog and any base64 blob a player pastes back in) --
-- either way, returns the actual JSON text to feed into jsonDecode, or nil
-- if neither interpretation looks like this addon's scale JSON.
local function resolveJSONText(text)
  text = trim(text)
  if looksLikeJSON(text) then return text end
  local decoded = base64Decode(text)
  if decoded and looksLikeJSON(decoded) then return trim(decoded) end
  return nil
end

function Serialized.Detect(text)
  text = trim(text)
  if text == "" then return nil, "empty" end
  if resolveJSONText(text) then return "native-json" end
  local lower = text:lower()
  if lower:find("pawn", 1, true) then return "pawn" end
  if lower:find("simcraft", 1, true) or lower:find("simc", 1, true) then return "simc" end
  if lower:find("raidbots", 1, true) then return "raidbots" end
  if lower:find("ask mr robot", 1, true) or lower:find("askmrrobot", 1, true) then return "ask-mr-robot" end
  if lower:find("wowhead", 1, true) then return "wowhead" end
  return "text"
end

function Serialized.Parse(text, requestedSpecID)
  local format, reason = Serialized.Detect(text)
  if not format then return nil, reason end
  if format == "native-json" then return fromJSON(resolveJSONText(text), requestedSpecID) end
  return fromText(text, requestedSpecID, format)
end

return Serialized
