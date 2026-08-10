-- XIVWeights/Builtin/Defaults.lua
-- Built-in spec scale templates. These are source-controlled defaults, not
-- user settings. XIVWeights.Config can create editable SavedVariables copies
-- on demand and can reset those copies from this table.
local addonName, XIVEquip = ...
XIVEquip.XIVWeights = XIVEquip.XIVWeights or {}
XIVEquip.XIVWeights.Builtin = XIVEquip.XIVWeights.Builtin or {}
local XIVWeights = XIVEquip.XIVWeights

local Defaults = {}
XIVWeights.Builtin.Defaults = Defaults

Defaults.Version = 3

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
    { id = 1480, name = "Devourer" },
  },
  EVOKER = {
    { id = 1467, name = "Devastation" },
    { id = 1468, name = "Preservation" },
    { id = 1473, name = "Augmentation" },
  },
}

local function weights(primary, priority, opts)
  local out = {}
  opts = opts or {}
  if opts.weaponDps == "abovePrimary" then
    out.weaponDps = 1.0
    out[primary] = 0.9
  elseif opts.weaponDps == "withPrimary" then
    out.weaponDps = 1.0
    out[primary] = 1.0
  else
    out[primary] = 1.0
  end
  local value = 0.5
  for _, entry in ipairs(priority or {}) do
    if type(entry) == "table" then
      for _, feature in ipairs(entry) do out[feature] = value end
    else
      out[entry] = value
    end
    value = value - 0.1
    if value < 0.1 then value = 0.1 end
  end
  return out
end

local function source(specID, url)
  return {
    kind = "xivequip-default",
    specID = specID,
    defaultVersion = Defaults.Version,
    reviewedAt = "2026-08-10",
    guide = url,
    refresh = "tools/default-scales/refresh-prompt.md",
  }
end

local function scale(specID, classFile, specName, primary, priority, guide, opts)
  return XIVWeights.NewScale({
    id = "default:spec:" .. tostring(specID),
    name = specName,
    source = source(specID, guide),
    weights = weights(primary, priority, opts),
    meta = {
      specID = specID,
      classFile = classFile,
      specName = specName,
      primary = primary,
      defaultVersion = Defaults.Version,
      priority = priority,
      guide = guide,
      weaponDpsPriority = opts and opts.weaponDps or nil,
    },
  })
end

