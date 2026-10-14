# Visual Target Research Report — Ant Simulator 2026
Date: 2026-10-14
Status: Research complete — feeds the next visual pass after chitin re-verification passes.

Target: approved concept render `research/references/media-generation-ant-sim-target-look-0-c6929be1-82f0-45b8-99ca-7352813d5d74.webp`
plus Empire of the Ants (surface) and EotU underground references.

---

## 1. Deconstruction of the target look (measured, not vibes)

### 1A. The approved target render (underground cross-section)

**Ingredient 1 — Extreme luminance contrast (the #1 driver of the look).**
Chamber interiors peak at near-white warm `#fff4df` / `#fecf9f`; surrounding deep soil averages `#1c110c` — roughly a **40:1 luminance ratio**. Mid-tone chamber walls `#885230`–`#754c2a` vs soil walls `#351f13` (~4:1). Our current build's match lighting is flat and even (sun 1.15 + white ambient + sky energy 1.2 everywhere). The target look *is* this contrast: glowing pockets of warmth floating in darkness.

**Ingredient 2 — Warm chamber glow with amber falloff.**
Highlights: `#f4c0a1` (peachy), `#fecf9f` (amber), `#fff4df` (warm white). Ambient chamber tone `#885230`. Reads as 2–3 warm point lights per chamber with fast falloff. Consistently warm (~2700–3500K feel); no cool light underground.

**Ingredient 3 — Soil reads rich via 3 scales of detail.**
- Large: mottled brown masses, avg `#351f13`, brightest `#ac7d59`.
- Medium: embedded pebbles/stones (discrete light spots).
- Fine: grain/noise + near-black root strands (`#090301`).
Our `terrain_rich.png` has large mottling but lacks the pebble and root-strand scales.

**Ingredient 4 — Chitin with subsurface warmth.**
Queen gaster highlight vivid amber `#fea14a` (transmitted/backlit, not specular). Queen head `#bb7836`. Gaster base `#4b220d`. Workers: reddish thorax/head, dark gasters. Read: dark warm base + amber glow where light passes through + bright specular rim on edges. Subsurface scattering + rim, not plain PBR.

**Ingredient 5 — Bright rim on silhouettes.**
Every ant has a bright edge highlight separating it from dark soil. The rim does the readability work.

**Ingredient 6 — Dense detail everywhere (horror vacui).**
Eggs (cream `#e5c5ab`), larvae, mushrooms, seed piles, pebbles, rootlets — no flat surfaces.

**Ingredient 7 — Surface cap.**
Soil band `#3d2719`, grass `#393e24`–`#8d945f` (muted olive, NOT vivid green), moss, pebbles. Our grass is more saturated than target.

**Ingredient 8 — Atmospheric depth.**
Deeper chambers darker/lower-contrast; dust motes in brightest chamber; volumetric-feeling light.

### 1B. Empire of the Ants (surface reference)

**Ingredient 9 — Warm/cool color contrast.** Golden-hour sun (~`#ff9a50`) vs cool blue ambient/sky (`#86afd2` zenith, `#2a2f3a` mist). Our build is warm-on-warm — lacks the cool counterpoint.

**Ingredient 10 — Backlit translucency on chitin.** Thorax base `#481c16`, highlight `#c08064` — glow from light *behind/through* the ant. The most "alive" quality in the reference.

**Ingredient 11 — Atmospheric perspective.** Distant trees fade blue-gray. Our fog is warm-toned; reference fog is cool.

**Ingredient 12 — Muted vegetation.** Ferns lit `#3f3e3c`, shadow `#312923` — desaturated olive-brown.

### 1C. EotU underground

**Ingredient 13 — Chamber floor material zones.** Distinct floors per function (leaf-litter, fungus, seeds, eggs). Color-coding = readability + richness.

**Ingredient 14 — Glowing pheromone trails.** Cyan/red emissive lines on dark ground, subtle bloom.

**Ingredient 15 — Unlit = black.** Unexcavated areas near-black; darkness is a feature (focus + mood).

---

## 2. How to reproduce in Godot 4.7

### Chitin (Ingredients 4, 5, 10) — `source/match/players/Player.gd`
Current material (dark albedo, roughness 0.55, specular 0.38) is a correct base; add:
- **Backlit translucency:** `subsurface_scattering_strength` 0.3–0.5. Godot 4 SSS tints transmitted light toward albedo (warm brown → amber glow), reproducing the queen-gaster effect when backlit. Works on Compatibility (screen-space) and Forward Plus.
- **Rim:** `rim` 0.6–1.0, `rim_tint` 0.5. Cheap, all renderers. Gives silhouette separation.
- Keep roughness ~0.5–0.6, specular ~0.35–0.45 (do not go glossier; blowout lesson stands).
- Optional HIGH-tier: subtle `emission` ~0.15 energy in warm amber to fake subsurface glow where SSS is subtle.

### Warm/cool lighting rig (Ingredients 1, 2, 9) — `source/match/Match.tscn`
- Sun: `DirectionalLight3D` warm `(1.0, 0.85, 0.70)`, energy ~1.1.
- Ambient/sky: **cool blue-gray** `(0.45, 0.55, 0.70)`; ProceduralSkyMaterial cooler zenith, warm horizon.
- Tonemap: keep ACES (`tonemap_mode = 3`), exposure 0.9.
- Underground (future): per-chamber `OmniLight3D` `#ff9a3c`-ish, energy 2–3, range = chamber radius, `shadow_enabled = false`.

### Glow/bloom (Ingredients 2, 14) — Environment
`glow_enabled = true`, `glow_intensity` ~0.4, `glow_strength` ~1.0, `glow_bloom` ~0.2, blend softlight/screen. Supported on Compatibility (verify on-device); gate to MEDIUM/HIGH if costly.

### Fog and atmosphere (Ingredients 8, 11) — Environment
- Surface: `fog_light_color` cool `(0.55, 0.65, 0.80)`, `fog_density` ~0.0016, height fog on. Non-volumetric fog works on Compatibility.
- HIGH/PC: `volumetric_fog_enabled`, density 0.01–0.03, warm light color. **Forward Plus only.**
- Fake light shafts (all renderers): cone meshes + additive gradient shader; HIGH = shafts + volumetrics, MEDIUM = shafts, LOW = neither.

### Soil richness (Ingredient 3) — `assets/textures/terrain_rich.png`, `dirt_rich.png`
Add at bake time (same Python pipeline):
- Medium: ~200–400 bright speckles (pebble grit, 2–6px, `#ac7d59`-ish) per 512² tile.
- Fine: dark rootlet strokes (thin branching random-walks, `#0a0503`, ~30–60/tile) + fine grain.
- Optional roughness map (pebbles glossier than soil). All Compatibility-safe.

### Vegetation (Ingredients 7, 12)
- Desaturate blade texture ~20% toward olive (`#6c6c2b`–`#8d945f`); keep per-blade variation + tip translucency, retarget palette.
- Add clover/moss tufts (3-quad, procedural texture, same wind shader).
- Compatibility-safe (alpha scissor).

### Dust motes (Ingredient 8)
`GPUParticles3D` (HIGH) / `CPUParticles3D` (MEDIUM, safer on weak GPUs), 40–80 additive billboards drifting above nest / in shafts. Gate via `QualityManager.scale_particle_amount()`.

### Pheromone trails (Ingredient 14)
Add `emission` to trail-dot material (cyan `#40e0d0` friendly, red `#ff4040` alarm), energy 1.5–2.0. Zero extra draw calls; bloom picks it up on MEDIUM/HIGH.

### Surface detail density (Ingredient 6)
Increase `Decorations` counts on HIGH; add seed piles (~40 tris), leaf-litter patches, small mushrooms near mound. Under existing `Decorations` node → tier gating automatic.

---

## 3. Mobile-tier mapping

| Technique | LOW (mobile default) | MEDIUM | HIGH (PC) |
|---|---|---|---|
| Chitin SSS + rim + backlight | SSS off, rim on, backlight on | SSS 0.3, rim on | SSS 0.5, rim on, subtle emission |
| Warm sun + cool ambient | Yes (free) | Yes | Yes |
| Glow/bloom | Off | On (verify cost) | On |
| Fog (non-volumetric, cool) | Yes, lower density | Yes | Yes |
| Volumetric fog | — | — | On (Forward+ only) |
| Fake light shafts | — | On | On |
| Dust motes | — | CPU, 50% | GPU, 100% |
| Soil 3-scale textures | Yes (free) | Yes | Yes |
| Vegetation desat + clover | Yes (free) | Yes | Yes |
| Prop density | 40% | 70% | 100% + new props |
| Shadows | Off | 1024 | Scene default |
| Pheromone emission | On, no bloom | On + bloom | On + bloom |
| MSAA | Off | Off | Project default |

SSS, rim, backlighting, emission, cool ambient, fog, textures: all Compatibility-safe. Volumetric fog is Forward Plus-only. Recommend against SDFGI/SSAO (costly, marginal gain; baked warm/cool contrast carries the look).

---

## 4. Surface vs. underground split

### (a) Surface game NOW
Chitin SSS/rim/backlight; warm sun + cool ambient + cool fog; glow/bloom; soil 3-scale textures; vegetation desat + clover/moss + leaf litter; dust motes; fake light shafts; prop density + new surface props; nest mound as dark rich soil with pebbles.

### (b) Bank for UNDERGROUND phases
- Per-chamber warm OmniLight3D rig (2–3 amber lights/chamber, fast falloff) — design chamber system with light anchor points from day one.
- Excavated walls: 3-scale soil + warm rim; unexcavated: near-black (darkness as feature).
- Root strands along chamber ceilings (thin cylinders, dark bark, procedural).
- Chamber floor zones per function (brood/fungus/storage/waste color-coding).
- Brood visuals: egg clusters (cream, slight emission), larvae, pupae.
- Queen chamber: larger, stronger warm light, SSS maxed — visual centerpiece.
- Light-shaft cones from surface entrances into top chambers.
- Pheromone glow (higher payoff underground on dark backgrounds).

---

## 5. Prioritized action list

1. **Chitin: SSS + rim + backlight** (`Player.gd`). SSS 0.35, rim 0.8, backlight on. Biggest ant-quality jump. Tier: SSS off LOW, rim always. Risk: low; keep spec ≤0.4.
2. **Warm/cool lighting rig** (`Match.tscn` Environment + DirectionalLight3D). Instant cinematic contrast, nearly free. All tiers. Risk: none.
3. **Glow/bloom** (Environment). Sells trails/rim/chamber warmth later. MEDIUM/HIGH. Risk: verify Compatibility cost.
4. **Soil 3-scale texture pass** (bake script). Kills flat-terrain read. All tiers, free. Risk: none.
5. **Vegetation palette + clover** (blade texture, shader, new tuft). Kills "astroturf" read. All tiers. Risk: low.
6. **Dust motes** (particles, nest area). Cheapest atmosphere. MEDIUM/HIGH. Risk: negligible.
7. **Pheromone trail emission**. EotU-style glow, zero draw calls. All tiers. Risk: none.
8. **Nest mound upgrade** (dark soil + pebbles, amber entrance light). Weakest hero asset currently. All tiers; light MEDIUM/HIGH. Risk: low.
9. **New surface props** (seeds, leaf litter, mushrooms). Density. Auto-tiered. Risk: minor tris; keep <60 each.
10. **Fake light shafts**. Volumetric feel, Compatibility-safe. MEDIUM/HIGH. Risk: low.
11. **Cool fog + exposure tune**. Depth cueing. All tiers. Risk: none; re-check ant readability after.
12. **[Underground, bank] Chamber light-rig spec.** Design doc now, implement with excavation phase.

**Suggested sequencing:** 2 → 1 → 4 → 5 → 3 → 7 → 6 → 8 → 9 → 10 → 11, with 12 as parallel design doc. Items 1–5 are the 80/20.
