# Ant Simulator 2026 — Multiplayer Architecture Design

**Status:** DESIGN ONLY. No code changes. (Phase 4 of the main DESIGN.md roadmap.)
**Engine:** Godot 4.7, GDScript. Codebase: `~/workspace/ant-sim-rts-base` (rethemed godot-open-rts).
**Prior art (study, MIT-licensed):** `base-games/banners-of-the-eight` (lockstep patterns,
checksummed commands, desync detection), `estebanchos/project-chronicle` (fixed-point sim
discipline), `ctharo/chem-ants` (deterministic ant-sim architecture).

## 0. Locked constraints (do not revisit)

1. **Player-hosted.** The host's device runs the game server. No dedicated servers, no
   monthly cost, no always-on infrastructure.
2. **No accounts, no logins.** Friends join directly — LAN discovery or IP/join-code style.
3. **Host-quit fallback.** If the host leaves, nothing crashes: every player's session
   continues in solo play from the same agreed state, and each player saves their own data.
4. **One game, both screens.** Identical features and systems on PC and Android; only
   rendering fidelity differs (quality tiers), never features.
5. **Deterministic-first sim.** The simulation must be written so that identical inputs
   produce identical state on every peer (see §4).

---

## 1. Networking model recommendation: deterministic lockstep

### Why lockstep (and not the alternatives)

| Model | Bandwidth | Host CPU | Fits hundreds–thousands of ants? |
|---|---|---|---|
| **State sync** (host broadcasts full unit state) | ~units × 60Hz — megabytes/sec, kills mobile data and host upload | High | No |
| **Deterministic lockstep** (peers exchange only player commands) | Bytes/sec — a few commands per tick | Each peer simulates locally | **Yes** |
| Snapshot interpolation (FPS-style) | Medium | Medium | Wrong genre |

An ant RTS routinely has hundreds to low-thousands of simulated entities (workers,
soldiers, brood, spiders, pheromone cells). State-syncing that at 60Hz is infeasible on
a phone hosting over residential upload. **Lockstep sends only commands**
("move selection to X", "build turret at Y", "queen ability Z") — typically <1 KB/s per
player — and every peer runs the identical simulation. This is the genre-standard answer
(StarCraft, Age of Empires, and the Godot reference `banners-of-the-eight` all use it)
and it matches the prior research recommendation.

### Transport

- **Godot 4 `ENetMultiplayerPeer`** (built in, no plugin). UDP, reliable + unreliable
  channels, already used by Godot's multiplayer API. One peer = host-as-server
  (authoritative for lobby/membership, NOT for sim state — the sim is peer-symmetric).
- Channels: `CH_COMMAND` (reliable, ordered — player commands), `CH_SYSTEM` (reliable —
  lobby, hashes, snapshots), `CH_VOICE_NA` (none — no voice planned).
- **Tick model:** fixed 10 ticks/sec command cadence on top of the 60Hz physics sim
  (see §4.3). Commands are tagged with the tick they take effect on, with a 2-tick
  input delay to absorb jitter (tunable per connection; mobile on cellular may need 3–4).

### What lockstep demands (and what it gives us for free)

- Demands: a deterministic simulation (§4), a single command-capture choke point (§3),
  and all peers starting from the identical initial state (same map seed + same settings).
- Gives us for free: the **host-quit fallback** (§5). Because every peer already holds the
  full authoritative sim state locally, losing the host is not a data-loss event — it's
  just a membership change.

---

## 2. Host / join UX flow

### 2.1 Menu structure

```
Main Menu
└── Multiplayer
    ├── Host Game
    │   └── Lobby (map select, slots, AI fill, ready check, Start)
    ├── Join Game
    │   ├── LAN Games (auto-discovered list, tap to join)
    │   └── Join by Address (IP/hostname + port, optional saved favorites)
    └── (How to connect help screen)
```

No login screen exists and none will — a player name is a free-text field stored locally
(defaults to device name), used only as a lobby label.

### 2.2 Hosting flow

1. Player taps **Host Game** → game opens an `ENetMultiplayerPeer` server on the
   configured port (default e.g. `7777`, user-changeable in settings).
