# Ant Simulator 2026 — New Game Modes Design

**Status:** DESIGN ONLY (2026-10-14). No code, scenes, or project files modified.
**Scope:** Three new modes on top of the existing single-player skirmish-vs-AI.
**Target tree:** `~/workspace/ant-sim-rts-base` (Godot 4.7, GDScript, 3D RTS).

## 0. Design pillars (non-negotiable)

- **EotU-inspired, better:** underground colony building, surface foraging, colony
  management, enemy encounters — deeper systems than Empires of the Undergrowth.
- **No pay-to-win:** progression is skill-based. No purchasable unlocks, boosts,
  timers, or currencies. Stars/medals/scores are earned, never bought.
- **Offline-first:** every mode works fully offline. No server calls, no
  always-online checks.
- **No forced accounts:** all progress is local (`user://`). No login, no
  profiles-in-the-cloud. (Multiplayer, when it lands in Phase 4, stays
  player-hosted with direct join — still no accounts.)
- **One game, both screens:** identical modes and rules on PC and mobile.
  Mobile differences are rendering-only (quality tiers), never gameplay.

## 1. Current baseline (for context)

- **Skirmish** (the only mode today): pick a map (Plain & Simple 4p 50×50,
  Big Arena 8p 140×140), assign HUMAN / AI / NONE per slot, play to last
  colony standing. Queen death = instant defeat for that colony
  (`MatchEndHandler`). Spiders are hostile wildlife: they raid everyone but
  never block victory.
- **Core loop:** workers forage Food (ResourceA) and Protein (ResourceB);
  eggs hatch into Worker/Scout/Soldier castes (nursery Royal Jelly aura
  speeds hatching); soldiers defend; queen is the fail state.
- **Existing systems to reuse:** `SpiderWaveSpawner` (escalating waves, 5s
  warning markers, broodmother every 3rd wave, protein drops from corpses),
  `MatchEndHandler` (victory/defeat/finish tiles), `MatchSettings` (player
  setup), `Loading` scene, quality tiers (LOW/MEDIUM/HIGH/AUTO via
  `QualityManager`), mobile UI scaling (`UIScale`, AUTO 2× on phones),
  gamepad + touch input, in-game bug reporter, debug overlay, procedural
  audio (voice lines + adaptive music).

---

## 2. Mode 1 — Mission Campaign

### 2.1 Concept
A structured, hand-designed sequence of missions that teaches the game
(Acts 1) and then tests mastery (Acts 2–3). Each mission is a scenario on an
existing map with custom starting conditions, objectives, and special rules —
not just "kill everyone."

### 2.2 Mission anatomy
Every mission defines:
- **Briefing:** title, 2–4 sentence story setup, primary objective, bonus
  objectives, special rules. Shown on a briefing screen before launch
  (readable text, large touch-friendly "Start Mission" button).
- **Setup:** map, player slots (fixed per mission — some are solo, some have
  scripted AI rivals with fixed temperaments), starting units/resources,
  special rules (e.g., "spider waves start at wave 3", "no turrets",
  "rival AI is passive for 5 minutes").
- **Win condition:** mission-specific (see list). Checked by a
  `MissionDirector` node that hooks `MatchSignals` (unit deaths, resources,
  timers) — `MatchEndHandler` stays as the defeat path (queen death always
  loses, in every mode).
- **Lose conditions:** queen dies (universal), OR mission timer expires where
  the mission is timed, OR all workers/eggs lost with no way to rebuild
  (colony collapse check).
- **Star rating (1–3):** 1 star for winning at all; 2nd star for beating the
  par time; 3rd star for completing all bonus objectives. Stars persist and
  gate progression.

### 2.3 Progression
- Missions unlock sequentially; finishing a mission (≥1 star) unlocks the
  next. Acts unlock as units.
- No grinding gates, no currencies: if you can beat it, you progress.
- Replay any unlocked mission to improve stars.

### 2.4 Mission list (9 missions, 3 acts)

**Act 1 — "First Forage" (teaches the loop, no rival colonies)**
1. **Awakening** — Hatch 6 workers, gather 150 Food. No enemies. Bonus: do it
   in under 6:00 / lose no units.
