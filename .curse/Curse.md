# XIVEquip – “Equip Recommended Gear” for WoW

**One button, best gear.** XIVEquip plans upgrades from your bags and equips them—just like FFXIV’s “Equip Recommended Gear”.

- Uses **Pawn** weights when available; otherwise a clear **stat/ilvl fallback**.
- Smart **weapons** (legal combos only; Prot Paladin requires **1H+Shield**, Holy can use **Holdable/Frill**).
- **Rings/Trinkets** are unique (no re-use).
- **Auto-equip on spec change** (optional), then auto-saves an equipment set named **`Spec.xive`**.

> MIT-style license. Not affiliated with Square Enix or Pawn.

---

## Screenshots

![Oh No\! I need some Gear\!](/screenshots/nekkid.png)
![Good thing I have an Equip Recommended Gear button\!](/screenshots/nekkid_preview.png)
![I'm Beautiful! Beautiful!](/screenshots/holy_equipped.png)
![But what if I want to be Prot now?](/screenshots/talent_swap_me.png)
![I change my talent spec...](/screenshots/swappin.png)
![My gear is so Prot now\!](/screenshots/omg_prot_now.png)

---

## Features

- **Automatically Equip your Optimal Gear** - Click the added "Equip Recommended Gear" button in the Character panel frame to equip the best gear in your bags!
- **Preview Gear Changes on Hover** – Mouse over the ERG button to preview the gear you'll equip!
- **Pawn integration (recommended)** – Scores with your active spec scale. If Pawn isn’t present or returns no value, XIVEquip falls back to a transparent stat/ilvl score.
- **Auto-equip on spec change** – Optional; equips best gear and saves a set named `Spec.xive` (e.g., `Protection.xive`).

---

## Installation

1. Install via the **CurseForge App** (recommended).
   - This project lists **Pawn** as a **Required Dependency** so it will be auto-installed.
2. Or manual: copy the **XIVEquip** folder into `World of Warcraft/_retail_/Interface/AddOns/`.
   - Pawn is optional for manual installs, but highly recommended.

---

## Usage

- Open the **Character panel** and click the **XIVEquip** button to plan & equip upgrades.
- To enable **auto-equip on spec change**, open **Options → AddOns → XIVEquip** and tick
  **“Auto-equip & save set on spec change”.**

### Slash Commands

- `/xiveauto` — toggle auto-equip on spec change
- `/xiveauto test` — run a one-off auto-equip

---

## Settings

- **Active comparer** – How items are scored
  *Default:* **Auto (Pawn → ilvl)** — use Pawn if available; otherwise a safe fallback.
- **Messages** – Toggle login/equip messages.
- **Debug logging** – Developer-oriented logs.
- **Auto-equip on spec change** – Auto-equip & save *Spec.xive* set on spec swap.

---

## FAQ

**Do I need Pawn?**

No, but it’s recommended. Without Pawn, XIVEquip uses a transparent stat/ilvl fallback that you can debug in logs.

**Why did it pick a lower item level?**

Because your **weights** said it’s better (e.g., haste/vers might beat crit/mastery at lower ilvl for your spec). Enable debug to see contributions.

**But why doesn't it do...?**

Because I didn't think of it. I'm but a lone mortal man. I tried to make this modular and extensible, though. If you have an idea, like referencing a BiS list or making optimal Trinket selection more intelligent, have at it!

---

## Credits & License

MIT-style license. Inspired by the FFXIV “Equip Recommended Gear” flow. Not affiliated with Square Enix or Pawn.

**Author:** https://github.com/argumentnullex-dev
**Special Thanks:** Pawn authors for thier awesome item weight system!

--

Ideas? Interested in contributing? Send an e-mail to argument.null.ex@gmail.com. I can't promise to respond quickly - I have a day job!
