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

-- Wowhead-style pasted priority list ("Strength > Crit > Haste > Mastery >
-- Versatility", or the same stat names one per line): every token is a bare
-- stat name with no operator or digit, which is a strict, narrow shape that
-- real Pawn/SimC/JSON text -- always containing "=", ":", or a digit
-- somewhere -- can never accidentally satisfy.
local function tokenizePriorityList(text)
  local tokens = {}
  for token in tostring(text):gmatch("[^\n>]+") do
    local trimmed = trim(token)
    if trimmed ~= "" then tokens[#tokens + 1] = trimmed end
  end
  if #tokens < 2 then return nil end
  for _, token in ipairs(tokens) do
    if token:find("[:=%d]") or not featureKey(token) then return nil end
  end
  return tokens
end

-- A priority list only encodes ORDER, not magnitude. The top-ranked stat
-- (almost always the primary stat) gets a full 1.0, then the remaining
-- ranks step down linearly starting from 0.5 rather than continuing the
-- same descent from 1.0 -- in modern WoW the primary stat dominates via
-- item level, and secondaries mainly matter for comparing items of similar
-- item level, so the big first drop reflects that split instead of
-- implying rank 2 is only marginally behind rank 1.
local function fromPriorityList(tokens, requestedSpecID)
  local weights = {}
  local remaining = #tokens - 1
  for i, token in ipairs(tokens) do
    local feature = featureKey(token)
    if i == 1 then
      weights[feature] = 1.0
    else
      local rankAmongRest = i - 1
      weights[feature] = 0.5 * (remaining - rankAmongRest + 1) / remaining
    end
  end
  return { format = "priority-list", name = nil, specID = tonumber(requestedSpecID), weights = weights }
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

function Serialized.Detect(text)
  text = trim(text)
  if text == "" then return nil, "empty" end
  if text:sub(1, 1) == "{" or text:find('"format"', 1, true) then return "native-json" end
  if tokenizePriorityList(text) then return "priority-list" end
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
  if format == "native-json" then return fromJSON(text, requestedSpecID) end
  if format == "priority-list" then return fromPriorityList(tokenizePriorityList(text), requestedSpecID) end
  return fromText(text, requestedSpecID, format)
end

return Serialized
