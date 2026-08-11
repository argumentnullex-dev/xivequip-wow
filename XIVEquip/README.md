# XIVEquip – “Equip Recommended Gear” for WoW

**XIVEquip** brings the FFXIV-style “Equip Recommended Gear” button to World of Warcraft.

- Click one button → it **plans** the best upgrades in your bags and **equips** them.
- The native planner uses built-in **XIVWeights** spec defaults out of the box; Pawn remains optional.
- Handles **armor**, **jewelry** (rings/trinkets are solved as pairs), and **weapons** (legal combos only).
- Optional: **Auto‑equip on spec change** and **auto‑save equipment sets** named **`Spec.xive`**.

> MIT-style license. Not affiliated with Square Enix or Pawn; big thanks to the Pawn authors ♥.

---

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
- **Auto-equip on spec change (optional)**
  - When you swap specs, XIVEquip can equip your best gear for that spec.
- **Auto-save spec equipment sets (optional)**
  - When enabled, verified successful equip operations save a set **`Spec.xive`** (e.g., `Protection.xive`).
  - Failed, timed-out, manual BoE, or zero-change runs do not auto-save.
- **Predictable debug**
  - Slot-filtered logs with a “force” bypass; detailed fallback scoring traces when wanted.

---

## Installation

1. Copy the **XIVEquip** folder into `World of Warcraft/_retail_/Interface/AddOns/`.
2. (Optional) Install **Pawn** to use your custom scales for scoring.
3. Launch the game and enable **XIVEquip** in the AddOns list.

---

## Development Builds

The repo has two build paths: one for fast in-game testing and one for release archives.

### Local environment

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
XIVEQUIP_ARCHIVE_DIR           # Publish archive output folder
```

Open a new terminal after running it so the variables are available to build scripts.

### Version scheme

XIVEquip uses semantic-ish addon versions:

- **Major** (`+1.0.0`) — huge overhauls.
- **Minor** (`+0.1.0`) — breaking changes.
- **Patch** (`+0.0.1`) — incremental releases.
- **Development builds** append `-dev.N`.

When starting a development branch, bump the intended release version and append `-dev.1`.
For example:

```text
1.1.4 -> 1.1.5-dev.1
```

Each later development build increments only the final dev number:

```text
1.1.5-dev.1 -> 1.1.5-dev.2
```

### Dev build

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

### Fixture import

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

### Publish build

Run this from the repo root:

```powershell
.\publish-build.ps1
```

The publish build script:

1. Reads the current TOC version.
2. Removes a trailing `-dev.N`, if present.
3. Writes the release version back to `XIVEquip/XIVEquip.toc`.
4. Creates `XIVEquip-<version>.zip` in `%XIVEQUIP_ARCHIVE_DIR%`.

For example:

```text
1.1.5-dev.7 -> 1.1.5
XIVEquip-1.1.5.zip
```

`build.ps1` remains as a compatibility wrapper for `publish-build.ps1`.

Publish builds should be created only from a reviewed release or RC branch. After publishing a stable release, tag the commit so the addon can be reset to that known-good point.

---

## Regression Testing

Run the offline regression suite from the repo root:

```powershell
.\tools\test.ps1
```

From Git Bash:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/test.ps1
```

The suite loads addon modules with mocked WoW APIs and covers scale resolution, settings migration, weapon legality, ring/trinket pair planning, unique-equipped rules, fixture replay, and equip execution semantics. It cannot replace live testing for protected WoW behavior, but it should pass before every PR and build.

---

## Usage

- Open your **Character panel** and click the **XIVEquip** button to plan & equip upgrades.
- Open `/xive` or `/xive settings` for the custom XIVEquip settings window.
- To enable **auto-equip on spec change**, use the General tab and tick **Auto-equip on spec change**.
- To let XIVEquip update equipment sets after successful equips, tick **Auto-save spec equipment set after equip**.

### Slash commands

- `/xiveauto` — toggle auto‑equip on spec change
- `/xiveauto test` — run a one‑off auto‑equip (useful for testing)
- `/xive` — open the XIVEquip settings window
- `/xive settings` — open the XIVEquip settings window
- `/xive status` — print settings schema, planner, auto-equip state, and auto-save state
- `/xive plan` — print the current native equip plan without equipping it
- `/xive equip` — equip the current native recommendation
- `/xive perf` — run a native planning pass and print timing/counter diagnostics
- `/xive test` — run in-game regression checks that do not equip gear
- `/xive fixture capture` — save current character, equipped item, bag item, and active Pawn scale data to `XIVEquip_Settings.TestFixtures.LastCapture`
- `/xive fixture clear` — remove captured fixture data

Fixture capture is intended for building realistic offline test cases. Run it on useful scenarios before logging out or reloading so the SavedVariables file is written.

---

