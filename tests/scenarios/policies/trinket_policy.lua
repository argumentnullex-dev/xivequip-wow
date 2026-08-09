-- tests/scenarios/policies/trinket_policy.lua
-- Doc section 7's trinket *policy* bullets (preferred/avoided/excluded/
-- required/locked adjustments, passive-vs-on-use preference, unknown
-- metadata handling). Jewelry.lua has no such metadata today -- it scores
-- rings and trinkets identically via cmp.ScoreItem with no per-trinket
-- policy hook. Written now as skipped placeholders per user decision, so
-- the matrix shape is visible ahead of the 2.0.0 policy pipeline work.

local REASON = "requires 2.0.0 trinket policy metadata (not yet implemented)"

return {
  { name = "trinket policy: a preferred trinket receives a positive score adjustment", skip = true, skipReason = REASON },
  { name = "trinket policy: an avoided trinket receives a negative score adjustment", skip = true, skipReason = REASON },
  { name = "trinket policy: an excluded trinket is never selected", skip = true, skipReason = REASON },
  { name = "trinket policy: a required/locked trinket remains in the winning pair when available", skip = true, skipReason = REASON },
  { name = "trinket policy: one required item plus the best compatible second item is selected", skip = true, skipReason = REASON },
  { name = "trinket policy: two incompatible required items produce a stable diagnostic rather than an illegal plan", skip = true, skipReason = REASON },
  { name = "trinket policy: passive/on-use preference influences score only when metadata is known", skip = true, skipReason = REASON },
  { name = "trinket policy: unknown metadata does not silently classify the trinket", skip = true, skipReason = REASON },
  { name = "trinket policy: unique-equipped restrictions continue to apply after policy adjustments", skip = true, skipReason = REASON },
  { name = "trinket policy: policy cannot cause one physical item to occupy both slots", skip = true, skipReason = REASON },
}
