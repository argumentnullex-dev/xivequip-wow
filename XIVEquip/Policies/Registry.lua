-- Policies/Registry.lua
-- Pending policy declarations (architecture proposal doc section 15.7-15.9).
-- This is runtime state, not a SavedVariables/settings-cache structure
-- (15.8) -- it only ever holds executable declarations supplied by addon
-- code at load time, rebuilt fresh every UI load.
--
-- Registration does only enough validation to reject an obviously malformed
-- declaration (15.7); the expensive checks (duplicate ids, missing
-- requires/provides, dependency cycles, deterministic ordering) happen once,
-- centrally, in Policies/Resolver.lua's Finalize -- not here, and not on
-- every registration call.
local addonName, XIVEquip = ...
XIVEquip.Policies = XIVEquip.Policies or {}
local Policies = XIVEquip.Policies

local Registry = {}
Policies.Registry = Registry

local Methods = {}
local RegistryMT = { __index = Methods }

function Registry.New()
  return setmetatable({ pending = {}, locked = false }, RegistryMT)
end

-- isStringArray: rejects anything that isn't a clean 1..N array of
-- strings -- not just "every value ipairs visits is a string" (ipairs
-- silently ignores non-array keys and stops at the first hole, so
-- {foo="x"} or a sparse {[1]="x",[3]="y"} would otherwise pass validation
-- while quietly losing data later).
local function isStringArray(value)
  if value == nil then return true end
  if type(value) ~= "table" then return false end

  local count = 0
  for _ in pairs(value) do count = count + 1 end

  for i = 1, count do
    if type(value[i]) ~= "string" then return false end
  end

  -- The loop above already confirms indices 1..count hold strings; this
  -- confirms there's nothing else in the table (a hole plus an
  -- out-of-range key could otherwise still total `count` pairs).
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key > count or key % 1 ~= 0 then
      return false
    end
  end

  return true
end

-- snapshotDeclaration(decl) -> a frozen, XIVEquip-owned copy of decl.
-- Register() stores and returns this copy, never the caller's own table --
-- otherwise a caller could mutate `policy.apply` (or anything else) on
-- their original table *after* the registry finalizes and locks, and
-- since the resolved phase arrays would still be holding that same object
-- by reference, the "resolved once, then only iterated" guarantee (doc
-- 15.10) would be fiction. table.freeze on the caller's own table isn't a
-- substitute for this: Retail restricts freezing a table to the addon
-- that created it, so XIVEquip can't freeze a third party's declaration
-- table even if it wanted to -- copying is the only mechanism that works
-- for every caller.
--
-- Copies EVERY field on decl, not just the ones this file's own
-- validation understands (id/phase/apply/requires/provides). A phase this
-- module knows nothing about is free to define its own extra declaration
-- fields (e.g. Phase 3's assignment-phase policies use `groups` to scope
-- which assignment group they apply to) -- if this only copied a fixed
-- allowlist, any such field would be silently dropped from the snapshot,
-- and a consumer reading it back (e.g. Assignments/Paired.lua checking
-- `policy.groups`) would see it as nil/absent and misinterpret the policy
-- (a policy meant for one group would look like it applies to every
-- group). Deep-copies+freezes table-valued fields for the same protection
-- requires/provides already get; scalars and functions are copied as-is.
local function copyValue(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for k, v in pairs(value) do copy[k] = copyValue(v) end
  return table.freeze(copy)
end

local KNOWN_FIELDS = { id = true, phase = true, apply = true, requires = true, provides = true }

local function snapshotDeclaration(decl)
  local snapshot = {
    id = decl.id,
    phase = decl.phase,
    apply = decl.apply,
    requires = copyValue(decl.requires),
    provides = copyValue(decl.provides),
  }
  for key, value in pairs(decl) do
    if not KNOWN_FIELDS[key] then
      snapshot[key] = copyValue(value)
    end
  end
  return table.freeze(snapshot)
end

-- Register(decl) -> a frozen snapshot of decl (see snapshotDeclaration --
-- NOT the same table the caller passed in). Raises for an obviously
-- malformed declaration; duplicate-id detection happens at Finalize, not
-- here (multiple pending declarations may legitimately share an id right
-- up until finalization -- e.g. a third party registering before deciding
-- whether to also register a conflicting one under the same id is still
-- just "pending" data).
function Methods:Register(decl)
  assert(not self.locked,
    "RegisterPolicy called after the registry was finalized -- policies must register before PLAYER_LOGIN")
  assert(type(decl) == "table", "RegisterPolicy requires a declaration table")
  assert(type(decl.id) == "string" and decl.id ~= "", "policy declaration requires a non-empty string id")
  assert(type(decl.phase) == "string" and decl.phase ~= "", "policy declaration '" .. tostring(decl.id) .. "' requires a phase")
  assert(type(decl.apply) == "function", "policy declaration '" .. tostring(decl.id) .. "' requires an apply function")
  assert(isStringArray(decl.requires), "policy declaration '" .. tostring(decl.id) .. "': requires must be an array of strings")
  assert(isStringArray(decl.provides), "policy declaration '" .. tostring(decl.id) .. "': provides must be an array of strings")
  -- `groups` (Assignments/Paired.lua's assignment-group scoping field) is
  -- ordinary policy metadata as far as the registry is concerned -- not
  -- every phase uses it, but whenever it's present it must be a clean
  -- string array for the same reason requires/provides must be: a bare
  -- string would break assignmentPoliciesFor's `ipairs(policy.groups)`,
  -- and a map like {weapons=true} would silently iterate zero entries
  -- (via ipairs) rather than fail loudly, making the policy look like it
  -- applies to no group instead of rejecting the malformed declaration.
  assert(isStringArray(decl.groups), "policy declaration '" .. tostring(decl.id) .. "': groups must be an array of strings")

  local snapshot = snapshotDeclaration(decl)
  self.pending[#self.pending + 1] = snapshot
  return snapshot
end

-- Pending() -> array of declarations, in registration order.
function Methods:Pending()
  return self.pending
end

-- Lock() -> closes registration permanently (doc 15.9: "After normal addon
-- loading has completed, XIVEquip should finalize the registry before any
-- equipment evaluation is allowed"). Called once, at PLAYER_LOGIN (see
-- XIVEquip.lua), after every normal addon -- including third-party
-- extensions declaring XIVEquip as a dependency -- has had the chance to
-- load and register. A late RegisterPolicy call after this point is a
-- programming error in the caller (registering too late to ever run), not
-- something to silently accept into a pending list nothing will ever look
-- at again.
function Methods:Lock()
  self.locked = true
end

function Methods:IsLocked()
  return self.locked
end
