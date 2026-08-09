-- Policies/EvaluationContext/DualWieldOverride.lua
-- Ports the live IsDualWielding() override that policyForSpec() layers on
-- top of its static per-spec table (Gear/Weapons.lua:101-103): any spec can
-- end up dual-wielding at runtime (e.g. via a temporary buff), and that
-- fact should win over the static class/spec default. Kept as its own
-- policy, ordered after ClassSpecWeaponCapabilities via requires, rather
-- than folded into it -- this is a live-state check, the other is a pure
-- static lookup, and doc 5.4 treats "checking a specific state that
-- materially affects equipment legality" as its own resolvable fact.
--
-- This policy both requires AND provides the two capabilities it can
-- overwrite -- requires so it orders after ClassSpecWeaponCapabilities
-- (the initial provider), provides so that a THIRD policy which only
-- requires these capabilities also orders after this override, not just
-- after the initial provider. Without re-declaring provides here, the
-- resolver's dependency graph would have no idea this policy touches
-- those values at all -- a downstream consumer would only get an edge
-- from ClassSpecWeaponCapabilities and could legally run before this
-- override, seeing the pre-override value on an unlucky registration
-- order.
--
-- IMPORTANT: this "require and re-provide the same token" pattern
-- supports exactly one transformer per token -- Resolver.lua's
-- topoSortPhase deliberately rejects a *second* same-phase transformer of
-- "capability.XIVEquip.allow_dual_wield" (or allow_offhand_weapon) with a
-- clear error, rather than silently forming a dependency cycle or picking
-- an order based on incidental registration timing. If a future policy
-- ever needs to layer a second transformation on top of this one, it
-- should require a distinct output token this policy would need to grow
-- (e.g. "capability.XIVEquip.allow_dual_wield.live", still setting the
-- same "XIVEquip.allow_dual_wield" capability key on the builder -- the
-- provides token is only a graph-ordering label, not the actual
-- capability name), not re-declare the same token this policy already
-- transforms.
local addonName, XIVEquip = ...

XIVEquip:RegisterPolicy({
  id = "XIVEquip.dual_wield_live_override",
  phase = "evaluation_context",
  requires = {
    "capability.XIVEquip.allow_dual_wield",
    "capability.XIVEquip.allow_offhand_weapon",
  },
  provides = {
    "capability.XIVEquip.allow_dual_wield",
    "capability.XIVEquip.allow_offhand_weapon",
  },
  apply = function(builder, runtime)
    if runtime.IsDualWielding and runtime.IsDualWielding() then
      builder:SetCapability("XIVEquip.allow_dual_wield", true)
      builder:SetCapability("XIVEquip.allow_offhand_weapon", true)
    end
  end,
})
