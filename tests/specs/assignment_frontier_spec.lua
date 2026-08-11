-- tests/specs/assignment_frontier_spec.lua
-- Assignments/Frontier.lua: safe dominance pruning (doc section 23).

local root = ...
local sep = package.config:sub(1, 1)
local A = dofile(root .. sep .. "tests" .. sep .. "assertions.lua")
local Bootstrap = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "addon_bootstrap.lua")

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function newAddon()
  local addon = {}
  -- LoadAssignments also loads Policies/Assignment/WeaponHandLegality.lua,
  -- which self-registers via XIVEquip:RegisterPolicy at load time -- so
  -- PublicAPI/Policies.lua must already be loaded.
  Bootstrap.LoadPolicyContext(root, addon)
  Bootstrap.LoadAssignments(root, addon)
  return addon
end

local function candidate(uniqueKey, uniqueLimit)
  return { uniqueness = { key = uniqueKey, limit = uniqueLimit } }
end

local function assignment(score, picks)
  return { score = score, picks = picks or {} }
end

local function invalidAssignment(score, picks)
  local a = assignment(score, picks)
  a.policyValid = false
  return a
end

test("UniqueUsage counts each non-empty pick's uniqueness key and records its limit", function()
  local addon = newAddon()
  local a = assignment(10, { first = candidate("item:1", 1), second = candidate("item:2", 1) })

  local usage = addon.Assignments.Frontier.UniqueUsage(a)

  A.equal(usage["item:1"].count, 1)
  A.equal(usage["item:1"].limit, 1)
  A.equal(usage["item:2"].count, 1)
  A.equal(usage["item:2"].limit, 1)
end)

test("UniqueUsage ignores picks with no uniqueness key", function()
  local addon = newAddon()
  local a = assignment(10, { first = { uniqueness = {} }, second = nil })

  local usage = addon.Assignments.Frontier.UniqueUsage(a)

  A.same(usage, {})
end)

test("UniqueUsage counts two picks sharing the same category together", function()
  local addon = newAddon()
  local a = assignment(10, { first = candidate("category:5", 2), second = candidate("category:5", 2) })

  local usage = addon.Assignments.Frontier.UniqueUsage(a)

  A.equal(usage["category:5"].count, 2)
  A.equal(usage["category:5"].limit, 2)
end)

test("UniqueUsage records the tightest limit when its own picks disagree on the same key", function()
  local addon = newAddon()
  local a = assignment(10, { first = candidate("category:5", 2), second = candidate("category:5", 1) })

  local usage = addon.Assignments.Frontier.UniqueUsage(a)

  A.equal(usage["category:5"].limit, 1)
end)

test("a strictly higher score with equal uniqueness usage dominates", function()
  local addon = newAddon()
  local better = assignment(20, { first = candidate("item:1", 1) })
  local worse = assignment(10, { first = candidate("item:1", 1) })

  A.truthy(addon.Assignments.Frontier.Dominates(better, worse))
  A.falsy(addon.Assignments.Frontier.Dominates(worse, better))
end)

test("equal score but strictly less uniqueness usage dominates", function()
  local addon = newAddon()
  local lessUsage = assignment(10, {})
  local moreUsage = assignment(10, { first = candidate("item:1", 1) })

  A.truthy(addon.Assignments.Frontier.Dominates(lessUsage, moreUsage))
  A.falsy(addon.Assignments.Frontier.Dominates(moreUsage, lessUsage))
end)

test("a category the OTHER assignment doesn't touch at all still counts against the one that uses it", function()
  local addon = newAddon()
  -- Both score 10, but `usesExtra` also consumes a category `plain`
  -- doesn't touch at all -- that's a real extra cost, not a neutral
  -- difference, even though a check that only scanned the dominated
  -- side's keys would miss it entirely.
  local plain = assignment(10, {})
  local usesExtra = assignment(10, { first = candidate("item:1", 1) })

  A.truthy(addon.Assignments.Frontier.Dominates(plain, usesExtra))
  A.falsy(addon.Assignments.Frontier.Dominates(usesExtra, plain))
end)

test("equal score and equal usage dominates neither way", function()
  local addon = newAddon()
  local a = assignment(10, { first = candidate("item:1", 1) })
  local b = assignment(10, { first = candidate("item:1", 1) })

  A.falsy(addon.Assignments.Frontier.Dominates(a, b))
  A.falsy(addon.Assignments.Frontier.Dominates(b, a))
end)