2. **Lobby screen** (new scene, built on the existing menu framework):
   - Map picker (reuse match-setup map list), player slots (2–8), per-slot
     Human / AI / Closed, species pick per human slot, team setup.
   - Player list with ready toggles; host has Start (enabled when ≥2 humans ready or
     host forces start with AI fill).
   - Lobby shows the join address prominently: `LAN: 192.168.1.42:7777` and, if a
     public IP was detected (via UPnP or a what-is-my-ip check), `Internet: <ip>:7777`
     with a copy button.
3. On Start: host generates the **match seed**, broadcasts `match_config` (map, seed,
   slot assignments, settings hash) on `CH_SYSTEM`; all peers load the map and the
   lockstep session begins at tick 0.

### 2.3 Joining — LAN (zero infrastructure)

- Host broadcasts UDP beacons on the LAN (e.g. every 2s to `255.255.255.255:<port+1>`)
  containing game name, version, map, player count, and latency estimate.
- Join screen lists beacons as they arrive ("Kris's Meadow — 2/4 — 12ms — v0.4.0").
  Version mismatch entries are shown greyed out with "version mismatch" (lockstep
  requires identical builds — this is a hard gate).
- Tap → ENet client connect → lobby (as non-host) → ready → wait for host Start.

### 2.4 Joining — internet (the honest hard part)

There is no matchmaking server and no accounts, so there is no central lobby. The ladder:

1. **Direct address join** (always available): friend enters the host's public
   `IP:port`. Works if the host's router passes the port through.
2. **Automatic port mapping:** on host start, attempt UPnP / NAT-PMP port mapping
   (Godot has `UPNP` support via `UPNPDevice`; mobile routers vary — treat as
   best-effort, show "reachable from internet: yes/no/unknown" in the lobby).
3. **Manual fallback UX:** if auto-mapping fails, the lobby shows a short, friendly
   port-forwarding explainer ("forward UDP 7777 to this device") — one screen, plain
   language, with the device's LAN IP pre-filled.
4. **Short join codes — explicitly out of scope without infra.** A memorable
   6-digit code requires a rendezvous server to map code→IP. Options, in order of
   preference: (a) skip codes entirely for v1 (IP:port + LAN discovery covers the
   "friends" use case the user asked for); (b) later, an optional community-run
   rendezvous (a trivial static key-value board on free-tier hosting — but that
   reintroduces an always-on dependency, so it stays optional and the game never
   depends on it).

**NAT traversal note:** ENet does not do NAT hole-punching by itself, and reliable
hole-punching without a rendezvous/STUN server is not practical. The design accepts
this: LAN works out of the box; internet works when the host is reachable (UPnP or
manual forward). This is the standard trade-off for serverless P2P (cf. classic
Warcraft III / Age of Empires direct-IP play).

---

## 3. Command model (the lockstep choke point)

All player intent — human AND AI — must flow through one ordered, serializable command
stream. Today, human orders enter via `match/players/human/UnitActionsController.gd`
(`_try_navigating_selected_units_towards_position`, `_try_ordering_selected_workers…`,
rally points, queen abilities) and AI orders come from `SimpleClairvoyantAI` controllers.
Neither path is currently captured as data.

### 3.1 `CommandBus` (new autoload)

```text
Human input (touch/mouse/gamepad) ──┐
AI controllers (per-tick decisions) ─┤─▶ CommandBus.issue(cmd) ─▶ tick-stamped ─▶ ENet broadcast
                                     │                                    │
                                     └──── apply locally at tick T+delay ──┘
```

- **Command format** (explicit binary encoding — no JSON, no Variant ambiguity):
  `[tick:u32][player_id:u8][type:u8][payload…]` where payload is fixed-layout per type
  (unit selection as sorted unit-ID arrays, positions as quantized Vector3, etc.).
- **Command types (v1):** `MOVE_TO`, `ATTACK_TARGET`, `ATTACK_MOVE`, `BUILD_AT`,
  `SET_RALLY`, `QUEEN_ABILITY`, `DIG_ORDER` (underground phase), `CHAT_PING`
  (non-sim, applied immediately), `RESIGN`.
