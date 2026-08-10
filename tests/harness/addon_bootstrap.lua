-- tests/harness/addon_bootstrap.lua
-- Loads production XIVEquip modules into a fresh addon table, mirroring the
-- WoW `local addonName, ns = ...` chunk convention every production file uses.
-- Split into phases so callers (ScenarioRunner) can patch the addon table
-- between phases -- e.g. installing fake Comparers/Settings/L and patching
-- Core.equipByBasics before Gear/Interface.lua loads and captures it as an
-- upvalue.

local Bootstrap = {}
local sep = package.config:sub(1, 1)
local unpack = table.unpack or unpack

local function join(...)
  return table.concat({ ... }, sep)
end

local function loadAddonFile(root, parts, addon)
  local chunk = assert(loadfile(join(root, "XIVEquip", unpack(parts))))
  chunk("XIVEquip", addon)
end

-- Global/Constants.lua + Core/GearCore.lua. Every other production module
-- depends on XIVEquip.Const / XIVEquip.Gear_Core being set first.
function Bootstrap.LoadCore(root, addon)
  loadAddonFile(root, { "Global", "Constants.lua" }, addon)
  loadAddonFile(root, { "Core", "GearCore.lua" }, addon)
end

-- The three per-category planners. None of these need Comparers/Settings/L.
function Bootstrap.LoadPlanners(root, addon)
  loadAddonFile(root, { "Gear", "Weapons.lua" }, addon)
  loadAddonFile(root, { "Gear", "Jewelry.lua" }, addon)
  loadAddonFile(root, { "Gear", "Armor.lua" }, addon)
end

-- Gear/Interface.lua captures L/Comparers/Settings/Core.equipByBasics as
-- upvalues at load time -- callers that need Gear:EquipBest must patch the
-- addon table with fakes for those before calling this.
function Bootstrap.LoadInterface(root, addon)
  loadAddonFile(root, { "Gear", "Interface.lua" }, addon)
end

-- The native XIVWeights valuation module tree. Self-contained -- doesn't
-- need Const/Gear_Core/Comparers/Settings, so it can be loaded in isolation
-- for unit tests that never touch the planner stack.
function Bootstrap.LoadWeights(root, addon)
  loadAddonFile(root, { "XIVWeights", "Model.lua" }, addon)
  loadAddonFile(root, { "XIVWeights", "Normalizer.lua" }, addon)
  loadAddonFile(root, { "XIVWeights", "Scorer.lua" }, addon)
  loadAddonFile(root, { "XIVWeights", "Repository.lua" }, addon)
  loadAddonFile(root, { "XIVWeights", "Resolver.lua" }, addon)
  loadAddonFile(root, { "XIVWeights", "Builtin", "Defaults.lua" }, addon)
  loadAddonFile(root, { "XIVWeights", "Config.lua" }, addon)
  loadAddonFile(root, { "XIVWeights", "Providers", "Default.lua" }, addon)
  loadAddonFile(root, { "XIVWeights", "Providers", "Manual.lua" }, addon)
  loadAddonFile(root, { "XIVWeights", "Providers", "Pawn.lua" }, addon)
  loadAddonFile(root, { "XIVWeights", "Import", "Pawn.lua" }, addon)
end

-- The policy registry + EvaluationContext + candidate normalization tree.
-- Self-contained like LoadWeights -- doesn't touch Gear_Core/Comparers.
-- Load order matters: Registry before PublicAPI (XIVEquip:RegisterPolicy
-- delegates to it), PublicAPI before the built-in EvaluationContext
-- policies (each self-registers via XIVEquip:RegisterPolicy at load time),
-- and Resolver before ContextBuilder (which calls Resolver.Freeze).
function Bootstrap.LoadPolicyContext(root, addon)
  loadAddonFile(root, { "Policies", "Registry.lua" }, addon)
  loadAddonFile(root, { "PublicAPI", "Policies.lua" }, addon)
  loadAddonFile(root, { "Policies", "Resolver.lua" }, addon)
  loadAddonFile(root, { "Policies", "EvaluationContext", "CharacterIdentity.lua" }, addon)
  loadAddonFile(root, { "Policies", "EvaluationContext", "ArmorProficiency.lua" }, addon)
  loadAddonFile(root, { "Policies", "EvaluationContext", "ClassSpecWeaponCapabilities.lua" }, addon)
  loadAddonFile(root, { "Policies", "EvaluationContext", "DualWieldOverride.lua" }, addon)
  loadAddonFile(root, { "Policies", "EvaluationContext", "WeightsResolution.lua" }, addon)
  loadAddonFile(root, { "Policies", "Candidate", "RequiredLevel.lua" }, addon)
  loadAddonFile(root, { "Policies", "Candidate", "Equippable.lua" }, addon)
  loadAddonFile(root, { "Policies", "Candidate", "ArmorProficiency.lua" }, addon)
  loadAddonFile(root, { "Policies", "Candidate", "JewelryIlvlFloor.lua" }, addon)
  loadAddonFile(root, { "Evaluation", "ContextBuilder.lua" }, addon)
  loadAddonFile(root, { "Evaluation", "CandidateNormalizer.lua" }, addon)
  loadAddonFile(root, { "Evaluation", "CandidateCollector.lua" }, addon)
  loadAddonFile(root, { "Evaluation", "CandidateEvaluator.lua" }, addon)
end

-- The generic paired-assignment solver tree. LoadoutState/Paired/Frontier/
-- Groups are self-contained (no registry dependency), but
-- Policies/Assignment/WeaponHandLegality.lua self-registers via
-- XIVEquip:RegisterPolicy at load time, same as the built-in
-- EvaluationContext policies -- callers must run Bootstrap.LoadPolicyContext
-- first, or that one file's load will fail. Frontier.lua must load before
-- Groups.lua, which captures `Assignments.Frontier` into a local upvalue
-- at load time.
function Bootstrap.LoadAssignments(root, addon)
  loadAddonFile(root, { "Assignments", "LoadoutState.lua" }, addon)
  loadAddonFile(root, { "Assignments", "Paired.lua" }, addon)
  loadAddonFile(root, { "Assignments", "Frontier.lua" }, addon)
  loadAddonFile(root, { "Assignments", "Singleton.lua" }, addon)
  loadAddonFile(root, { "Assignments", "Groups.lua" }, addon)
  loadAddonFile(root, { "Policies", "Assignment", "WeaponHandLegality.lua" }, addon)
end

-- The whole-loadout optimizer. Depends only on Assignments.LoadoutState's
-- CheckAssignment contract (not on Groups/Frontier directly), but callers
-- combining real group frontiers still need Bootstrap.LoadAssignments too.
function Bootstrap.LoadOptimization(root, addon)
  loadAddonFile(root, { "Optimization", "LoadoutOptimizer.lua" }, addon)
end

function Bootstrap.LoadPlanning(root, addon)
  loadAddonFile(root, { "Planning", "Runtime.lua" }, addon)
  loadAddonFile(root, { "Planning", "Coordinator.lua" }, addon)
  loadAddonFile(root, { "Planning", "PlanBuilder.lua" }, addon)
end

return Bootstrap
