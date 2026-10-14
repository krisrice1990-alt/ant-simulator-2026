# HANDOFF — Ant Simulator 2026 (mainline full-game tree)

> **Branch note:** this branch (`mainline`) holds the full-game Godot 4.7
> project. The 2D prototype lives on `master` (its own HANDOFF there).
> The in-app updater in both trees reads releases from this same repo.
>
> If you're an AI picking up this project: this file + `DESIGN.md` +
> `research/` + `docs/RELEASE_PIPELINE.md` are your onboarding. Read them
> before touching code. The repo is private; releases stay prerelease/draft
> until the human explicitly approves publishing.

## What this is

**Ant Simulator 2026** — a 3D ant-colony simulation RTS for **PC (Windows) and
Android**, built with **Godot 4.7**. Modelled on *Empires of the Undergrowth*,
with the explicit goal of beating it: deeper systems, better visuals, live
multiplayer, mobile crossover. One game, both screens (see key decisions).

This repo is the **mainline full-game tree**. (A separate 2D Android prototype
exists outside this repo purely as proof of the core loop — dig/forage/combat/
queen — and is not shipped.)

## Repo layout

```
project.godot              Godot 4.7 project (config/version = 0.3.0)
source/                    All game code (GDScript)
  main-menu/               Menu, options, play/setup screens
  match/                   RTS match: units, AI, maps, handlers, decorations
  data-model/              Options, match settings
  audio/                   AudioManager (music states, voice lines)
  updater/                 In-app updater (Updater + UpdaterUI autoload)
  utils/                   UIScale, QualityManager, helpers
addons/AntUpdater/         v2 Android plugin: installs downloaded APK updates
assets/                    Models, textures, audio, translations
docs/RELEASE_PIPELINE.md   Release pipeline: tagging, secrets, version discipline
research/                  Target-look research, art-hunt shortlist, ref images
DESIGN.md                  Full game design (species, bestiary, biomes, phases)
DESIGN_MODES.md            Game-modes design (difficulty, survival, challenges, campaign)
DESIGN_MULTIPLAYER.md      Multiplayer design (player-hosted, determinism plan)
HANDOFF.md                 This file
.github/workflows/
  main.yml                 CI: gdformat + gdlint on push/PR (keep code clean)
  release.yml              Builds APK + Windows ZIP, publishes GitHub releases
tools/                     CI helpers (ci_configure_android.py, ci_release_notes.py)
                           + dev/verification scripts
```

## What's DONE

- **Full 3D RTS foundation** — adopted `lampe-games/godot-open-rts` (MIT,
  attribution in `LICENSE`/`LOGO_LICENSES.md`); selection, orders, resources,
  buildings, fog of war, minimap, vs-AI all working.
- **All 5 implementation tracks**: unit logic/stats · 3D visuals · colony
  economy/brood/digging · pheromones/spiders/rival AI/win-lose · HUD/touch/menu.
- **Visual overhaul + refinement** — 5 ant castes rebuilt (~1.1k tris), glossy
  chitin, procedural terrain/dirt, nest mound + entrance, grass tufts (wind
  sway), pebble boulders, fallen-log twigs, warm sun + fog. Graphics upgrade
  pass (target-look: warm/cool lighting rig, chitin SSS+rim, 3-scale soil,
  bloom, dust motes) in flight — see `research/target-look-research-2026-10-14.md`.
- **Audio locked** (human approved every sample): 3 procedural music tracks,
  16 ant-themed voice lines, volume/mute persisted.
- **Mobile-ready**: UI scaling (AUTO 2x phones), touch controls, Compatibility
  renderer path, quality tiers, in-game bug reporter, debug overlay (F3 /
  triple-tap version).
- **Gamepad support** (Xbox/PlayStation layouts).
- **Critical bugs fixed**: AI turret hang (unbounded placement search),
  navmesh serving empty mesh → units teleported to (0,0,0).
- **In-app updater + release pipeline** — `source/updater/` checks the
  `dev-latest` GitHub release, downloads APK/ZIP with progress;
  `addons/AntUpdater/` (v2 plugin) installs the APK;
  `.github/workflows/release.yml` builds + publishes. Details in
  `docs/RELEASE_PIPELINE.md`.
- **Multiplayer design** (`DESIGN_MULTIPLAYER.md`, determinism-first plan) and
  **modes design** (`DESIGN_MODES.md`) written; implementation in flight.

## What's IN FLIGHT (as of 2026-10-14)