## Settings

Open `/xive` or `/xive settings`.

- **Config** – Profiles, automatic scale selection, per-spec custom and addon-integration assignments, wishlist/avoidlist preferences, set-bonus preference, notifications, automation, minimap visibility, and the `/xivequip` macro helper.
- **Scales** – Create, import, duplicate, export, rename, edit, and delete custom scales tied to a specialization. Built-in defaults remain immutable.

Fresh specs use immutable built-in defaults. Choosing to customize a spec creates a normal SavedVariables scale named after the spec, such as `Protection`, `Retribution`, or `Holy`. Resetting a customized spec scale replaces your copy with a fresh copy of the shipped default for that spec.

---

## Release Candidate Smoke Checklist

Before cutting an RC or stable archive, perform a quick live-client pass:

1. `/reload`, then confirm the expected version in the AddOns list.
2. Run `/xive test`.
3. With the built-in source selected, confirm preview and equip display the expected specialization scale.
4. With Pawn enabled and selected as an addon integration, confirm preview and equip display the selected Pawn scale.
5. Test Fury Warrior with Titan's Grip two-handed weapons.
6. Test a shield spec, such as Protection Warrior or Protection Paladin.
7. Test a one-ring or one-trinket upgrade where the stronger currently equipped item should be retained.
8. Test a normal equip with auto-save off, then with auto-save on.
9. If practical, test an unbound BoE candidate and confirm it is reported as manual-required rather than silently completed.
10. Capture one useful fixture with `/xive fixture capture`, then reload and import it for offline replay.

---

## Debugging (optional)

Enable logging from the in‑game console:

```text
/xive debug on                           -- master debug on
/xive debug slot 6                       -- only log Waist (slot 6)
/xive debug slot clear                   -- log all slots
/run XIVEquip_DebugAutoSpec = true       -- verbose auto-spec logs
```

Passing "force" as the first argument to `Log.Debugf("force", ...)` bypasses the slot filter; the addon uses this for a few global lines already.

---

## File Structure (for devs)

- **Global/Settings.lua** — Canonical saved-variable schema, migrations, and settings getters/setters.
- **Global/Constants.lua / Localization.lua / Logger.lua** — Shared slot constants, user-facing strings, and slot-filtered debug logging.
- **Core/GearCore.lua** — Public gear helpers: item/slot maps, link helpers, uniqueness helpers, equipped item basics, scoring calls, single-slot candidate selection, and plan row construction.
- **Core/CommandRouter.lua** — Slash command routing for `/xive`, `/xivequip`, diagnostics, fixture capture, and settings commands.
- **XIVWeights/** — Native weights model, built-in spec defaults, SavedVariables-backed scale config, providers, importers, resolver, and scorer.
- **Integrations/Pawn.lua** — Pawn scale-discovery adapter used by the native XIVWeights provider.
- **Evaluation/** — Candidate collection, normalization, feature extraction, and policy-aware scoring.
- **Assignments/** and **Optimization/** — Slot-group assignment frontiers, uniqueness state, and whole-loadout optimization.
- **Planning/Runtime.lua / Coordinator.lua / PlanBuilder.lua** — Native planner runtime, whole-loadout coordinator, and executor-compatible plan construction.
- **Gear/Interface.lua** — Gear orchestrator and verified equip executor. Applies native plans with bounded verification and auto-saves only after verified success with no hard execution problems.
- **Automation/SpecSwitch.lua** — Spec-change listener and `/xiveauto` command; throttled and combat-safe; calls `Gear:EquipBest()` when enabled.
- **UI/SettingsWindow/** — Custom XIVEquip settings window.
- **UI/MinimapButton.lua** — Draggable minimap launcher for the custom settings window.
- **UI/UI.lua** — Character panel button and preview tooltip.
- **Tests/Regression.lua** — In-game `/xive test` checks.

---

## FAQ

**Do I need Pawn?**
No. XIVEquip ships with built-in specialization scales. Pawn is an optional scale integration.

**Why did it pick a lower item level?**
Because your **weights** said it’s better (e.g., a haste/vers piece may beat crit/mastery at lower ilvl for your spec). Turn on debug to see the exact score breakdown.

**It saved the set under the wrong spec name.**
We defer the save and re-read the active spec after swap. If you still see odd timing on your client, capture the behavior with `/xive status` and a fixture capture so it can be reproduced.

---

## Contributing

- Issues and PRs welcome—please keep changes **surgical** and split by file (Core vs planners vs UI).
- Keep **Core/GearCore.lua** backward-compatible; it is the public gear-helper surface.

---

## License

MIT-style. See the file headers or `LICENSE` for details.

**Credits:** Inspired by the FFXIV “Equip Recommended Gear” feature and Pawn © their authors. Thanks to everyone who helped test and iterate.