Defaults.Scales = {
  [71] = scale(71, "WARRIOR", "Arms", "strength", { "criticalStrike", "haste", "mastery", "versatility" }, "https://www.wowhead.com/guide/classes/warrior/arms/stat-priority-pve-dps", { weaponDps = "withPrimary" }),
  [72] = scale(72, "WARRIOR", "Fury", "strength", { "haste", "mastery", "criticalStrike", "versatility" }, "https://www.wowhead.com/guide/classes/warrior/fury/stat-priority-pve-dps", { weaponDps = "withPrimary" }),
  [73] = scale(73, "WARRIOR", "Protection", "strength", { "haste", "criticalStrike", "versatility", "mastery" }, "https://www.wowhead.com/guide/classes/warrior/protection/stat-priority-pve-tank"),

  [65] = scale(65, "PALADIN", "Holy", "intellect", { "mastery", { "haste", "criticalStrike" }, "versatility" }, "https://www.wowhead.com/guide/classes/paladin/holy/overview-pve-healer"),
  [66] = scale(66, "PALADIN", "Protection", "strength", { "haste", "versatility", "mastery", "criticalStrike" }, "https://www.wowhead.com/guide/classes/paladin/protection/stat-priority-pve-tank"),
  [70] = scale(70, "PALADIN", "Retribution", "strength", { "mastery", "criticalStrike", "haste", "versatility" }, "https://www.wowhead.com/guide/classes/paladin/retribution/stat-priority-pve-dps"),

  [253] = scale(253, "HUNTER", "Beast Mastery", "agility", { "mastery", "criticalStrike", "haste", "versatility" }, "https://www.wowhead.com/guide/classes/hunter/beast-mastery/stat-priority-pve-dps", { weaponDps = "abovePrimary" }),
  [254] = scale(254, "HUNTER", "Marksmanship", "agility", { "criticalStrike", "mastery", "versatility", "haste" }, "https://www.wowhead.com/guide/classes/hunter/marksmanship/stat-priority-pve-dps"),
  [255] = scale(255, "HUNTER", "Survival", "agility", { "mastery", { "criticalStrike", "haste" }, "versatility" }, "https://www.wowhead.com/guide/classes/hunter/survival/overview-pve-dps"),

  [259] = scale(259, "ROGUE", "Assassination", "agility", { "criticalStrike", "haste", "mastery", "versatility" }, "https://www.wowhead.com/guide/classes/rogue/assassination/overview-pve-dps"),
  [260] = scale(260, "ROGUE", "Outlaw", "agility", { "haste", { "criticalStrike", "versatility" }, "mastery" }, "https://www.wowhead.com/guide/classes/rogue/outlaw/overview-pve-dps"),
  [261] = scale(261, "ROGUE", "Subtlety", "agility", { "mastery", "haste", "criticalStrike", "versatility" }, "https://www.wowhead.com/guide/classes/rogue/subtlety/stat-priority-pve-dps"),

  [256] = scale(256, "PRIEST", "Discipline", "intellect", { "haste", "criticalStrike", "mastery", "versatility" }, "https://www.wowhead.com/guide/classes/priest/discipline/stat-priority-pve-healer"),
  [257] = scale(257, "PRIEST", "Holy", "intellect", { "criticalStrike", { "versatility", "mastery" }, "haste" }, "https://www.wowhead.com/guide/classes/priest/holy/overview-pve-healer"),
  [258] = scale(258, "PRIEST", "Shadow", "intellect", { "haste", "mastery", "criticalStrike", "versatility" }, "https://www.wowhead.com/guide/classes/priest/shadow/overview-pve-dps"),

  [250] = scale(250, "DEATHKNIGHT", "Blood", "strength", { "criticalStrike", "mastery", "versatility", "haste" }, "https://www.wowhead.com/guide/classes/death-knight/blood/basics"),
  [251] = scale(251, "DEATHKNIGHT", "Frost", "strength", { "criticalStrike", "mastery", "haste", "versatility" }, "https://www.wowhead.com/guide/classes/death-knight/frost/basics"),
  [252] = scale(252, "DEATHKNIGHT", "Unholy", "strength", { "criticalStrike", "mastery", "haste", "versatility" }, "https://www.wowhead.com/guide/classes/death-knight/unholy/basics"),

  [262] = scale(262, "SHAMAN", "Elemental", "intellect", { "mastery", { "criticalStrike", "haste" }, "versatility" }, "https://www.wowhead.com/guide/classes/shaman/elemental/overview-pve-dps"),
  [263] = scale(263, "SHAMAN", "Enhancement", "agility", { "mastery", "haste", "criticalStrike", "versatility" }, "https://www.wowhead.com/guide/classes/shaman/enhancement/overview-pve-dps"),
  [264] = scale(264, "SHAMAN", "Restoration", "intellect", { "criticalStrike", { "versatility", "mastery", "haste" } }, "https://www.wowhead.com/guide/classes/shaman/restoration/stat-priority-pve-healer"),

  [62] = scale(62, "MAGE", "Arcane", "intellect", { "mastery", "haste", "criticalStrike", "versatility" }, "https://www.wowhead.com/guide/classes/mage/arcane/stat-priority-pve-dps"),
  [63] = scale(63, "MAGE", "Fire", "intellect", { "haste", "mastery", "versatility", "criticalStrike" }, "https://www.wowhead.com/guide/classes/mage/fire/stat-priority-pve-dps"),
  [64] = scale(64, "MAGE", "Frost", "intellect", { "mastery", "criticalStrike", "haste", "versatility" }, "https://www.wowhead.com/guide/classes/mage/frost/stat-priority-pve-dps"),

  [265] = scale(265, "WARLOCK", "Affliction", "intellect", { "haste", "criticalStrike", "versatility", "mastery" }, "https://www.wowhead.com/guide/classes/warlock/affliction/overview-pve-dps"),
  [266] = scale(266, "WARLOCK", "Demonology", "intellect", { { "haste", "criticalStrike" }, "mastery", "versatility" }, "https://www.wowhead.com/guide/classes/warlock/demonology/stat-priority-pve-dps"),
  [267] = scale(267, "WARLOCK", "Destruction", "intellect", { "haste", { "mastery", "criticalStrike" }, "versatility" }, "https://www.wowhead.com/guide/classes/warlock/destruction/stat-priority-pve-dps"),

  [268] = scale(268, "MONK", "Brewmaster", "agility", { { "versatility", "criticalStrike", "mastery" }, "haste" }, "https://www.wowhead.com/guide/classes/monk/brewmaster/stat-priority-pve-tank"),
  [269] = scale(269, "MONK", "Windwalker", "agility", { "haste", { "criticalStrike", "mastery" }, "versatility" }, "https://www.wowhead.com/guide/classes/monk/windwalker/overview-pve-dps"),
  [270] = scale(270, "MONK", "Mistweaver", "intellect", { "haste", "criticalStrike", "versatility", "mastery" }, "https://www.wowhead.com/guide/classes/monk/mistweaver/overview-pve-healer"),

  [102] = scale(102, "DRUID", "Balance", "intellect", { "mastery", { "criticalStrike", "haste" }, "versatility" }, "https://www.wowhead.com/guide/classes/druid/balance/overview-pve-dps"),
  [103] = scale(103, "DRUID", "Feral", "agility", { "mastery", { "haste", "criticalStrike" }, "versatility" }, "https://www.wowhead.com/guide/classes/druid/feral/stat-priority-pve-dps"),
  [104] = scale(104, "DRUID", "Guardian", "agility", { "haste", "versatility", { "mastery", "criticalStrike" } }, "https://www.wowhead.com/guide/classes/druid/guardian/overview-pve-tank"),
  [105] = scale(105, "DRUID", "Restoration", "intellect", { "haste", "mastery", "criticalStrike", "versatility" }, "https://www.wowhead.com/guide/classes/druid/restoration/stat-priority-pve-healer"),

  [577] = scale(577, "DEMONHUNTER", "Havoc", "agility", { "criticalStrike", "mastery", "haste", "versatility" }, "https://www.wowhead.com/guide/classes/demon-hunter/havoc/stat-priority-pve-dps"),
  [581] = scale(581, "DEMONHUNTER", "Vengeance", "agility", { "haste", "versatility", "criticalStrike", "mastery" }, "https://www.wowhead.com/guide/classes/demon-hunter/vengeance/basics"),
  [1480] = scale(1480, "DEMONHUNTER", "Devourer", "intellect", { "haste", "mastery", "criticalStrike", "versatility" }, "https://www.wowhead.com/guide/classes/demon-hunter/devourer/basics"),

  [1467] = scale(1467, "EVOKER", "Devastation", "intellect", { "criticalStrike", { "haste", "mastery" }, "versatility" }, "https://www.wowhead.com/guide/classes/evoker/devastation/overview-pve-dps"),
  [1468] = scale(1468, "EVOKER", "Preservation", "intellect", { "mastery", "criticalStrike", "haste", "versatility" }, "https://www.wowhead.com/guide/classes/evoker/preservation/stat-priority-pve-healer"),
  [1473] = scale(1473, "EVOKER", "Augmentation", "intellect", { "criticalStrike", "haste", "mastery", "versatility" }, "https://www.wowhead.com/guide/classes/evoker/augmentation/basics"),
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

function Defaults.ClassForSpec(specID)
  specID = tonumber(specID)
  for classFile, specs in pairs(Defaults.Classes) do
    for _, spec in ipairs(specs) do
      if spec.id == specID then return classFile end
    end
  end
  return nil
end

function Defaults.PrimaryForSpec(specID)
  local scaleValue = Defaults.Scales[tonumber(specID)]
  return scaleValue and scaleValue.meta and scaleValue.meta.primary or nil
end