- **Graphics upgrade pass** on this tree (target-look implementation). Visual
  work — coordinate before touching `source/match/decorations/`, materials,
  or lighting.
- **Game modes build** — implements `DESIGN_MODES.md`: difficulty → survival
  → challenges → campaign → UI.
- **Multiplayer build** — implements `DESIGN_MULTIPLAYER.md`, starting at M0
  (deterministic sim discipline).
- **Species & bestiary build** — Phase 2: playable species (leafcutters, army
  ants, fire ants, carpenter ants, trap-jaw, weavers), bug bestiary, rival
  colonies, excavation spoil piles (ants carry dirt out and pile it away from
  entrances).
- **Underground**: tile-based nest excavation is the known gap vs EotU
  (Phase 3). Directives on record: RTS orders must work underground
  (click-select, right-click order); tunnels are smooth organic carves, never
  chunky blocks; surface view must NOT show the underground — tap to switch to
  a readable EotU-style cutaway.

## What's NEXT

1. Finish graphics pass → verify v0.3.0 (screenshots, phone-aspect judged) →
   first `dev-latest` release → human audit.
2. Game modes, then species/bestiary (Phase 2).
3. Connected world + layered undergrounds + nest entrances (Phase 3).
4. Player-hosted multiplayer (Phase 4 — biggest lift, needs the deterministic
   sim from M0).
5. Human approves → publish releases (undraft), post to GitHub publicly only
   on explicit approval.

## Key decisions (do not relitigate without the human)

- **Visuals: REALISTIC.** EotU is the bar, not the ceiling. No cartoon/stylized.
- **ONE game, both screens.** Identical features and systems on PC and mobile.
  "PC better" = rendering only (maxed graphics, effects, ant counts, draw
  distances). Never a mobile feature subset. Single tree, quality tiers.
- **Multiplayer is player-hosted.** The game starts its own server; the fastest
  PC hosts; everything saves on that machine — no monthly server bill. No
  logins/accounts, ever. If the host quits, sessions fall back to solo play.
- **Art licensing:** CC-BY-SA art is OK **with attribution + share-alike on
  art derivatives only** (0 A.D. flora/textures, Unvanquished insectoids —
  see `research/open-game-art-hunt.md`; keep the per-asset provenance log).
  **Never ship GPL/AGPL code** (anthill, subterrans, Xonotic art — taint risk;
  OpenRA — EA-derived). Code stays ours.
- **Base is MIT** (`lampe-games/godot-open-rts`) — attribution preserved in
  `LICENSE` and credits.
- **Repo stays private; releases stay prerelease/draft** until the human says
  go. The `dev-latest` rolling release is prerelease (the updater's read-only
  token cannot see drafts); versioned `v*` releases are drafts.
- **Never ask the human for raw tokens/passwords.** Secrets go in via GitHub's
  web UI or Secure Vault flows, never chat.

## How to build / export

- **Godot 4.7.2**: `~/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64`
  (also at `/home/hatch/tools/godot/`). Headless import check:
  `Godot_v4.7.2-stable_linux.x86_64 --headless --path . --import`
  (watch stderr for `SCRIPT ERROR`s).
- **Export presets** (`export_presets.cfg`): `Android` (package
  `com.antsim2026.game`; **Gradle build must stay ON** — Godot 4.7 refuses to
  bundle the AntUpdater plugin otherwise; CI installs the build template
  headlessly), `Windows Desktop`, `Linux/X11`, `macOS`.
- **makefile**: `release-linux` / `release-macos` / `release-windows`,
  plus `lint`/`format-check` (CI enforces `gdformat` + `gdlint`).
- **Release flow**: push to `main` → `release.yml` builds
  `ant-simulator-2026.apk` + `ant-simulator-2026-windows.zip` → recreates the
  `dev-latest` prerelease (what the updater reads). Needs 5 repo secrets —
  see `docs/RELEASE_PIPELINE.md`. **Version-bump discipline**: `project.godot`
  `config/version`, `source/updater/updater.gd` `CURRENT_VERSION`, and
  `CHANGELOG.md` top section — all three, every release.
- **In-app updater**: needs `UPDATE_READ_TOKEN` secret at build time
  (→ `updater_token.txt`, gitignored). Without it the update check fails
  quietly by design.

## Working agreements

- Show visual progress with **screenshots**, not just text status.
- Zero script errors is the bar for anything merged.
- Check `AGENTS.md` in the working environment for accumulated local lessons.
- The human audits before anything is published. When in doubt, ask.