2. **First Blood** — Spider raids begin (wave spawner from wave 1, slow).
   Kill 8 spiders without losing the queen. Bonus: kill a broodmother.
3. **The Broodmother** — Survive 6 spider waves; kill the wave-6 broodmother.
   Bonus: keep all starting soldiers alive.

**Act 2 — "Rival Colonies" (AI opponents)**
4. **Border Skirmish** — Plain & Simple, 1 rival AI (passive temperament).
   Destroy its queen. Bonus: win in under 12:00.
5. **Protein Run** — Gather 400 Protein in 14:00 while a raider AI harasses
   workers (it can't be eliminated — its nest is off-map; defense mission).
   Bonus: lose fewer than 5 workers.
6. **Siege** — Big Arena, 2 rival AIs. Destroy both queens. Bonus: win
   without building turrets.

**Act 3 — "The Deep Dark" (mastery)**
7. **Endless Night** — Survive 12 spider waves, no rivals, escalating from
   wave 4. Bonus: end with 20+ ants alive.
8. **Extermination** — Big Arena, 3 rival AIs, aggressive. Last colony
   standing. Bonus: be the first to kill any queen.
9. **Queen of Queens** — Finale: 2 rival AIs + heavy spider waves from the
   start. Destroy both queens. Bonus: win in under 20:00.

Par times and bonus objectives are tuned per mission during playtesting;
values above are starting points.

### 2.5 Difficulty scaling
Global 3-level difficulty, ant-themed names, selectable on the campaign setup
screen and changeable anytime (applies to the next mission launch):
- **Scout (easy):** rival AI is passive/cautious, spider waves −25% size and
  +10s interval, player starts with +2 workers / +50 Food.
- **Worker (normal):** as designed.
- **Soldier (hard):** rival AI aggressive, spider waves +25% size and −10s
  interval, no starting bonus.
Stars are tracked **per difficulty** (a mission can hold 3 stars on each).
Changing difficulty never locks or wipes progress.

---

## 3. Mode 2 — Wave Survival ("Hold the Nest")

### 3.1 Concept
Endless defense against escalating spider waves. No rival colonies — just
your colony, the map's resources, and the spiders. How long can the queen
survive? Pure EotU fantasy: the nest under siege.

### 3.2 Rules
- **Setup:** pick a map (both work; Big Arena gives more room to expand).
  Solo colony, standard starting units. No AI players.
- **Waves:** reuses and extends `SpiderWaveSpawner`:
  - Wave 1 at 90s, then every 45s (configurable by difficulty).
  - Size = `2 + wave_number`, uncapped (the skirmish cap of 6 is lifted);
    broodmother every 3rd wave; from wave 8, every 5th wave adds fast
    "skitterer" spiders (high speed, low HP — new variant of `Spider.gd`).
  - 5s red warning markers + HUD countdown persist from skirmish.
  - Corpses drop Protein (scaling with wave number, as now) — the economy
    engine of the mode: kills fund the defense.
- **Build phases:** the 45s between waves IS the build phase. A HUD banner
  shows "Wave N incoming in 0:32" with a progress bar. No separate phase
  state needed — the rhythm is forage/build → defend → harvest → repeat.
- **Score:** `waves_cleared × 100 + spider_kills × 10 + flawless_wave_bonus`
  (+50 per wave with zero colony losses). Score ticks live on the HUD.
- **Win/lose:** there is no victory — the run ends only when the queen dies
  (defeat screen shows waves survived, kills, final score). Pause menu gains
  "End Run" which banks the current score as the final result (counts as a
  completed run, not a defeat).

### 3.3 Difficulty scaling
Same global Scout/Worker/Soldier setting:
- **Scout:** wave interval 55s, size ×0.75, spider HP −20%.
- **Worker:** as designed (45s, ×1.0).
- **Soldier:** wave interval 35s, size ×1.25, spider HP +20%, skitterers
  from wave 6.
High scores are tracked **per map + difficulty**.

### 3.4 Session length (mobile consideration)
Survival runs can go long. Mitigations: score banks on "End Run" or queen
death (nothing is lost by quitting); the pause menu shows current score at
all times; no mid-run save needed because a run is a single sitting by
design. (Full mid-match save is out of scope for v0.3.x.)

---

## 4. Mode 3 — Timed Challenges

### 4.1 Concept
Short, fixed scenarios scored against the clock. Each challenge has a single
clear goal and par times for medals. Built for mobile: every challenge is
designed to finish in under ~15 minutes.

### 4.2 Rules
- **Setup:** challenge picker shows goal, par times, and your best medal.
  Launch goes straight to the scenario (fixed map, fixed setup — no
  configuration to fiddle with).
- **Timer:** counts up on the HUD from match start. Pausing pauses the timer
  (no cheating via pause).
- **Medals:** Gold ≤ par_gold, Silver ≤ par_silver, Bronze ≤ finish at all.
  Best medal + best time persist per challenge **per difficulty**.
- **Lose conditions:** queen dies (universal), or the challenge's own fail
  state (e.g., timer cap exceeded → "Out of time").

### 4.3 Challenge list (5 to start)
1. **Lunch Rush** — Gather 400 Food as fast as possible. No enemies.
   Par: Gold 7:00 / Silver 9:00.
2. **Regicide** — Assassinate the rival AI's queen as fast as possible
   (Plain & Simple, 1 aggressive AI). Par: Gold 11:00 / Silver 14:00.
3. **Egg Sprint** — Hatch 20 ants in under 8:00 (tests brood/nursery play).
   Par: Gold 5:30 / Silver 7:00.
4. **Holding the Line** — Survive 10 spider waves; scored by clear time,
   tiebreak on ants alive. Par: Gold 12:00 / Silver 15:00.
5. **Protein Baron** — First to bank 500 Protein wins the race vs 1 AI rival
   (it banks too — race, not combat). Par: Gold 10:00 / Silver 13:00.

New challenges can be added as data (scenario definition + pars) without
new systems.

### 4.4 Difficulty scaling
Same global Scout/Worker/Soldier setting shifts enemy pressure and starting
bonuses as in §2.5; par times stay fixed (medals are per difficulty, so a
Gold on Soldier means more than a Gold on Scout).

---

## 5. Mode-select UI flow

Main menu today: Play / Options / Credits / Quit. New flow:

```
Main
├── Skirmish        → existing Play screen (map list + player slots) → Loading → Match
├── Campaign        → Mission select (acts, stars, locks) → Briefing → Loading → Match
│                                                  └── Results (stars earned) → Next / Replay / Menu
├── Survival        → Setup (map + difficulty) → Loading → Match (endless)
│                                                  └── Defeat/End-Run → Score → Retry / Menu
├── Challenges      → Challenge picker (goal, pars, best medal) → Loading → Match
│                                                  └── Results (medal, best time) → Retry / Menu
├── Options (unchanged)
├── Credits (unchanged)
└── Quit
```

UI requirements:
- Big touch targets (≥64px at 1×, scaled by `UIScale`), full gamepad
  d-pad navigation with visible focus (menus already do this — extend the
  pattern, don't reinvent it).
- Briefing and results screens reuse the existing menu visual language.
- The in-match HUD gains per-mode widgets: objective tracker (campaign),
  wave banner + score (survival), timer + goal (challenges). All optional
  via existing HUD patterns.
- Bug reporter stays in the pause menu in every mode; debug overlay
  unchanged.

---

## 6. Difficulty system (global)

One setting, three levels — **Scout / Worker / Soldier** — stored in
`Options` (persisted, changeable from the mode setup screens and the
options menu). Applies to campaign, survival, and challenges (skirmish
keeps its own per-slot AI setup). Effects are data-driven multipliers, not
separate code paths:
- AI temperament/aggression and starting bonuses (campaign).
- Spider wave size, interval, HP (survival + spider-heavy missions).
- Starting resources/workers (Scout only).
Records (stars, scores, medals, times) are tracked **per difficulty** so a
Soldier Gold is never overwritten by a Scout run.

---

## 7. Save / progress persistence

Offline-first, local-only, no accounts. Same pattern as `Options`
(`Resource` + `ResourceSaver` to `user://*.tres`):

| File | Contents |
|---|---|
| `user://campaign_progress.tres` | highest unlocked mission index; `{mission_id: stars}` per difficulty |
| `user://survival_scores.tres` | `{map+difficulty: {score, waves, kills}}` best runs |
| `user://challenge_bests.tres` | `{challenge_id+difficulty: {best_time, medal}}` |
| `user://options.tres` (existing) | adds global `difficulty` (Scout/Worker/Soldier) |

- All writes are atomic-ish (write temp + rename, or single
  `ResourceSaver.save` as Options does today) and degrade gracefully —
  corrupt/missing files reset to defaults, never crash.
- No cloud sync in v0.3.x (no accounts pillar). If multiplayer (Phase 4)
  ever needs identity, it stays device-local.

---

## 8. How each mode reuses existing systems

| System | Campaign | Survival | Challenges |
|---|---|---|---|
| Match scene + maps | ✅ (both maps, fixed per mission) | ✅ (either map) | ✅ (fixed per challenge) |
| AI players (simple-clairvoyant) | ✅ rival colonies | ❌ (no rivals) | ✅ (Regicide, Protein Baron) |
| `SpiderWaveSpawner` | ✅ (tuned per mission) | ✅ (extended: uncapped, skitterers) | ✅ (Holding the Line) |
| `MatchEndHandler` | ✅ defeat path; `MissionDirector` adds win checks | ✅ defeat only (queen death) | ✅ + timer/out-of-time fail |
| Queen-as-fail-state | ✅ universal | ✅ universal | ✅ universal |
| Resources (Food/Protein), eggs, nursery jelly | ✅ | ✅ (kill-driven economy) | ✅ (race/sprint goals) |
| Quality tiers + `QualityManager` | ✅ unchanged | ✅ unchanged | ✅ unchanged |
| `UIScale`, touch, gamepad | ✅ unchanged | ✅ unchanged | ✅ unchanged |
| Bug reporter, debug overlay | ✅ unchanged | ✅ unchanged | ✅ unchanged |
| Voice lines + adaptive music | ✅ (mission stingers hook existing queues) | ✅ (wave warnings reuse spider-approach lines) | ✅ (victory/defeat lines) |

New code is confined to: a `MissionDirector` (objectives/win checks),
a `SurvivalDirector` (score, endless scaling, End Run), a `ChallengeDirector`
(timer, medals), the mode-select/briefing/results screens, and the three
progress resources. No changes to core sim, AI, or rendering.

---

## 9. Mobile considerations

- **Touch:** all new screens follow the existing mobile UI rules — big
  targets, readable text at phone size, `UIScale` AUTO 2× respected.
  Briefing text is short and scrollable; nothing requires hover.
- **Performance tiers:** modes add no new rendering cost. Survival's
  uncapped waves are the risk — cap *concurrent alive* spiders (the
  spawner's `MAX_ALIVE_SPIDERS` pattern) and let backlog queue; LOW tier
  keeps unit counts sane via existing scalability.
- **Session length:** challenges <15 min by design; campaign missions
  8–20 min; survival is endless but score banks on quit/death — nothing
  punishes putting the phone down.
- **Interruptions:** pause menu (with bug reporter) works in every mode;
  timer pauses with the game (challenges); wave countdown pauses too.
- **Battery/storage:** progress files are kilobytes; no background work.

---

## 10. Out of scope (not this design)

- Multiplayer (Phase 4, player-hosted — separate design).
- Mid-match save/load.
- New maps (modes reuse the 2 existing maps; new maps are content work,
  not mode work).
- Cosmetics/shop/battle-pass — prohibited by the no pay-to-win pillar.
- Cloud saves, leaderboards, accounts — prohibited by offline-first /
  no-forced-accounts pillars.

## 11. Suggested build order

1. Difficulty setting + persistence plumbing (unlocks everything below).
2. Wave Survival (smallest delta — extends the existing spawner).
3. Timed Challenges (fixed scenarios, reuses everything).
4. Mission Campaign (most content: 9 briefings, tuning, stars).
5. Mode-select UI + results screens (can parallelize with 2–4).
