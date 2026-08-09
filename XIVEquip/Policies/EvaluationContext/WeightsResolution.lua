-- Policies/EvaluationContext/WeightsResolution.lua
-- Doc section 5.5: "the selected Provider and the effective XIVWeights
-- scale should be resolved during context construction by context
-- policies." Which Provider + selection is actually configured is a
-- Settings-UI concern deferred past 2.0 parity (see Phase 2 plan's scope
-- decisions) -- this policy just calls whatever the injected runtime
-- provides, so real wiring later is a matter of supplying a real
-- `runtime.ResolveWeights`, not touching this file.
local addonName, XIVEquip = ...

XIVEquip:RegisterPolicy({
  id = "XIVEquip.weights_resolution",
  phase = "evaluation_context",
  provides = { "weights" },
  apply = function(builder, runtime)
    if runtime.ResolveWeights then
      builder:Set("weights", runtime.ResolveWeights(builder))
    end
  end,
})
