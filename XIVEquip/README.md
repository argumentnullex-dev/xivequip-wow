# XIVEquip – "Equip Recommended Gear" for WoW

**XIVEquip** brings the FFXIV-style "Equip Recommended Gear" button to World of Warcraft.

- Click one button → it **plans** the best upgrades in your bags and **equips** them.
- Built-in **XIVWeights** spec defaults work out of the box; Pawn remains optional.
- Handles **armor**, **jewelry** (rings/trinkets are solved as pairs), and **weapons** (legal combos only).
- Optional: **Auto-equip on spec change** and **auto-save equipment sets** named **`Spec.xive`**.

> MIT-style license. Not affiliated with Square Enix or Pawn; big thanks to the Pawn authors ♥.

This README has two audiences:

- **[Using XIVEquip](#using-xivequip)** — install it, understand what it does, and configure it.
- **[Building on XIVEquip](#building-on-xivequip)** — the addon's own build/test tooling, and the public
  extensibility API for writing your own policies against it from another addon.

---

# Using XIVEquip

## Features

- **Planner-first flow**
  - `PlanBest` computes the full list of items to equip; `EquipBest` applies and verifies that plan.
  - If item data is still loading, XIVEquip retries briefly instead of treating unknown items as non-upgrades.
- **XIVWeights**
  - Fresh characters use source-controlled XIVEquip defaults for each spec.
  - Customizing a spec creates an editable SavedVariables copy that can be reset to the shipped default.
  - Pawn can still be used live or imported into a manual XIVWeights scale.
- **Weapons done right**
  - Legal combos only, scored via your comparer.
  - Fury supports Titan's Grip two-handed pairs. Protection specs keep shield requirements. Your weights decide winners inside legal loadouts.
- **Rings & Trinkets**
  - Solves each pair as one loadout, so a strong currently equipped ring/trinket can be retained while the weaker slot is upgraded.
  - Rejects duplicate physical items and unique-equipped conflicts before attempting to equip.
  - Optional: hide trinkets Blizzard itself doesn't consider appropriate for your specialization (Wishlist always overrides this).
- **Wishlist & Avoidlist**
  - Prefer or exclude specific gear per Profile and specialization, with a dedicated Settings tab for browsing/searching equipped and bag gear, or Ctrl-clicking a link straight in.
- **Auto-equip on spec change (optional)**
  - When you swap specs, XIVEquip can equip your best gear for that spec.
- **Auto-save spec equipment sets (optional)**
  - When enabled, verified successful equip operations save a set **`Spec.xive`** (e.g., `Protection.xive`).
  - Failed, timed-out, manual BoE, or zero-change runs do not auto-save.
- **Predictable debug**
  - Slot-filtered logs with a "force" bypass; detailed fallback scoring traces when wanted.

## Installation

1. Copy the **XIVEquip** folder into `World of Warcraft/_retail_/Interface/AddOns/`.
2. (Optional) Install **Pawn** to use your custom scales for scoring.
3. Launch the game and enable **XIVEquip** in the AddOns list.

## Usage

- Open your **Character panel** and click the **XIVEquip** button to plan & equip upgrades.
- Open `/xive` or `/xive settings` for the custom XIVEquip settings window.
- To enable **auto-equip on spec change**, use the General tab and tick **Auto-equip on spec change**.
- To let XIVEquip update equipment sets after successful equips, tick **Auto-save spec equipment set after equip**.

### Slash commands

- `/xive` or `/xive settings` — open the XIVEquip settings window
- `/xive plan` — print the current equip plan without equipping it
- `/xive equip` — equip the current recommendation
- `/xive status` — print settings schema, planner, auto-equip state, and auto-save state
- `/xive perf` — run a planning pass and print timing/counter diagnostics
- `/xive validate` — save `backup.xive`, unequip, equip the recommendation, and confirm it matches what a fresh plan would pick
- `/xive wish <item link|itemID>` — add to the active Profile and specialization's Wishlist (no argument lists it; remove from the Settings UI)
- `/xive avoid <item link|itemID>` — add to the active Profile and specialization's Avoidlist (no argument lists it; remove from the Settings UI)
- `/xive test` — run in-game regression checks that do not equip gear
- `/xive smoke` — run `/xive test`, then `/xive validate` if the checks pass
- `/xive fixture capture` / `/xive fixture clear` — save or clear current character/equipped/bag/Pawn-scale data for offline test replay (see [Fixture import](#fixture-import))
- `/xive debug ...` — see [Debugging](#debugging-optional)
- `/xiveauto` — toggle auto-equip on spec change; `/xiveauto test` runs a one-off auto-equip

Fixture capture is intended for building realistic offline test cases. Run it on useful scenarios before logging out or reloading so the SavedVariables file is written.

## Settings

Open `/xive` or `/xive settings`.

- **Config** – Profiles, automatic scale selection, per-spec custom and addon-integration assignments, set-bonus and spec-appropriate-trinket preferences, notifications, automation, minimap visibility, and the `/xivequip` macro helper.
- **Scales** – Create, import, duplicate, export, rename, edit, and delete custom scales tied to a specialization. Built-in defaults remain immutable.
- **Wishlist** – Search equipped and bag gear, or enter/Ctrl-click an item link, to prefer gear for the active Profile and specialization.
- **Avoidlist** – Search equipped and bag gear, or enter/Ctrl-click an item link, to exclude gear for the active Profile and specialization.

Fresh specs use immutable built-in defaults. Choosing to customize a spec creates a normal SavedVariables scale named after the spec, such as `Protection`, `Retribution`, or `Holy`. Resetting a customized spec scale replaces your copy with a fresh copy of the shipped default for that spec.

By default, a Profile has **Automatic** scale selection, **Prefer set bonuses**, and **Prefer spec-appropriate trinkets** all enabled — the intent is that installing XIVEquip and doing nothing else gives you the best available recommendation (continuing to use your existing Pawn scale automatically if you have one, while scoring set bonuses and hiding spec-inappropriate trinkets). Any of the three can be turned off per Profile.

## Debugging (optional)

Enable logging from the in-game console:

```text
/xive debug on                           -- master debug on
/xive debug slot 6                       -- only log Waist (slot 6)
/xive debug slot clear                   -- log all slots
/run XIVEquip_DebugAutoSpec = true       -- verbose auto-spec logs
```

Passing "force" as the first argument to `Log.Debugf("force", ...)` bypasses the slot filter; the addon uses this for a few global lines already.

## FAQ

**Do I need Pawn?**
No. XIVEquip ships with built-in specialization scales. Pawn is an optional scale integration.

**Why did it pick a lower item level?**
Because your **weights** said it's better (e.g., a haste/vers piece may beat crit/mastery at lower ilvl for your spec). Turn on debug to see the exact score breakdown.

**Why was a trinket hidden from the recommendation?**
XIVEquip can hide trinkets Blizzard itself doesn't consider appropriate for your specialization (**Prefer spec-appropriate trinkets** in Config, on by default). Wishlist the item to override this for that one trinket, or turn the preference off entirely.

**It saved the set under the wrong spec name.**
We defer the save and re-read the active spec after swap. If you still see odd timing on your client, capture the behavior with `/xive status` and a fixture capture so it can be reproduced.

---

# Building on XIVEquip

This section covers two different things: building/testing **this repo**, and writing **your own addon** that extends XIVEquip's recommendations through its policy API.

## Local environment

Run this once from the repo root:

```powershell
.\init-env.ps1
```

From Git Bash:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./init-env.ps1
```

There is also an `init-env.cmd` wrapper for launching the same setup from Explorer.

The initializer asks for and stores these user environment variables:

```text
XIVEQUIP_ADDON_PATH            # Full live AddOns\XIVEquip install folder
XIVEQUIP_SAVED_VARIABLES_DIR   # Folder containing XIVEquip.lua SavedVariables
XIVEQUIP_ARCHIVE_DIR           # Publish/release-candidate archive output folder
```

Open a new terminal after running it so the variables are available to build scripts.

## Version scheme

XIVEquip uses semantic-ish addon versions:

- **Major** (`+1.0.0`) — huge overhauls.
- **Minor** (`+0.1.0`) — breaking changes.
- **Patch** (`+0.0.1`) — incremental releases.
- **Development builds** append `-dev.N`.
- **Release candidates** append `-rc.N`, cut once a development line is ready for wider testing.

When starting a development branch, bump the intended release version and append `-dev.1`. For example:

```text
1.1.4 -> 1.1.5-dev.1
```

Each later development build increments only the final dev number:

```text
1.1.5-dev.1 -> 1.1.5-dev.2
```

When a dev line is ready for a release candidate, `rc-build.ps1` drops the `-dev.N` suffix and starts `-rc.1`; further candidate cuts for the same release increment `N`:

```text
1.1.5-dev.7 -> 1.1.5-rc.1 -> 1.1.5-rc.2
```

## Dev build

Run this from the repo root:

```powershell
.\dev-build.ps1
```

From Git Bash, run the same script through PowerShell:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./dev-build.ps1
```

The dev build script:

1. Reads `## Version:` from `XIVEquip/XIVEquip.toc`.
2. If the version is a release version, bumps patch by default and appends `-dev.1`.
3. If the version is already `-dev.N`, increments `N`.
4. Copies the addon folder to `%XIVEQUIP_ADDON_PATH%`.

After it runs, reload the UI in-game and the AddOns list/TOC version should show the new dev build. You can override the configured install path for one run with `-AddonPath`.

Optional bump choices when starting a new dev line:

```powershell
.\dev-build.ps1 -Bump Patch
.\dev-build.ps1 -Bump Minor
.\dev-build.ps1 -Bump Major
```

Optional install modes:

```powershell
.\dev-build.ps1 -Mode Copy
.\dev-build.ps1 -Mode Junction
.\dev-build.ps1 -SkipTests
.\dev-build.ps1 -RequireTests
.\dev-build.ps1 -NoInstall
```

`Copy` is the default because it works without special Windows permissions. `Junction` links the live AddOns folder back to the repo's `XIVEquip` folder. By default, the dev build runs offline tests when a local Lua runtime is available and warns/skips when it is not. `RequireTests` makes a missing Lua runtime fail the build. `SkipTests` bypasses the offline test step entirely.

## Release candidate build

Once a development line is stable enough for wider testing, cut a release candidate:

```powershell
.\rc-build.ps1
```

From Git Bash:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./rc-build.ps1
```

The RC build script:

1. Reads the current TOC version and computes the next `-rc.N` (dropping any `-dev.N` suffix the first time; incrementing `N` on repeat runs — see [Version scheme](#version-scheme)).
2. Runs the offline test suite (same behavior as `dev-build.ps1`'s `-SkipTests`/`-RequireTests`) and refuses to proceed if it fails, unless `-SkipTests` is passed explicitly.
3. Writes the new version to `XIVEquip/XIVEquip.toc`.
4. Installs the addon to `%XIVEQUIP_ADDON_PATH%` (same `-Mode`/`-AddonPath`/`-NoInstall` options as `dev-build.ps1`).
5. Archives `XIVEquip-<version>.zip` (keeping the `-rc.N` suffix, so multiple candidates for one release can coexist) to `%XIVEQUIP_ARCHIVE_DIR%`, unless `-NoArchive` is passed.

A release candidate must pass the offline suite and, ideally, the [smoke checklist](#release-candidate-smoke-checklist) before being shared for review.

## Fixture import

After running `/xive fixture capture` in game, run `/reload` or log out so WoW writes SavedVariables. Then import the capture into the offline fixture suite:

```powershell
.\tools\import-fixture.ps1
```

The importer reads `XIVEquip.lua` from the configured SavedVariables folder:

```text
%XIVEQUIP_SAVED_VARIABLES_DIR%\XIVEquip.lua
```

and writes a redacted fixture to:

```text
tests\fixtures\live_capture.lua
```

Character name, realm, and item GUIDs are redacted. Item IDs, links, equipment locations, item levels, slot assignments, and active Pawn scale metadata are retained so offline tests can replay realistic item data.

## Publish build (final release)

Run this from the repo root:

```powershell
.\publish-build.ps1
```

The publish build script:

1. Reads the current TOC version.
2. Removes a trailing `-dev.N` or `-rc.N`, if present.
3. Writes the release version back to `XIVEquip/XIVEquip.toc`.
4. Creates `XIVEquip-<version>.zip` in `%XIVEQUIP_ARCHIVE_DIR%`.

For example:

```text
1.1.5-rc.2 -> 1.1.5
XIVEquip-1.1.5.zip
```

`build.ps1` remains as a compatibility wrapper for `publish-build.ps1`.

Publish builds should be created only from a reviewed release or RC branch. After publishing a stable release, tag the commit so the addon can be reset to that known-good point.

## Regression testing

Run the offline regression suite from the repo root:

```powershell
.\tools\test.ps1
```

From Git Bash:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/test.ps1
```

The suite loads addon modules with mocked WoW APIs and covers scale resolution, settings migration, weapon legality, ring/trinket pair planning, unique-equipped rules, policy registration/resolution, the whole-loadout optimizer, fixture replay, and equip execution semantics. It cannot replace live testing for protected WoW behavior, but it should pass before every PR and build.

### Release candidate smoke checklist

Before cutting an RC or stable archive, perform a quick live-client pass:

1. `/reload`, then confirm the expected version in the AddOns list.
2. Run `/xive smoke` (runs `/xive test`, then validates a fresh equip against the recommendation).
3. With the built-in source selected, confirm preview and equip display the expected specialization scale.
4. With Pawn enabled and selected as an addon integration, confirm preview and equip display the selected Pawn scale.
5. Test Fury Warrior with Titan's Grip two-handed weapons.
6. Test a shield spec, such as Protection Warrior or Protection Paladin.
7. Test a one-ring or one-trinket upgrade where the stronger currently equipped item should be retained.
8. Test a normal equip with auto-save off, then with auto-save on.
9. If practical, test an unbound BoE candidate and confirm it is reported as manual-required rather than silently completed.
10. Capture one useful fixture with `/xive fixture capture`, then reload and import it for offline replay.

## File structure

- **Global/Settings.lua** — Canonical saved-variable schema, migrations, and settings getters/setters.
- **Global/Constants.lua / Localization.lua / Logger.lua** — Shared slot constants, user-facing strings, and slot-filtered debug logging.
- **Core/GearCore.lua** — Public gear helpers: item/slot maps, link helpers, uniqueness helpers, equipped item basics, scoring calls, single-slot candidate selection, and plan row construction.
- **Core/CommandRouter.lua** — Slash command routing for `/xive`, `/xivequip`, diagnostics, fixture capture, and settings commands.
- **Profiles/** — Profile storage and per-character assignment (`Config.lua`), and the `/xive wish`/`/xive avoid` slash commands (`Commands.lua`).
- **XIVWeights/** — Weights model, built-in spec defaults, SavedVariables-backed scale config, providers, importers, resolver, and scorer.
- **Integrations/Pawn.lua** — Pawn scale-discovery adapter used by the XIVWeights provider.
- **PublicAPI/Policies.lua** — `XIVEquip:RegisterPolicy`, the stable extensibility entry point. See [Extending XIVEquip](#extending-xivequip-writing-your-own-policies) below.
- **Policies/** — The policy registry, resolver, and every built-in policy, grouped by phase (`EvaluationContext/`, `Candidate/`, `Assignment/`, `Preference/`).
- **Evaluation/** — Candidate collection, normalization, feature extraction, and policy-aware scoring.
- **Assignments/** and **Optimization/** — Slot-group assignment frontiers, uniqueness state, and whole-loadout optimization.
- **Planning/Runtime.lua / Coordinator.lua / PlanBuilder.lua** — Planner runtime, whole-loadout coordinator, and executor-compatible plan construction.
- **Gear/Interface.lua** — Gear orchestrator and verified equip executor. Applies plans with bounded verification and auto-saves only after verified success with no hard execution problems.
- **Automation/SpecSwitch.lua** — Spec-change listener and `/xiveauto` command; throttled and combat-safe; calls `Gear:EquipBest()` when enabled.
- **UI/SettingsWindow/** — Custom XIVEquip settings window (Config, Scales, Wishlist, Avoidlist tabs).
- **UI/MinimapButton.lua** — Draggable minimap launcher for the custom settings window.
- **UI/UI.lua** — Character panel button and preview tooltip.
- **Tests/Regression.lua** — In-game `/xive test` checks.

## Extending XIVEquip: writing your own policies

XIVEquip's planner is built as a pipeline of small, independently-registered **policies** rather than one monolithic scoring function. This is the same mechanism XIVEquip's own built-in behavior (armor proficiency, weapon-hand legality, Wishlist/Avoidlist, set bonuses, spec-appropriate trinkets, and more) is written with — a third-party addon extends XIVEquip through the exact same door, not a separate/lesser API.

### Registering a policy

```lua
local XIVEquip = C_AddOns.GetAddOnLocalTable("XIVEquip")
-- Only returns the real table if XIVEquip.toc declares `## AllowAddOnTableAccess: 1`
-- (it does). XIVEquip is never a global, so this call is the only way in.

XIVEquip:RegisterPolicy({
  id = "YourAddon.some_policy",        -- required, unique, namespaced by convention
  phase = "candidate",                 -- required, see Pipeline phases below
  requires = { "character.class_id" }, -- optional: EvaluationContext fields this policy reads
  provides = { },                      -- optional: EvaluationContext fields this policy sets (evaluation_context phase only)
  groups = { "trinkets" },             -- optional: scopes an assignment-phase policy to one Assignments.Groups id
  isActive = function(context) return true end, -- optional: skip this policy entirely when it returns false
  apply = function(...) ... end,       -- required: signature depends on phase, see below
})
```

Register **before `PLAYER_LOGIN` finishes** — the registry locks after that point (matching every other addon's normal load-then-login sequence), and a late `RegisterPolicy` call raises loudly rather than being silently ignored. `requires`/`provides` build a dependency graph the resolver topologically sorts once at startup; a `requires` token nothing provides raises at startup too, so a typo'd dependency fails fast instead of quietly never running.

### Pipeline phases

Policies run in a fixed phase order; the same order that matters is enforced by `Policies/Resolver.lua`, not something you configure:

1. **`evaluation_context`** — `apply(builder, runtime)`. Builds the immutable per-planning-pass snapshot every later phase reads. Call `builder:Set(field, value)` for plain context fields and `builder:SetCapability(name, value)` for boolean weapon/gear capability flags. See [EvaluationContext fields](#evaluationcontext-fields-built-in) below for what's already there.
2. **`candidate`** — `apply(candidate, context, policyContext)`. Runs once per candidate item per slot placement it's being considered for. Return `{ allow = false, reason = "..." }` (or `nil`/no field to allow) to reject a candidate outright, or `{ scoreAdjustment = N, reason = "..." }` to adjust its score without rejecting it. See [Candidate shape](#candidate-shape) and [Writing a candidate policy: example](#writing-a-candidate-policy-example) below.
3. **`assignment`** — `apply(assignment, context) -> boolean`. Runs against a proposed multi-role assignment (e.g. both rings, or both weapon hands together) before it's added to that group's frontier; returning `false` rejects the whole assignment. Scope one to a single `Assignments.Groups` id with `groups = {"rings"}` etc. — see `Policies/Assignment/WeaponHandLegality.lua` for a complete real example (Titan's Grip, shield requirements).
4. **`loadout`** — `apply(loadout) -> boolean`. Runs once per complete candidate whole-loadout combination during the optimizer's search, reading aggregated `loadout.summaries` (set counts, target/required flags candidate/assignment policies contributed). Returning `false` rejects that combination.
5. **`preference`** — `apply(loadout, context) -> { preferenceAdjustment = N } | nil`. Runs after a legal loadout is chosen, to rank otherwise-legal combinations against each other (e.g. `Policies/Preference/PreferSetBonuses.lua`). A preference policy that participates in branch-and-bound pruning during the optimizer's search additionally implements an `optimizer` table (`prepare`/`createState`/`push`/`pop`/`upperBound`) — see that file for the real pattern; most preference policies don't need this and can just return an adjustment.

### EvaluationContext fields (built-in)

Read via `context.<field>` in any phase after `evaluation_context`:

| Field | Set by | Notes |
|---|---|---|
| `classID`, `classFile`, `specID`, `specName`, `level` | `CharacterIdentity.lua` | |
| `armorProficiencySubclass` | `ArmorProficiency.lua` | |
| `profilePreferences` | `ProfilePreferences.lua` | `{ preferSetBonuses, preferSpecAppropriateTrinkets, wishlist, avoidlist }` for the active Profile + spec. Spec-appropriate trinket filtering defaults on, can be disabled, permits unknown Blizzard metadata, and is bypassed by Wishlist. |
| `weights` | `WeightsResolution.lua` | The resolved XIVWeights scale for scoring |
| `capabilities["XIVEquip.allow_two_hand"]`, `..._dual_wield`, `..._offhand_weapon`, `..._shield`, `..._holdable`, `..._main_hand_one_hand`, `.titan_grip`, `.require_shield` | `ClassSpecWeaponCapabilities.lua`, `DualWieldOverride.lua` | Boolean weapon-hand legality flags for the active spec |
| `caches` | `Evaluation/ContextBuilder.lua` | Mutable scratch space for the planning pass (the only non-frozen part of the context) — use it to memoize expensive per-item work, keyed by whatever's stable for your policy (see `Policies/Candidate/SpecAppropriateTrinkets.lua`'s classID/specID/itemID cache key for a real example) |

### Candidate shape

A candidate passed to a `candidate`-phase policy (see `Evaluation/CandidateNormalizer.lua` for the authoritative shape):

```lua
{
  itemID = 12345,
  link = "|Hitem:12345:...|h[Item Name]|h",
  guid = "...",                 -- present for an equipped/bag item, absent for some synthetic candidates
  physicalID = "...",
  source = { kind = "bag" | "equipped", ... },
  equip = { equipLoc = "INVTYPE_TRINKET", itemClassID = ..., itemSubclassID = ..., requiredLevel = ... },
  itemLevel = 480,
  setID = 1234,                 -- nil if not part of a tier/dungeon set
  uniqueness = { key = "item:12345" | "category:77", limit = 1 },
  stats = { strength = 0, agility = 0, ..., criticalStrike = 120, ... },
  weapon = { dps = 0, minimumDamage = 0, maximumDamage = 0, swingIntervalSeconds = 0 },
}
```

### Writing a candidate policy: example

A user-configurable filter that hides a hypothetical "junk" item class demonstrates the same candidate-policy mechanics as `Policies/Candidate/SpecAppropriateTrinkets.lua`. The real trinket policy is enabled by default:

```lua
local XIVEquip = C_AddOns.GetAddOnLocalTable("XIVEquip")

XIVEquip:RegisterPolicy({
  id = "YourAddon.hide_junk_trinkets",
  phase = "candidate",
  groups = { "trinkets" },              -- only trinkets, leave every other slot untouched
  requires = { "character.spec_id" },
  isActive = function(context)          -- skip entirely (zero overhead) unless the player opted in
    return YourAddon.SavedVariables.hideJunkTrinkets == true
  end,
  apply = function(candidate, context, policyContext)
    if not YourAddon.IsJunk(candidate.itemID, context.specID) then return nil end
    return { allow = false, reason = "junk-trinket" }
  end,
})
```

Conservative failure matters: if your policy can't determine an answer (missing data, an API that hasn't loaded yet), prefer returning `nil` (allow) over rejecting — a false rejection silently removes an otherwise-good item from consideration, which is worse than an occasional suggestion the player can Avoidlist by hand.

---

## Contributing

- Issues and PRs welcome — please keep changes **surgical** and split by file (Core vs planner vs UI).
- Keep **Core/GearCore.lua** backward-compatible; it is the public gear-helper surface.
- Third-party policies register through `XIVEquip:RegisterPolicy` — see [Extending XIVEquip](#extending-xivequip-writing-your-own-policies) above.

## License

MIT-style. See the file headers or `LICENSE` for details.

**Credits:** Inspired by the FFXIV "Equip Recommended Gear" feature and Pawn © their authors. Thanks to everyone who helped test and iterate.