- **AI as a player:** each AI colony's controller output is converted into the same
  command structs by an `AICommandAdapter` and issued through the bus with that AI's
  player_id. This makes AI deterministic *and* lets a dropped human's colony be
  seamlessly handed to AI (§5).
- **Checksum per command** (banners-of-the-eight pattern): `hash(cmd)` is logged; the
  periodic state hash (§6) covers the command log tail, so a corrupted/dropped command
  surfaces as a desync instead of silent divergence.

---

## 4. Determinism audit plan

Lockstep lives or dies on determinism: same initial state + same command stream ⇒
bit-identical sim state on every peer, every tick. Audit findings from the current
`ant-sim-rts-base` tree (read-only review, 2026-10-14):

### 4.1 What is already deterministic-friendly

- **Decorations** (`seed_pile.gd`, `mushroom.gd`, `leaf_litter.gd`, `ChamberProps.gd`)
  already use seeded `RandomNumberGenerator` (`rng.seed = rng_seed`) — this is the
  pattern to extend everywhere.
- **Pheromone grid** (`Pheromones.gd`) is grid/array-based — deterministic if update
  order is fixed.
- **Physics runs at fixed 60Hz** (`_physics_process` in `Moving.gd`, `Movement.gd`,
  `AttackingWhileInRange.gd`) — fixed timestep is the right foundation.

### 4.2 What must change (the audit checklist)

