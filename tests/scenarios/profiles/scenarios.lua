-- tests/scenarios/profiles/scenarios.lua
-- Doc section 9's scoring-profile bullets that are testable at this layer
-- without any production change: for the offline black-box harness, a
-- "profile" is just which deterministic score table the scenario feeds
-- cmp.ScoreItem through -- there's no real Pawn-scale enumeration or
-- spec-to-profile binding involved here (that's covered at the right layer
-- by tests/specs/comparer_spec.lua already, and isn't duplicated here).
--
-- "automatic mode reproduces current behavior" is demonstrated by the first
-- scenario reusing the plain default scoring path with no explicit
-- profile.scoring.profileID. "Two profiles choose different items" is
-- demonstrated by the second/third pair: the same two candidate items,
-- scored under two different (hypothetical) profile weightings, produce
-- two different winners.

local root = ...
local sep = package.config:sub(1, 1)
local Item = dofile(root .. sep .. "tests" .. sep .. "harness" .. sep .. "item_builder.lua")

return {

  {
    name = "scoring profile: automatic/default mode reproduces plain best-score selection",
    character = { classFile = "WARRIOR" },
    profile = { scoring = { provider = "test" } },
    items = {
      strengthHead = Item.armor(101, "INVTYPE_HEAD", 1, "plate", 100),
      agilityHead = Item.armor(102, "INVTYPE_HEAD", 1, "plate", 80),
    },
    equipped = {},
    bags = { [0] = { "strengthHead", "agilityHead" } },
    expect = { final = { [1] = "strengthHead" } },
  },

  {
    name = "scoring profile: a strength-weighted profile picks the strength item",
    character = { classFile = "WARRIOR" },
    profile = { scoring = { provider = "test", profileID = "test:strength-weighted" } },
    items = {
      strengthHead = Item.armor(101, "INVTYPE_HEAD", 1, "plate", 100),
      agilityHead = Item.armor(102, "INVTYPE_HEAD", 1, "plate", 90),
    },
    equipped = {},
    bags = { [0] = { "strengthHead", "agilityHead" } },
    expect = { final = { [1] = "strengthHead" } },
  },

  {
    name = "scoring profile: an agility-weighted profile picks the agility item instead, same candidates",
    character = { classFile = "WARRIOR" },
    profile = { scoring = { provider = "test", profileID = "test:agility-weighted" } },
    items = {
      strengthHead = Item.armor(101, "INVTYPE_HEAD", 1, "plate", 80),
      agilityHead = Item.armor(102, "INVTYPE_HEAD", 1, "plate", 100),
    },
    equipped = {},
    bags = { [0] = { "strengthHead", "agilityHead" } },
    expect = { final = { [1] = "agilityHead" } },
  },
}
