# Ant Simulator 2026 — Design Document

**Bar to beat:** Empires of the Undergrowth. Every system asks "is this better than EotU?"
**Platforms:** ONE game, both screens — identical features and systems on PC and mobile. "PC better" is visual/technical only: maxed graphics, effects, ant counts, draw distances on PC; mobile gets tuned-down rendering of the same game (Compatibility renderer, fewer particles, lower caps via quality settings). Never two different games. Long-term: single project tree with quality tiers (Low/Mobile → Ultra/PC).

## 1. Pillars (from EotU, outdone)
- Underground nest building (tile-based excavation — LATER phase, not in current build)
- Surface foraging (food + protein, pheromone trails)
- Colony management (castes, eggs/brood, queen)
- Enemy encounters (spider waves, rival colonies)
- Pheromone/trail mechanics (foraging, alarm, warfare)
- Distinct unit roles per caste

## 2. Playable ant species (all platforms — same game everywhere)
| Species | Unique mechanic |
|---|---|
| Garden ants (black) | Balanced baseline — the current build |
| Leafcutters | Harvest leaves → fungus gardens (new structure) → food multiplier over time; huge mediae workers as living storage |
| Army ants | Nomadic: no permanent nest (mobile bivouac instead of nest mound); overwhelming swarm raids; must keep moving or colony starves |
| Fire ants | Venom: attacks apply damage-over-time; fastest brood cycle; aggressive AI temperament |
| Carpenter ants | Wood-chewers: excavate through wood/root barriers (new terrain obstacle); massive major workers; strongest melee, slowest colony |
| Trap-jaw ants | Lightning mandible strike: huge burst damage with long cooldown; elite hunters; small, fragile colonies |
| Weaver ants | Silk builders: bind leaves into nest structures (silk as building resource); traverse tree/vegetation obstacles others can't |

Species select at match setup. Each species: unique unit stats, one unique structure, one unique mechanic. Shared core (queen, eggs, pheromones, digging).

## 2b. Bug bestiary — enemies & neutrals (each with distinct behavior/AI)
| Bug | Role | Behavior |
|---|---|---|
| Termites | Rival faction | Mound colonies with own workers/soldiers; expand aggressively; permanent ant enemies |
| Beetles | Armored prey | Very high HP, slow; hard to kill, drop large protein hauls |
| Spiders | Ambush predators | Already in build; lurk near food, pounce on isolated workers |
| Wasps | Flying raiders | Swoop attacks on workers carrying food; fast, fragile; drawn to stockpiles |
| Centipedes | Brood hunters | Fast, venomous; target eggs and queen; strike from map edges |
| Scorpions | Apex mini-boss | Rare spawns; enormous HP and damage; guards rich protein caches |
| Aphids | Farmable livestock | Passive herds; workers "milk" them for steady honeydew (food trickle); must be defended |
| Rival ant colonies | True rivals | Full AI colonies of other species competing for the map (existing AI, species temperaments) |

Surface and underground both feel alive: bugs wander, hunt, and react to the colony — not just wave spawns.

## 3. Rival AI colonies (same map)
2–4 colonies per map, each a full AI player (existing simple-clairvoyant-ai retuned per species temperament). Compete for food, raid each other, react to spider waves. Victory: last colony standing OR queen-capture mode (later).

## 4. Day/night cycle + seasons + weather
- Day/night: 6-min cycle; nocturnal foraging bonus for some species, spiders stronger at night
- Seasons: spring abundance → winter scarcity (food spawn rates scale)
- Weather: rain (slows surface movement, boosts fungus), drought (food scarce), storm (random events)
- Affects: foraging yield, movement speed, spider aggression. Shown on HUD + minimap tint.

## 5. Underground water & flooding (pairs with underground-nest phase)
Water table tiles; heavy rain floods low tunnels; workers must rescue brood. Not in current build — designed alongside tile-based excavation.

## 6. Colony tech / evolution tree
Brood Chamber upgrades via Royal Jelly (new currency from queen): e.g. Stronger Mandibles (+damage), Swift Legs (+speed), Fertile Queen (faster eggs), Pheromone Glands (stronger/longer trails), Venom Resistance. 2 tiers x 5 branches, all platforms.

## 7. Queen abilities (cooldown-based, PC)
- Pheromone Burst: all nearby workers get speed + harvest burst for 20s
- Royal Guard Call: nearest soldiers rally to the queen
- Brood Surge: next 5 eggs hatch instantly
Abilities unlock via tech tree.

## 8. Pheromone warfare
- Alarm trails: soldiers mark threats; nearby ants converge
- Trail hijacking: enemy scouts can corrupt rival trails (lead them astray); counter with "loyalty" tech
- Decoy trails: player-placed fake food trails to bait enemies/spiders

## 9. Scale (PC flagship)
- Grand maps (2x), 2–3x unit caps, bigger spider waves, 4-colony matches

## 10. Mobile rendering tiers (same game, tuned-down rendering — NOT fewer features)
- Renderer: Compatibility (vs Forward Plus on PC)
- Particles/VFX density: reduced; shadows: low/off; MSAA: off
- Unit caps: lower via quality settings (same systems, fewer simultaneous ants)
- Draw distance / LOD: aggressive on mobile
- All species, tech tree, queen abilities, weather, colonies, maps: IDENTICAL to PC. If a map is too heavy for mobile GPUs, it ships with a "reduced decoration" variant — same layout, same gameplay.

