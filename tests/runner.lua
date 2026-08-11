local root = arg and arg[1] or "."
root = root:gsub("[/\\]+$", "")

local sep = package.config:sub(1, 1)
local function join(...)
  return table.concat({ ... }, sep)
end

-- table.freeze is a WoW client extension (added in retail 12.x, which this
-- addon's .toc targets) -- Policies/Resolver.lua calls it unconditionally,
-- assuming the real client's native implementation. This plain-Lua runner
-- has no such thing, so specs need a stand-in, same as fake_world.lua
-- stands in for other WoW-only globals. This polyfill is a metatable
-- proxy: reads (direct indexing, ipairs, and -- since this Lua build is
-- 5.4 -- `#` via __len) work correctly, but pairs() does NOT (its raw
-- backing table is always empty), unlike the real table.freeze, which has
-- no such limitation. Don't write a test that pairs() over a frozen value
-- -- that's a test-polyfill artifact, not something to codify.
if type(table.freeze) ~= "function" then
  function table.freeze(source)
    return setmetatable({}, {
      __index = source,
      __len = function() return #source end,
      __newindex = function(_, key, _)
        error("attempt to mutate a frozen value (key '" .. tostring(key) .. "')", 2)
      end,
      __metatable = false,
    })
  end
end

local specs = {
  "comparer_spec",
  "planning_runtime_spec",
  "planning_plan_builder_spec",
  "command_router_compare_spec",
  "settings_spec",
  "settings_window_spec",
  "weapons_spec",
  "paired_slots_spec",
  "equip_execution_spec",
  "fixture_spec",
  "black_box_scenario_spec",
  "weapon_archetype_scenario_spec",
  "paired_slot_scenario_spec",
  "coordinator_scenario_spec",
  "xivweights_model_spec",
  "xivweights_normalizer_spec",
  "xivweights_scorer_spec",
  "xivweights_repository_spec",
  "xivweights_resolver_spec",
  "xivweights_config_spec",
  "xivweights_import_spec",
  "integrations_registry_spec",
  "xivweights_manual_provider_spec",
  "xivweights_pawn_provider_spec",
  "policy_registry_spec",
  "policy_resolver_spec",
  "evaluation_context_builder_spec",
  "xivweights_context_policies_spec",
  "candidate_normalizer_spec",
  "candidate_collector_spec",
  "candidate_evaluator_spec",
  "profile_preferences_policy_spec",
  "evaluation_context_pipeline_spec",
  "assignment_loadout_state_spec",
  "assignment_paired_spec",
  "assignment_singleton_spec",
  "weapon_hand_legality_policy_spec",
  "assignment_groups_cross_validation_spec",
  "assignment_frontier_spec",
  "loadout_optimizer_spec",
  "planning_coordinator_spec",
}

local total, failed, skipped = 0, 0, 0

for _, specName in ipairs(specs) do
  local specPath = join(root, "tests", "specs", specName .. ".lua")
  local chunk, err = loadfile(specPath)
  if not chunk then
    io.stderr:write(err .. "\n")
    os.exit(1)
  end

  local tests = chunk(root)
  for _, test in ipairs(tests) do
    if test.skip then
      skipped = skipped + 1
      io.write("[SKIP] " .. test.name .. (test.reason and (" - " .. test.reason) or "") .. "\n")
    else
      total = total + 1
      local ok, testErr = xpcall(test.fn, debug.traceback)
      if ok then
        io.write("[PASS] " .. test.name .. "\n")
      else
        failed = failed + 1
        io.stderr:write("[FAIL] " .. test.name .. "\n" .. tostring(testErr) .. "\n")
      end
    end
  end
end

io.write(string.format("%d tests, %d failed, %d skipped\n", total, failed, skipped))
if failed > 0 then os.exit(1) end
