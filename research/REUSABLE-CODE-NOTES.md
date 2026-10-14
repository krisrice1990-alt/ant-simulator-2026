# Reusable open-source code for Ant Simulator 2026 (Godot 4.7 / GDScript)

Researched 2026-10-14. Permissive licenses only (MIT/CC0). Cloned to `research/`.

## 1. ant-world — hermes98761234/ant-world (Phaser + Colyseus, TS)
- **License:** ⚠️ README claims MIT, but **no LICENSE file in repo**. Treat algorithms as inspiration; reimplement rather than copy-paste.
- `server/src/systems/PheromoneSystem.ts` — sparse tile-keyed pheromone map:
  - lay: `strength = min(existing + 0.3, 3.0)`; new tiles start at 1.0
  - tick: linear decay; rate 0.002/tick, rain 0.008/tick; remove below 0.05 (20 Hz tick)
- `server/src/systems/ColonySystem.ts` — colony food store; larvae eat `0.05 * larvaeCount` food/tick; new colony starts with 3 larvae
- `server/src/systems/PredatorAI.ts` — nearest-ant targeting: damage if within 2 units (spider 20 / beetle 15 / centipede 10 per `shared/src/constants.ts`), chase if within 20, else wander on surface; seeded `mulberry32` RNG (good for deterministic sim)
- `server/src/systems/WorldGen.ts` — tilemap gen (air / grass / dirt / 5% rock), food sources on surface (10–60 amount), predator spawns (spider/beetle/centipede, 100 HP), colony spawn points; seeded
- `shared/src/constants.ts` — role stats: forager (speed 2.5, HP 80), soldier (2, 150), builder (1.5, 100), nurse (1.5, 70), scout (3, 90); world 400×200 tiles, surface at y=80
- Has unit tests per system (`server/tests/`)

## 2. NLM101 / SlimeHive — Blacksky-Labs/NLM101 (TS, browser swarm sim)
- **License:** ✅ MIT (LICENSE file verified)
- `src/simulation/pheromones.ts` — dual grids (hive + ghost), `deposit` capped at 255, `depositArea` with Manhattan falloff, multiplicative `decayGrid`, 8-neighbor `sampleGradient` returning half-step vector
  - Defaults (`src/simulation/config.ts`): deposit 5.0, ghost 0.5, decay 0.95
- `src/simulation/behaviors.ts` — **best steal: weighted multi-mode behavior blending.** Modes AVOID/FLOCK/ALIGN/FORAGE/SCATTER/SWARM/RANDOM/FEED_QUEEN/BOIDS each return a velocity vector, combined by weights (AVOID 2.0, FLOCK 1.0, ALIGN 0.5, FORAGE 2.0, FEED_QUEEN 3.0, RANDOM 0.3); desperation (hunger-based) scales detection radius ×(1+0.5·desperation) and triggers erratic search; carrying ants head straight to queen at speed 3; anti-stall random nudge when velocity is zero; output discretized via sign()
- Directly portable to GDScript ant AI

## 3. ant-farm — cod-e-codes/ant-farm (Rust, terminal sim)
- **License:** ✅ MIT (LICENSE file verified)
- `src/main.rs` — ant state machine: Wandering / Foraging / Carrying / Digging
  - Wandering → Foraging 30%, → Digging 35% (if diggable nearby); Foraging → Wandering 40%, → Digging 10%; Digging → Wandering 30%, → Foraging 20%; Carrying → move to target
  - Stepping on Food cell → Carrying; reaching queen → deposit
- Dual pheromone channels (home + distress): distress decays slower in crisis (0.95) vs healthy (0.85); ants near distress (>0.5) switch to Digging (80% if wandering, 60% if foraging); gradient follow = strongest of 8 neighbors above 0.5
- `try_dig` — **best steal: tunnel-digging algorithm.** Momentum: last dig direction weighted 5×; cardinal directions weighted 3× (straighter tunnels); bias outward from queen (Manhattan distance); 80% chance to move into newly dug tunnel
- Params: 150 ms tick, max 30 ants, spawn 1.2%/tick, food spawn 1.5%/tick, colony health decay 0.07/tick, low-health threshold 55

## 4. Antkeeper — antkeeper/antkeeper-source
- **License:** ❌ GPL-3.0-or-later (source) + proprietary game data. **NOT usable.**
- Its Sketchfab micro-CT ant scans are CC0 (public domain) but are raw 1.2M-triangle scans — not game-ready, no rig. Reference only.

## 5. BlendSwap CC0 ant models ("Ant - rigged, animated" by vildanovak; "rigged ant" by MeinhardAbsalon)
- **Blocked:** downloads require a BlendSwap account (login wall verified). Blender is not installed on this machine, so .blend → glTF conversion would need a Blender install regardless.
- Recommendation: skip — prototype already builds procedural ants.

## Suggested steals for our GDScript (priority order)
1. ant-farm `try_dig` momentum/cardinal/outward algorithm → tunnel digging
2. NLM101 weighted behavior blending + desperation foraging → ant AI
3. ant-world pheromone lay/decay numbers + predator AI targeting → pheromones/enemies
4. ant-farm state machine transitions → worker/soldier logic