test("a higher score does NOT dominate when its own declared limit is more restrictive on a shared key", function()
  local addon = newAddon()
  -- Same key, same count (1 each), but tighter (limit=1) vs. laxer
  -- (limit=2). Count alone would make the higher-scoring one look
  -- strictly better -- it isn't, because keeping it instead of the laxer
  -- one can make an otherwise-legal combination with some OTHER group's
  -- use of the same key illegal (a real counterexample, not a hypothetical:
  -- see loadout_optimizer_spec.lua's matching cross-group test).
  local tighterHigherScore = assignment(20, { first = candidate("cat", 1) })
  local laxerLowerScore = assignment(10, { first = candidate("cat", 2) })

  A.falsy(addon.Assignments.Frontier.Dominates(tighterHigherScore, laxerLowerScore),
    "a strictly more restrictive limit must block domination even with a better score")
  A.falsy(addon.Assignments.Frontier.Dominates(laxerLowerScore, tighterHigherScore),
    "the lower score also isn't enough on its own for the laxer one to dominate")
end)

test("a strictly laxer limit on a shared key is itself a strict improvement, at equal score and count", function()
  local addon = newAddon()
  local laxer = assignment(10, { first = candidate("cat", 2) })
  local tighter = assignment(10, { first = candidate("cat", 1) })

  A.truthy(addon.Assignments.Frontier.Dominates(laxer, tighter),
    "equal score and count, but a less restrictive limit, should dominate")
  A.falsy(addon.Assignments.Frontier.Dominates(tighter, laxer))
end)

test("a policy-valid assignment dominates a policy-invalid one when usage is no worse, even with a lower score", function()
  local addon = newAddon()
  -- policyValid trumps SCORE (a currently-equipped item a registered
  -- policy actively rejects, e.g. leftover gear illegal under a spec
  -- change, must never survive alongside -- let alone beat -- a
  -- policy-valid alternative just because it happens to score higher),
  -- but only once usage-safety already holds (see the next test).
  local validLowerScore = assignment(10, {})
  local invalidHigherScore = invalidAssignment(20, {})

  A.truthy(addon.Assignments.Frontier.Dominates(validLowerScore, invalidHigherScore),
    "valid must dominate invalid regardless of the invalid one's higher score")
  A.falsy(addon.Assignments.Frontier.Dominates(invalidHigherScore, validLowerScore),
    "an invalid assignment must never dominate a valid one, no matter its score")
end)

test("a policy-valid assignment does NOT dominate a policy-invalid one when it uses more of a shared category", function()
  local addon = newAddon()
  -- The counterexample this guards against: a policy-invalid current
  -- weapon that touches no uniqueness category at all, next to a
  -- policy-valid replacement that DOES consume a category some other
  -- group's own fixed current state also needs. Whether the "better"
  -- valid replacement is actually usable depends on that other group --
  -- pruning the invalid one here on validity alone could make the only
  -- globally feasible complete loadout (the invalid one plus that other
  -- group's current state) unreachable. Policy validity may only trump
  -- score once usage-safety (the same check score dominance already
  -- relies on) has been established -- it is not an unconditional
  -- ahead-of-everything dimension.
  local validButCostly = assignment(120, { first = candidate("raidToken", 1) })
  local invalidButFree = invalidAssignment(200, {})

  A.falsy(addon.Assignments.Frontier.Dominates(validButCostly, invalidButFree),
    "a valid assignment must not erase an invalid one by outscoring it while consuming MORE of a shared category")
  A.falsy(addon.Assignments.Frontier.Dominates(invalidButFree, validButCostly),
    "the invalid assignment still can't dominate the valid one either -- neither should be pruned")
end)

test("policyValid is nil (treated as valid) for every ordinary assignment, so existing behavior is unaffected", function()
  local addon = newAddon()
  -- Every hand-built fixture in this file, and every ordinary solver-
  -- proposed assignment, never sets policyValid at all -- both sides
  -- being nil must fall through to the normal score/usage comparison
  -- exactly as before this dimension existed.
  local higher = assignment(20, { first = candidate("item:1", 1) })
  local lower = assignment(10, { first = candidate("item:1", 1) })

  A.truthy(addon.Assignments.Frontier.Dominates(higher, lower))
  A.falsy(addon.Assignments.Frontier.Dominates(lower, higher))
end)

test("a higher score does NOT dominate when it has worse set-count progress", function()
  local addon = newAddon()
  local higherNoSet = assignment(100, {})
  local lowerTierPiece = assignment(90, {})
  lowerTierPiece.setCounts = { tier = 1 }

  A.falsy(addon.Assignments.Frontier.Dominates(higherNoSet, lowerTierPiece),
    "the lower-scoring tier piece may enable a loadout-level set bonus later")
  A.falsy(addon.Assignments.Frontier.Dominates(lowerTierPiece, higherNoSet),
    "the tier piece's lower score still prevents it from dominating back")
end)

test("equal score with strictly better set-count progress dominates", function()
  local addon = newAddon()
  local tierPiece = assignment(50, {})
  tierPiece.setCounts = { tier = 1 }
  local plain = assignment(50, {})

  A.truthy(addon.Assignments.Frontier.Dominates(tierPiece, plain))
  A.falsy(addon.Assignments.Frontier.Dominates(plain, tierPiece))
end)

test("target and required flags are preserved as dominance dimensions", function()
  local addon = newAddon()
  local targeted = assignment(40, {})
  targeted.targetFlags = { wishlist = true }
  targeted.requiredFlags = { locked = true }
  local plain = assignment(40, {})

  A.truthy(addon.Assignments.Frontier.Dominates(targeted, plain))
  A.falsy(addon.Assignments.Frontier.Dominates(plain, targeted))
end)

test("Prune removes a policy-invalid assignment once a resource-equivalent policy-valid assignment exists", function()
  local addon = newAddon()
  local validLowerScore = assignment(10, {})
  local invalidHigherScore = invalidAssignment(20, {})

  local survivors = addon.Assignments.Frontier.Prune({ invalidHigherScore, validLowerScore })

  A.equal(#survivors, 1)
  A.equal(survivors[1], validLowerScore)
end)

test("incremental Insert preserves the same survivor semantics as Prune", function()
  local addon = newAddon()
  local dominant = assignment(120, { first = candidate("item:1", 2) })
  local dominated = assignment(90, { first = candidate("item:1", 1) })
  local setRelevant = assignment(80, {})
  setRelevant.setCounts = { tier = 1 }
  local freeInvalid = invalidAssignment(200, {})
  local all = { dominated, setRelevant, freeInvalid, dominant }

  local pruned = addon.Assignments.Frontier.Prune(all)
  local incremental = {}
  for _, entry in ipairs(all) do
    addon.Assignments.Frontier.Insert(incremental, entry)
  end

  local function contains(list, value)
    for _, item in ipairs(list) do
      if item == value then return true end
    end
    return false
  end

  A.equal(#incremental, #pruned)
  for _, survivor in ipairs(pruned) do
    A.truthy(contains(incremental, survivor), "incremental frontier should contain every Prune survivor")
  end
end)

test("Prune keeps a policy-invalid assignment alongside a policy-valid one that costs more in a shared category", function()
  local addon = newAddon()
  local validButCostly = assignment(120, { first = candidate("raidToken", 1) })
  local invalidButFree = invalidAssignment(200, {})

  local survivors = addon.Assignments.Frontier.Prune({ validButCostly, invalidButFree })

  A.equal(#survivors, 2, "neither safely dominates the other -- a downstream group may need the invalid one's zero usage")
end)

test("Prune keeps a policy-invalid assignment when it is the only representable option", function()
  local addon = newAddon()
  local onlyOption = invalidAssignment(200, {})

  local survivors = addon.Assignments.Frontier.Prune({ onlyOption })

  A.equal(#survivors, 1)
  A.equal(survivors[1], onlyOption)
end)

test("Prune keeps both a higher-scoring tight-limit option and a lower-scoring lax-limit option", function()
  local addon = newAddon()
  -- Neither dominates the other (see the Dominates tests above) -- a
  -- global optimizer may need the laxer one later, so pruning must not
  -- discard it just because it scores lower.
  local tighterHigherScore = assignment(20, { first = candidate("cat", 1) })
  local laxerLowerScore = assignment(10, { first = candidate("cat", 2) })

  local survivors = addon.Assignments.Frontier.Prune({ tighterHigherScore, laxerLowerScore })

  A.equal(#survivors, 2)
end)

test("higher score but strictly more uniqueness usage dominates neither way", function()
  local addon = newAddon()
  local higherScoreMoreUsage = assignment(20, { first = candidate("item:1", 1), second = candidate("item:2", 1) })
  local lowerScoreLessUsage = assignment(10, { first = candidate("item:1", 1) })

  A.falsy(addon.Assignments.Frontier.Dominates(higherScoreMoreUsage, lowerScoreLessUsage))
  A.falsy(addon.Assignments.Frontier.Dominates(lowerScoreLessUsage, higherScoreMoreUsage))
end)

test("Prune keeps a non-dominated frontier untouched", function()
  local addon = newAddon()
  local a = assignment(20, { first = candidate("item:1", 1), second = candidate("item:2", 1) })
  local b = assignment(10, {})

  local survivors = addon.Assignments.Frontier.Prune({ a, b })

  A.equal(#survivors, 2)
end)

test("Prune removes a strictly dominated assignment", function()
  local addon = newAddon()
  local better = assignment(20, { first = candidate("item:1", 1) })
  local dominated = assignment(10, { first = candidate("item:1", 1) })

  local survivors = addon.Assignments.Frontier.Prune({ better, dominated })

  A.equal(#survivors, 1)
  A.equal(survivors[1], better)
end)

test("Prune is transitive-safe: only the true best survives across a 3-assignment chain", function()
  local addon = newAddon()
  -- best dominates middle (higher score, same usage), middle dominates
  -- worst (higher score, same usage) -- best must also correctly
  -- dominate worst directly, not rely on middle surviving to relay it.
  local best = assignment(30, { first = candidate("item:1", 1) })
  local middle = assignment(20, { first = candidate("item:1", 1) })
  local worst = assignment(10, { first = candidate("item:1", 1) })

  local survivors = addon.Assignments.Frontier.Prune({ worst, best, middle })

  A.equal(#survivors, 1)
  A.equal(survivors[1], best)
end)

return tests