| # | Hazard | Where it lives today | Required change |
|---|---|---|---|
| 1 | **Unseeded global RNG** — 44 call sites using `randf()`/`randi()`/`randf_range()` | `SpiderWaveSpawner.gd`, `IntelligenceController.gd`, `Movement.gd`, `RotateRandomlyWhenLookingForTargetsIdle.gd`, `Set.gd` | One **match-seeded central RNG** (autoload `SimRNG`, seeded from the lobby's match seed). Either a single ordered stream or one stream per subsystem (combat/spawn/AI/wander) — per-subsystem streams are safer (adding a feature can't shift another system's rolls). Global `randf` banned in sim code via code-review rule. |
| 2 | **Frame-rate-dependent motion** — `delta`-scaled movement in actions | `units/actions/Moving.gd`, `units/traits/Movement.gd`, `Spider.gd`, `Egg.gd` | Sim must advance on **fixed ticks**, never wall-clock `delta`. Keep `_physics_process` (fixed 60Hz) as the tick driver; rendering interpolation is view-only. Any `delta` in sim code becomes `TICK_DT` constant. |
| 3 | **Float math across ARM/x86** | All position/velocity math (Vector3) | Godot floats are IEEE-754 double; same op order ⇒ same results on ARM64 and x86_64 in practice. **Discipline:** no platform-varying transcendental reliance in sim hot paths (quantize wander angles to a lookup table or integer degrees); never compare floats for exact equality across logic branches that matter — use epsilon windows that are themselves deterministic. **Escape hatch (documented, not v1):** migrate sim-critical math to fixed-point (project-chronicle pattern) if cross-platform desyncs ever appear in the wild. |
| 4 | **Dictionary iteration order** | No `.keys()`/`.values()` iteration found in `match/units` today — keep it that way | Rule: sim iteration over dictionaries/sets must use **sorted keys** or arrays. Add to the multiplayer code-review checklist. |
| 5 | **Wall-clock timers** | `create_timer` / `Time.get_*` in AI controllers (`IntelligenceController`, `DefenseController`, `AutoAttackingBattlegroup`), `Egg.gd`, `AttackingWhileInRange.gd` | Convert sim timers to **tick counters** (`ticks_remaining -= 1`). Wall-clock stays allowed only in pure view/UI code (animations, voice cooldowns, HUD). |
| 6 | **Navmesh queries** | `TerrainNavigation` (recently fixed sync bug) | Navmesh bakes must complete identically on all peers before tick 0 (gate match start on bake-ready, same as the existing spawn gate). Pathfinding must be a pure function of (navmesh, start, goal) — no async/partial results mid-tick. |
| 7 | **Node/scene-tree ordering** | Unit spawn order, `_ready` cascades | Spawn order must derive from the deterministic command stream, never from signal/callback arrival order. |
| 8 | **View/sim separation** | Particles, voice lines, camera shake, selection visuals currently interleaved | Hard rule: **nothing the camera sees may feed back into sim state.** VFX, audio, HUD, fog-of-war visuals are view-only. (Fog-of-war *knowledge* — what a player can see — IS sim state and must be deterministic; its rendering is not.) |

### 4.3 Tick architecture

- **Sim tick = physics tick (60Hz fixed).** Command cadence = every 6th tick (10Hz):
  peers exchange command batches for tick `T+12` (2 command-ticks ≈ 1.2s input delay;
  adaptive 2–4 based on measured RTT, shown subtly in the lobby/HUD).
- **No rendering dependency:** a peer rendering at 30fps (mobile LOW tier) still sims
  at 60 ticks/sec. Quality tiers (§7) never touch the sim.
- **Deterministic startup:** lobby exchanges `match_config` → every peer loads the map,
  seeds `SimRNG` from the match seed, bakes navmesh, signals ready → host broadcasts
  `GO` → tick 0 begins on all peers simultaneously.

---

## 5. Host-quit fallback design

This is where lockstep pays off: **every peer already has the full, authoritative sim
state.** Host loss is a membership event, not a data-loss event.

### 5.1 Detection
- ENet heartbeat/timeout (tune: ~5s of silence = suspect, ~10s = gone; show
  "connection unstable" warning at the suspect stage).
- Host may also send a graceful `HOST_LEAVING` with its final tick number.

### 5.2 Fallback sequence (per surviving peer, identical on all of them)
1. **Freeze at last agreed tick** `T_last` (the highest tick for which all peers
   acknowledged the command batch — tracked continuously, so this is O(1)).
2. **Promote:** each remaining human keeps their own colony. Every *other* human
   colony (including the host's) is handed to the local AI (`AICommandAdapter` takes
   over that player_id — same code path as AI opponents, so no special casing).
   Remaining humans are notified: "Host left — their colony is now AI-controlled."
3. **Resume solo:** the local sim continues from `T_last` with no network. The game
   is now a single-player match against AI, exactly as if it had started that way.
4. **Save:** each player keeps **only their own colony/progress** (per the locked
   constraint). Shared/contested state (joint battlefields, neutral bugs, map
   exploration) is snapshotted into the local save as world context, marked
   `origin: multiplayer-fallback`. Ownership rule: units/structures keep their
   `owner_id`; on save, other players' entities are persisted read-only as
   "rival snapshot" data so a reloaded solo game has a sensible world.

### 5.3 Rejoin (later milestone)
- A dropped (non-host) player may rejoin within N minutes: host sends a full
  **state snapshot** at an agreed tick; the rejoining peer fast-forwards command
  batches from that tick. Requires snapshot serialization (§6.3) — plan the format
  early, implement in Milestone 3.

---

## 6. Anti-desync strategy

Desyncs will happen (missed command, float edge case, a modded client). The design
detects fast, recovers gracefully, and never silently diverges.

1. **Periodic state hash** (every 60 ticks = 1/sec): each peer computes
   `H = hash(unit_count, Σ quantized positions, Σ HP, resources per player,
   pheromone grid checksum, RNG stream position, tick)`. Hashes are broadcast on
   `CH_SYSTEM`; any mismatch at tick T ⇒ **desync declared**.
2. **On desync:** pause the sim on all peers (freeze frame + "syncing…" UI, max ~5s),
   host streams a full **snapshot** at the last agreed-good tick; peers load it and
   resume. If a second desync occurs within 60s, that peer is dropped to solo
   fallback (§5) rather than stalling the match.
3. **Command log:** every peer keeps the last ~10s of tick-stamped commands; the
   state hash covers the log tail, so the *cause* (divergent command vs divergent
   sim) is diagnosable from logs + the in-game bug reporter.
4. **Snapshot format (v1):** full unit list (id, owner, type, quantized pos/hp/state),
   structure list, resources, pheromone grid (RLE-compressed), RNG stream states,
   tick number. Target <2 MB for a large match; sent in chunks over `CH_SYSTEM`.
5. **Version gate:** lobby rejects mixed builds outright (desync by version is the
   cheapest one to prevent).

---

## 7. Android / PC cross-play considerations

- **Sim parity:** the sim is identical code on both platforms — cross-play is a
  determinism problem, not a feature problem, and §4 covers it. Same tick rate,
  same command encoding, same RNG.
- **Performance asymmetry:** a phone may render at 30fps on LOW tier while a PC
  renders at 144fps — irrelevant to lockstep, which keys off sim ticks, not frames.
  The one real risk is a phone CPU unable to simulate 60 ticks/sec with max unit
  counts; mitigation: the lobby's slot setup caps total units, and the host can set
  a "mobile-friendly" unit cap preset. Long-term: sim LOD is forbidden (it would
  desync) — instead, cap counts.
- **Input latency:** touch input has no disadvantage in lockstep (commands are
  tick-stamped, not reflex-based). Cellular jitter is absorbed by the adaptive
  command delay (2–4 ticks); the lobby shows each peer's ping so the host can see
  who's on a laggy link.
- **Battery/thermal:** sustained 60Hz sim + ENet on a phone is fine (the sim already
  runs at 60Hz in solo); the main cost is radio keep-alive — acceptable for a
  session-based RTS.
- **Endianness/serialization:** the binary command format (§3.1) uses explicit
  little-endian encoding everywhere; no `var_to_bytes` without a fixed schema.
- **Platform-specific code paths in sim:** banned. `OS.has_feature("mobile")` and
  friends may only branch *view* code (quality tiers), never sim code — add to the
  review checklist.

---

## 8. Phased implementation plan

**Milestone 0 — Determinism foundation** (prerequisite for everything)
- Implement `SimRNG` (match-seeded, per-subsystem streams); replace the 44 unseeded
  RNG call sites in sim code.
- Convert sim timers to tick counters; replace `delta` with `TICK_DT` in sim motion.
- Establish the sim/view separation rule + multiplayer code-review checklist (§4.2).
- Gate: headless 2× same-seed AI-vs-AI matches produce identical state hashes.

**Milestone 1 — LAN 2-player lockstep prototype**
- `CommandBus` autoload; human orders (`UnitActionsController`) captured as commands.
- ENet host/join, 10Hz command exchange with 2-tick delay, fixed 60Hz sim ticks.
- Minimal Host/Join UI (direct IP only).
- Gate: 2 humans complete a 5-minute match on LAN with zero desyncs.

**Milestone 2 — Full lobby + N players + desync safety**
- Lobby scene (map/slots/AI fill/ready), LAN UDP discovery, version gate.
- `AICommandAdapter` (AI issues commands through the bus); up to 8 players.
- Periodic state hashing + pause-and-resnapshot recovery (§6).
- Gate: 4-player LAN match (2 humans + 2 AI), forced desync injection recovers cleanly.

**Milestone 3 — Internet play + host fallback**
- UPnP/NAT-PMP auto-mapping, public-IP display, manual port-forward helper UI.
- Host-quit → solo fallback (§5) with per-player saves; heartbeat/timeout handling.
- Snapshot serialization format finalized; rejoin-with-snapshot for dropped clients.
- Gate: host kills app mid-match → all clients continue solo, saves intact.

**Milestone 4 — Cross-play hardening**
- Adaptive command delay (cellular), ping display, mobile-friendly unit-cap presets.
- Fuzz testing: randomized command streams across PC+Android builds, hash-compare.
- Gate: 2-hour PC-vs-Android match, zero desyncs, thermal/battery acceptable.

## Open questions (for the user, not blockers)
1. Max players per match for v1 (recommend 4: 2 humans + AI fill, raise to 8 later)?
2. Is the optional community rendezvous for short join codes worth *any* infra, or is
   IP:port + LAN discovery sufficient for "friends"?
3. On host-quit, should the host's colony become AI or be eliminated (its units
   becoming neutral/hostile)? Recommendation: AI takeover (keeps the match alive).
