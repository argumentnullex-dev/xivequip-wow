-- PublicAPI/Policies.lua
-- The stable public extensibility surface (doc section 15.7): built-in and
-- third-party policies register through this exact same function. Internally
-- it's a thin delegate to Policies/Registry.lua -- this file's only job is
-- to be the one place `XIVEquip:RegisterPolicy` is defined, so third-party
-- addons have a single, stable entrypoint independent of internal registry
-- structure.
--
-- `XIVEquip` here is this addon's private addon-local table (the second
-- vararg every file gets from `local addonName, XIVEquip = ...`) -- it is
-- NOT a global, so a third-party addon cannot reach `RegisterPolicy` just
-- by naming XIVEquip. The supported way in for another addon is:
--   C_AddOns.GetAddOnLocalTable("XIVEquip"):RegisterPolicy({ ... })
-- which only returns that table when XIVEquip.toc declares
-- `## AllowAddOnTableAccess: 1` (set there -- see XIVEquip.toc). No global
-- is introduced here specifically to keep that single, documented entry
-- point as the only way in, rather than polluting _G.
local addonName, XIVEquip = ...
XIVEquip.Policies = XIVEquip.Policies or {}
XIVEquip.Policies.Registry = XIVEquip.Policies.Registry or {}

-- The default registry instance built-in policy files register into at load
-- time. A caller assembling its own addon table for a test (see
-- tests/harness/addon_bootstrap.lua) gets a fresh one per Bootstrap.LoadPolicyContext
-- call, since this line runs again against that fresh `addon` table.
XIVEquip.Policies.DefaultRegistry = XIVEquip.Policies.Registry.New()

function XIVEquip:RegisterPolicy(decl)
  return self.Policies.DefaultRegistry:Register(decl)
end
