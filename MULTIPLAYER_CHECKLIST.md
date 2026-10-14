# Multiplayer determinism — code-review checklist

Lockstep multiplayer (DESIGN_MULTIPLAYER.md) requires **bit-identical sim state on
every peer, every tick**: same initial state + same command stream ⇒ same state.
Every change to sim code must pass this checklist. When in doubt, ask: *"could
two peers running this code disagree about the state at tick N?"* If yes, it
doesn't land.

**Sim code** = anything that reads or writes match state: units, AI controllers,
actions, traits, resources, pheromones, waves, digging, spawning, combat,
navmesh. **View code** = rendering, audio, HUD, camera, particles, animations,
input handling. The line is: *nothing the camera sees may feed back into sim
state.*

## 1. Randomness — SimRNG only
- [ ] Sim code uses ONLY `SimRNG.randf_range()/randi_range()/randf()/shuffle()`
      with the closest subsystem stream (`STREAM_COMBAT/SPAWN/AI/WANDER/DIG/
      PLACEMENT/UNDERGROUND`). New features pick an existing stream; new streams
      need a design note.
- [ ] BANNED in sim code: global `randf()/randi()/randf_range()/randi_range()`,
      `RandomNumberGenerator.randomize()`, `Array.shuffle()`, `pick_random()`
      on unseeded sources.
- [ ] View-only code (decorations, particles, UI jitter) may use a local
      `RandomNumberGenerator` — seeded if its output is visible across peers
      (decorations already do this via position hash), unseeded only if truly
      cosmetic AND never read by sim code.
- [ ] `Match` seeds `SimRNG` from `settings.match_seed` in `_ready()` before any
      sim system initializes. Multiplayer lobbies supply a shared nonzero seed.

## 2. Time — ticks, never wall-clock
- [ ] Sim timing uses `SimTimer` (tick-based), never Godot `Timer`,
      `get_tree().create_timer()`, or `Time.get_ticks_msec()/get_ticks_usec()`.
- [ ] Sim accumulation runs in `_physics_process` with `SimRNG.tick_delta()`,
      never `_process(delta)`. (`_physics_process` delta is already fixed, but
      the explicit constant removes all doubt about engine internals and
      `time_scale`.)
- [ ] Wall-clock stays allowed ONLY in pure view/UI: VFX pulses, voice
      cooldowns, HUD animations, input double-click windows, menu delays.
- [ ] `Engine.time_scale` MUST be `1.0` in multiplayer (enforced by the
      multiplayer session setup, M1). The debug speed toggle is solo-only.
- [ ] `AnimationPlayer` method tracks MUST NOT mutate sim state (no damage,
      no spawns, no resource changes). Drive such effects from tick countdowns
      in code; animation tracks are visual only. (Precedent: Rocket.gd strips
      its `_perform_hit` method track at runtime.)

## 3. Float math — same ops, same order, everywhere
- [ ] Godot floats are IEEE-754 double: the same operation order gives the same
      result on ARM64 and x86_64. Keep operation order fixed; don't reorder
      arithmetic across "equivalent" refactors in sim hot paths.
- [ ] No exact float equality (`==`) in sim branches that matter — use epsilon
      windows (which are themselves deterministic).
- [ ] Wander/idle angles and other transcendental uses in sim hot paths should
      be quantized (integer degrees or lookup tables), not raw `sin/cos` of
      unquantized values, to minimize cross-platform libm drift.
- [ ] Fixed-point migration (project-chronicle pattern) is the documented
      escape hatch if cross-platform desyncs ever appear in the wild — not v1.

## 4. Iteration order — deterministic
- [ ] Sim iteration over Dictionaries/Sets uses **sorted keys** or Arrays.
      (`get_nodes_in_group()` returns scene-tree order — deterministic — but
      never `shuffle()` it with the global RNG; use `SimRNG.shuffle`.)
- [ ] Unit spawn order derives from the deterministic command stream / fixed
      spawn tables, never from signal/callback arrival order.

## 5. Navmesh
- [ ] Match start is gated on navmesh bake completion
      (`await_terrain_navigation_ready()`) before any unit spawns — same as
      the existing spawn gate.
- [ ] Mid-match rebake *requests* are tick-scheduled (`TerrainNavigation`
      uses `SimRNG.tick`), not frame-scheduled.
- [ ] KNOWN RESIDUAL (M2 hardening): the rebake itself is async, so the tick
      on which the new mesh becomes queryable can vary by 1–2 ticks across
      peers. If this ever causes a desync in the wild: make rebakes synchronous
      at a tick boundary, or version-stamp the navmesh and include the version
      in the state hash (§6).

## 6. Platform parity
- [ ] Identical features on PC and mobile — no `OS.has_feature("mobile")`
      (or similar) branches in sim code. Quality tiers (`QualityManager`) are
      **view-only and banned from sim code**.
- [ ] Binary command/snapshot encoding (M1+) uses explicit little-endian
      layout; no `var_to_bytes()` without a fixed schema.

## 7. View/sim separation — the hard rule
- [ ] Fog-of-war *knowledge* (who sees what) is sim state and must be
      deterministic; its *rendering* is view-only.
- [ ] Particles, voice lines, camera shake, selection visuals, marker pulses:
      view-only, never read by sim code.
- [ ] `UndergroundView.send_unit_to_surface()` mutates sim state from a View
      class — flagged for M1 refactor into the sim layer (currently
      deterministic via SimRNG, acceptable for M0).

## M0 determinism gate
`tests/determinism/` — headless: two runs of the same-seed AI-vs-AI match must
produce identical state hashes at the same tick. Any mismatch is a P0 desync
bug: fix the sim, never the test.
