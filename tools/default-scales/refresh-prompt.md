# XIVEquip Default Scale Refresh Prompt

Use this prompt when a new WoW Retail patch changes class/spec stat priorities.

For every supported Retail specialization, inspect the current Wowhead class
guide stat-priority section. Extract only the priority ordering and any tied
stats. Do not copy guide prose.

Convert each spec into XIVWeights defaults:

- primary stat = 1.0
- highest-ranked non-primary stat = 0.5
- next = 0.4
- next = 0.3
- next = 0.2
- continue downward by 0.1 only when additional ranked dimensions are explicit
- unranked dimensions = 0
- tied stats receive the same value

Update `XIVEquip/XIVWeights/Builtin/Defaults.lua` and preserve source metadata
for the guide page and review date. Report any spec whose priority could not be
resolved confidently instead of guessing.
