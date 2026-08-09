-- XIVWeights/Builtin/Defaults.lua
-- Built-in spec scale templates. These are source-controlled defaults, not
-- user settings. XIVWeights.Config creates editable SavedVariables copies for
-- the user's class/specs and can reset those copies from this table.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
XIVEquip.XIVWeights.Builtin = XIVEquip.XIVWeights.Builtin or {}
local XIVWeights = XIVEquip.XIVWeights

local Defaults = {}
XIVWeights.Builtin.Defaults = Defaults

Defaults.Version = 1

Defaults.Classes = {
  WARRIOR = {
    { id = 71, name = "Arms" },
    { id = 72, name = "Fury" },
    { id = 73, name = "Protection" },
  },
  PALADIN = {
    { id = 65, name = "Holy" },
    { id = 66, name = "Protection" },
    { id = 70, name = "Retribution" },
  },
  HUNTER = {
    { id = 253, name = "Beast Mastery" },
    { id = 254, name = "Marksmanship" },
    { id = 255, name = "Survival" },
  },
  ROGUE = {
    { id = 259, name = "Assassination" },
    { id = 260, name = "Outlaw" },
    { id = 261, name = "Subtlety" },
  },
  PRIEST = {
    { id = 256, name = "Discipline" },
    { id = 257, name = "Holy" },
    { id = 258, name = "Shadow" },
  },
  DEATHKNIGHT = {
    { id = 250, name = "Blood" },
    { id = 251, name = "Frost" },
    { id = 252, name = "Unholy" },
  },
  SHAMAN = {
    { id = 262, name = "Elemental" },
    { id = 263, name = "Enhancement" },
    { id = 264, name = "Restoration" },
  },
  MAGE = {
    { id = 62, name = "Arcane" },
    { id = 63, name = "Fire" },
    { id = 64, name = "Frost" },
  },
  WARLOCK = {
    { id = 265, name = "Affliction" },
    { id = 266, name = "Demonology" },
    { id = 267, name = "Destruction" },
  },
  MONK = {
    { id = 268, name = "Brewmaster" },
    { id = 269, name = "Windwalker" },
    { id = 270, name = "Mistweaver" },
  },
  DRUID = {
    { id = 102, name = "Balance" },
    { id = 103, name = "Feral" },
    { id = 104, name = "Guardian" },
    { id = 105, name = "Restoration" },
  },
  DEMONHUNTER = {
    { id = 577, name = "Havoc" },
    { id = 581, name = "Vengeance" },
  },
  EVOKER = {
    { id = 1467, name = "Devastation" },
    { id = 1468, name = "Preservation" },
    { id = 1473, name = "Augmentation" },
  },
}

local function weights(primary, priority)
  local out = {}
  out[primary] = 1.0
  local value = 0.5
  for _, feature in ipairs(priority or {}) do
    out[feature] = value
    value = value - 0.1
    if value < 0.1 then value = 0.1 end
  end
  return out
end

local source = {
  kind = "xivequip-default",
  defaultVersion = Defaults.Version,
  refresh = "tools/default-scales/refresh-prompt.md",
}

local function scale(specID, classFile, specName, primary, priority)
  return XIVWeights.NewScale({
    id = "default:spec:" .. tostring(specID),
    name = specName,
    source = source,
    weights = weights(primary, priority),
    meta = {
      specID = specID,
      classFile = classFile,
      specName = specName,
      defaultVersion = Defaults.Version,
      priority = priority,
    },
  })
end

