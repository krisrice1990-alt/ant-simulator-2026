# Changelog

## [main]

### New features
 - Added structure rally points
 - Phase 2 species pack: 7 playable ant species (garden, leafcutter, army ant,
   fire ant, carpenter, trap-jaw, weaver), each with unique unit stats, one
   unique structure, and one unique mechanic (venom DoT, swarm fury, mandible
   strike burst, fungus farming, nomadic bivouac, wood-chewing, silk building);
   species select at match setup; AI temperaments per species
 - Phase 2 bug bestiary: beetles (armored prey), wasps (air raiders hunting
   laden workers), centipedes (venomous brood hunters), scorpions (apex
   mini-bosses guarding protein), aphids (milkable livestock), wood barriers
   (carpenter-only chewable), and a rival termite colony faction with mound,
   workers, soldiers, and raid parties; BestiarySpawner seeds wildlife and
   runs wasp/centipede events
 - Excavation spoil piles: dug tunnel cells produce a dirt pellet the worker
   visibly carries; dirt lands in growing surface spoil piles offset from the
   nest entrance; haul distance slows dig ticks (foraging-style economy)

### Changed
 - Godot 4.1 support added instead of Godot 4.0 (4.0 support is still present on branch)

## [0.9.0]

### New features
 - Added 'loading page' translations
 - Added ability to use custom maps
 - Added 2 new maps
 - Added match setup page

### Changed
 - Performed various refactorings
 - Simplified turret's rotation algorithm
 - Removed redundant unit groups
 - Extracted generic `MouseClickAnimation`
 - Improved `assert()` calls
 - Renamed `buildings` to - more generic - `structures`
 - Made `SimpleClairvoyantAI` being able to attach units in runtime

## [0.8.1]

### New features
 - Added resource tooltips
 - Added unit production/construction tooltips
 - Added main menu background
 - Added match loading page
 - Added diagnostic FPS monitor

### Changed
 - Increased units HP by a factor of 2

## [0.8.0]

### New features
 - Added animated logo sequence on startup
 - Added basic main menu with options etc.
 - Added match with hardcoded map and features such as:
   - Settings
   - Isometric 3D camera
   - Fog of war
   - Terrain/Air navigation
   - Units & structures
   - Resources (blue/red crystals)
   - UI (unit selection mechanism)
   - HUD (resource counters, unit management panels)
   - Menu
   - Dynamically created human/AI players
   - Debug utilities (God mode etc.)