## Build phases
- **Phase 1 (in flight):** base game — castes, eggs/brood, digging, pheromone trails, spiders, rival AI, touch, day-agnostic. → Android APK + PC flagship EXE.
- **Phase 2:** species pack (leafcutter/army/fire-ant mechanics), bug bestiary, rival colony temperaments, day/night + weather, tech tree, queen abilities, pheromone warfare, Grand maps. Same features all platforms; PC gets maxed fidelity.
- **Phase 3:** connected world + true undergrounds (see below), water/flooding.
- **Phase 4:** player-hosted live multiplayer (lockstep).

## 11. Connected world & layered undergrounds (Phase 3)A larger world, not isolated levels:
- **Territories:** several surface territories (meadow, forest floor, desert scrub, rotten log, etc.), each with distinct food, bugs, and dangers. Territories connect via tunnel entrances / surface paths — ants travel between them (short transition through the tunnel).
- **Campaign structure:** expand territory by territory (conquer or colonize), or skirmish across linked territories. Rival colonies hold their own territories.
- **Underground layers** (3D makes this natural — vertical Y levels under the surface):
  - *Shallow tunnels* (Y−10): dirt, grub clusters, fast to dig; aphid herds near roots
  - *Deep chambers* (Y−25): clay/dense soil, richer food caches, centipede hunters, slower digging
  - *Bedrock layer* (Y−40): rock (carpenter ants excel here), royal jelly deposits, scorpion nests, flood risk
- **Distinct resources & dangers per layer:** shallow = safe/fast/poor; deep = risky/rich; bedrock = rare/very dangerous.
- **Water & flooding:** water table in deep layers; heavy rain floods low tunnels — rescue brood or lose it.
- **Implementation path:** start with large single maps containing multiple territories + tunnel links (achievable now); evolve toward persistent multi-map travel later. Camera gets a layer toggle (surface / shallow / deep / bedrock).

### Nest entrances & exits (core EotU loop — Phase 3)
- **Breakthrough digging:** workers excavating the shallow layer can be ordered to dig UPWARD at a player-chosen spot, breaking through to the surface and creating a nest entrance (mound with a hole).
- **Multiple entrances:** no hard cap — each costs digging time; player chooses placement. Entrances are two-way: ants ordered into an entrance on one side emerge from its pair on the other after a short travel delay.
- **Strategically meaningful:**
  - *Foraging routes* — entrances near food/aphids shorten worker trips (pheromone trails start at entrances)
  - *Defensible chokepoints* — entrances are narrow; soldiers guard them, but enemies (spiders, centipedes, rival ants) can invade through them too
  - *Exposure trade-off* — more entrances = faster foraging but more invasion vectors; few entrances = safe but slow
- **Entrance mechanics:** each entrance has structure HP — enemies can attack and collapse it (sealing the tunnel); player can re-dig. Collapsed entrances trap ants on the wrong side until reopened. Upgradable: reinforced rims (more HP), hidden entrances (harder for AI to find).
- **Queen safety:** the queen's chamber should stay deep — entrances near the surface never lead directly to her.

## 12. Rich surface world / topside (Phase 2–3, PC flagship priority)
The surface is as alive and gameplay-rich as the underground — never an afterthought.

**VISUAL DIRECTION (user directive, confirmed 2026-10-14 — "make it real"):** ant's-eye photorealism. The surface looks like the REAL world at ant scale — you are an ant in a real backyard/forest floor. Giant grass blades like trees, pebbles like boulders, twigs like fallen logs, realistic lighting and soil/grass textures. Grounded like EotU but better. The underground stays stylized dirt; the surface feels real. Ant-scale proportions govern all decoration sizing.

**Biomes** (each a territory type with its own foraging game):
- *Meadow:* grass tufts (cover, slow movement), seed clusters, flowers with timed nectar
- *Forest floor:* leaf litter, twigs (bridges/barriers), fallen fruit (big hauls that attract wasps), mushrooms
- *Sand / desert scrub:* sparse food, heat shimmer midday (ants slow), beetle territory
- *Rotten log:* wood-chewing (carpenter ants), grub pockets, termite mound nearby
- *Rock field:* stone cover, lichen, scorpion hunting grounds

**Vegetation:** grass tufts, flowers, saplings, mushrooms, moss — visual richness + gameplay (cover, slowdown, food).

**Surface food sources:** seed clusters (safe, scattered), fallen fruit (rich, contested, draws wasps), dead insects (protein, draws beetles), aphid herds (renewable honeydew — farm and defend).

**Water:** puddles and streams — slow crossings, drowning risk for small castes; rain fills them, drought dries them. Bridges (twigs) become strategic.

**Surface hazards & predators:** spider ambushes near food, wasp raids on laden workers, centipede surface hunts at night, scorpion territory, rain flooding low ground, anteater event (a giant snout sweep — rare, devastating, telegraphed).

**Day/night up top:** dawn/dusk lighting shifts; flowers open/close; nocturnal predators emerge; some species forage better at night. The surface reads differently every hour — scouting matters.