Defaults.Scales = {
  [71] = scale(71, "WARRIOR", "Arms", "strength", { "criticalStrike", "haste", "mastery", "versatility" }),
  [72] = scale(72, "WARRIOR", "Fury", "strength", { "mastery", "haste", "criticalStrike", "versatility" }),
  [73] = scale(73, "WARRIOR", "Protection", "strength", { "haste", "versatility", "mastery", "criticalStrike" }),

  [65] = scale(65, "PALADIN", "Holy", "intellect", { "haste", "mastery", "criticalStrike", "versatility" }),
  [66] = scale(66, "PALADIN", "Protection", "strength", { "haste", "mastery", "versatility", "criticalStrike" }),
  [70] = scale(70, "PALADIN", "Retribution", "strength", { "mastery", "criticalStrike", "haste", "versatility" }),

  [253] = scale(253, "HUNTER", "Beast Mastery", "agility", { "haste", "criticalStrike", "mastery", "versatility" }),
  [254] = scale(254, "HUNTER", "Marksmanship", "agility", { "criticalStrike", "mastery", "haste", "versatility" }),
  [255] = scale(255, "HUNTER", "Survival", "agility", { "haste", "criticalStrike", "mastery", "versatility" }),

  [259] = scale(259, "ROGUE", "Assassination", "agility", { "mastery", "criticalStrike", "haste", "versatility" }),
  [260] = scale(260, "ROGUE", "Outlaw", "agility", { "versatility", "criticalStrike", "haste", "mastery" }),
  [261] = scale(261, "ROGUE", "Subtlety", "agility", { "criticalStrike", "versatility", "mastery", "haste" }),

  [256] = scale(256, "PRIEST", "Discipline", "intellect", { "haste", "criticalStrike", "mastery", "versatility" }),
  [257] = scale(257, "PRIEST", "Holy", "intellect", { "mastery", "haste", "criticalStrike", "versatility" }),
  [258] = scale(258, "PRIEST", "Shadow", "intellect", { "haste", "mastery", "criticalStrike", "versatility" }),

  [250] = scale(250, "DEATHKNIGHT", "Blood", "strength", { "haste", "criticalStrike", "mastery", "versatility" }),
  [251] = scale(251, "DEATHKNIGHT", "Frost", "strength", { "mastery", "criticalStrike", "haste", "versatility" }),
  [252] = scale(252, "DEATHKNIGHT", "Unholy", "strength", { "mastery", "haste", "criticalStrike", "versatility" }),

  [262] = scale(262, "SHAMAN", "Elemental", "intellect", { "haste", "mastery", "criticalStrike", "versatility" }),
  [263] = scale(263, "SHAMAN", "Enhancement", "agility", { "haste", "mastery", "criticalStrike", "versatility" }),
  [264] = scale(264, "SHAMAN", "Restoration", "intellect", { "criticalStrike", "haste", "versatility", "mastery" }),

  [62] = scale(62, "MAGE", "Arcane", "intellect", { "mastery", "haste", "criticalStrike", "versatility" }),
  [63] = scale(63, "MAGE", "Fire", "intellect", { "haste", "criticalStrike", "versatility", "mastery" }),
  [64] = scale(64, "MAGE", "Frost", "intellect", { "criticalStrike", "haste", "mastery", "versatility" }),

  [265] = scale(265, "WARLOCK", "Affliction", "intellect", { "haste", "mastery", "criticalStrike", "versatility" }),
  [266] = scale(266, "WARLOCK", "Demonology", "intellect", { "haste", "mastery", "criticalStrike", "versatility" }),
  [267] = scale(267, "WARLOCK", "Destruction", "intellect", { "haste", "criticalStrike", "mastery", "versatility" }),

  [268] = scale(268, "MONK", "Brewmaster", "agility", { "versatility", "criticalStrike", "mastery", "haste" }),
  [269] = scale(269, "MONK", "Windwalker", "agility", { "mastery", "criticalStrike", "versatility", "haste" }),
  [270] = scale(270, "MONK", "Mistweaver", "intellect", { "haste", "criticalStrike", "versatility", "mastery" }),

  [102] = scale(102, "DRUID", "Balance", "intellect", { "mastery", "haste", "criticalStrike", "versatility" }),
  [103] = scale(103, "DRUID", "Feral", "agility", { "mastery", "criticalStrike", "haste", "versatility" }),
  [104] = scale(104, "DRUID", "Guardian", "agility", { "versatility", "mastery", "haste", "criticalStrike" }),
  [105] = scale(105, "DRUID", "Restoration", "intellect", { "haste", "mastery", "criticalStrike", "versatility" }),

  [577] = scale(577, "DEMONHUNTER", "Havoc", "agility", { "criticalStrike", "mastery", "haste", "versatility" }),
  [581] = scale(581, "DEMONHUNTER", "Vengeance", "agility", { "haste", "versatility", "criticalStrike", "mastery" }),

  [1467] = scale(1467, "EVOKER", "Devastation", "intellect", { "criticalStrike", "mastery", "haste", "versatility" }),
  [1468] = scale(1468, "EVOKER", "Preservation", "intellect", { "criticalStrike", "haste", "versatility", "mastery" }),
  [1473] = scale(1473, "EVOKER", "Augmentation", "intellect", { "mastery", "criticalStrike", "haste", "versatility" }),
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

function Defaults.Get(specID)
  local scale = Defaults.Scales[tonumber(specID)]
  if not scale then return nil end
  return copy(scale)
end

function Defaults.List()
  local out = {}
  for specID, scaleValue in pairs(Defaults.Scales) do
    out[#out + 1] = copy(scaleValue)
  end
  table.sort(out, function(a, b)
    return tonumber(a.meta and a.meta.specID or 0) < tonumber(b.meta and b.meta.specID or 0)
  end)
  return out
end

function Defaults.SpecsForClass(classFile)
  return Defaults.Classes[classFile] or {}
end
