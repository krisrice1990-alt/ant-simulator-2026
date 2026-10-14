class_name Colony
extends Node3D
## Underground tile grid: dirt to dig, open tunnels, rock borders.
##
## Game logic runs in 2D "logic space" (pixels, y-down, surface at SURFACE_Y),
## exactly as before. to_3d()/from_3d() map logic space onto the 3D ant-farm
## cutaway: one 40px tile = 1.0 world unit, surface at y=0, depth going -y.
## Entities live on the ENTITY_Z plane, just in front of the dirt slab.
##
## Presentation: the surface is a narrow grass strip (never a deep slab, so it
## can never occlude the tunnels). When the camera dives underground the
## surface props fade out automatically so the colony stays readable.

signal tile_dug(tile: Vector2i)

const COLS := 26
const ROWS := 13
const TILE := 40.0
const OX := 120.0
const OY := 180.0
const SURFACE_Y := 180.0
const VIEW_W := 1280.0
const VIEW_H := 720.0
const ENTRANCE_COL := 13
const QUEEN_TILE := Vector2i(12, 5)
const STORAGE_TILE := Vector2i(13, 6)

const T_DIRT := 0
const T_OPEN := 1
const T_ROCK := 2

# Logic-space (px) -> world units.
const WORLD_S := 0.025
# Z of the gameplay plane: just in front of the dirt slab's front face.
const ENTITY_Z := 0.55

var tiles: Array = [] # tiles[row][col] -> int

# Set by main.gd so the surface can fade when the camera goes underground.
var view_rig: CameraRig = null

var _dirt_mm: MultiMeshInstance3D
var _tile_box: BoxMesh
var _surf_mats: Array = [] # materials faded when underground
var _fade := 0.0


func to_3d(p: Vector2) -> Vector3:
	return Vector3((p.x - VIEW_W * 0.5) * WORLD_S, (SURFACE_Y - p.y) * WORLD_S, 0.0)


func from_3d(v: Vector3) -> Vector2:
	return Vector2(v.x / WORLD_S + VIEW_W * 0.5, SURFACE_Y - v.y / WORLD_S)


func _ready() -> void:
	generate()
	_build_terrain()


func _process(_delta: float) -> void:
	# Fade the surface props out as the camera dives into the colony so the
	# tunnels, queen and eggs stay visible and tappable.
	var want := 0.0
	if view_rig != null:
		want = clampf((-view_rig.target.y - 2.5) / 4.5, 0.0, 1.0)
	if absf(want - _fade) > 0.001:
		_fade = want
		for m in _surf_mats:
			var c: Color = m.get_meta("base_color")
			c.a = 1.0 - 0.82 * _fade
			m.albedo_color = c


func generate() -> void:
	tiles.clear()
	for r in ROWS:
		var row: Array = []
		for _c in COLS:
			row.append(T_DIRT)
		tiles.append(row)
	# Rock borders: left, right, bottom.
	for r in ROWS:
		tiles[r][0] = T_ROCK
		tiles[r][COLS - 1] = T_ROCK
	for c in COLS:
		tiles[ROWS - 1][c] = T_ROCK
	# Entrance shaft at the surface.
	tiles[0][ENTRANCE_COL] = T_OPEN
	# Starter vertical shaft down to the chamber.
	for r in range(1, 5):
		tiles[r][ENTRANCE_COL] = T_OPEN
	# Starting chamber.
	for r in range(5, 7):
		for c in range(11, 15):
			tiles[r][c] = T_OPEN


func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < COLS and t.y < ROWS


func is_open(t: Vector2i) -> bool:
	return in_bounds(t) and tiles[t.y][t.x] == T_OPEN


func is_diggable(t: Vector2i) -> bool:
	if not in_bounds(t):
		return false
	if tiles[t.y][t.x] != T_DIRT:
		return false
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		if is_open(t + d):
			return true
	return false


func dig(t: Vector2i) -> bool:
	if not is_diggable(t):
		return false
	tiles[t.y][t.x] = T_OPEN
	tile_dug.emit(t)
	_refresh_dirt()
	return true


func world_of_tile(t: Vector2i) -> Vector2:
	return Vector2(OX + t.x * TILE + TILE * 0.5, OY + t.y * TILE + TILE * 0.5)


func tile_at_world(p: Vector2) -> Vector2i:
	var c := int(floor((p.x - OX) / TILE))
	var r := int(floor((p.y - OY) / TILE))
	c = clampi(c, 0, COLS - 1)
	r = clampi(r, 0, ROWS - 1)
	return Vector2i(c, r)


func entrance_world_x() -> float:
	return world_of_tile(Vector2i(ENTRANCE_COL, 0)).x


func surface_point(x: float) -> Vector2:
	return Vector2(x, SURFACE_Y - 6.0)


func open_neighbor_of(t: Vector2i) -> Vector2i:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		if is_open(t + d):
			return t + d
	return Vector2i(-1, -1)


## Nearest open tile to t (BFS, bounded). Returns (-1,-1) if none found.
func nearest_open_tile(t: Vector2i) -> Vector2i:
	t = Vector2i(clampi(t.x, 0, COLS - 1), clampi(t.y, 0, ROWS - 1))
	if is_open(t):
		return t
	var seen := {t: true}
	var queue: Array = [t]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var guard := 0
	while not queue.is_empty() and guard < 400:
		guard += 1
		var cur: Vector2i = queue.pop_front()
		for d in dirs:
			var nxt: Vector2i = cur + d
			if in_bounds(nxt) and not seen.has(nxt):
				seen[nxt] = true
				if is_open(nxt):
					return nxt
				queue.append(nxt)
	return Vector2i(-1, -1)


## Breadth-first path over open tiles. Returns tile steps excluding start.
func find_path(from: Vector2i, to: Vector2i) -> Array:
	var result: Array = []
	if not is_open(from) or not is_open(to):
		return result
	if from == to:
		return result
	var prev := {}
	var queue: Array = [from]
	prev[from] = from
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			break
		for d in dirs:
			var nxt: Vector2i = cur + d
			if is_open(nxt) and not prev.has(nxt):
				prev[nxt] = cur
				queue.append(nxt)
	if not prev.has(to):
		return result
	var step: Vector2i = to
	while step != from:
		result.push_front(step)
		step = prev[step]
	return result


func _hash2(c: int, r: int, salt: int) -> int:
	var h := (c * 73856093) ^ (r * 19349663) ^ (salt * 83492791)
	h = h & 0x7fffffff
	return h


# ---- 3D terrain ------------------------------------------------------------

func _surf_mat(color: Color) -> StandardMaterial3D:
	# Dedicated surface material (not shared) so it can fade independently.
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.set_meta("base_color", color)
	_surf_mats.append(m)
	return m


func _solid_mat(color: Color) -> StandardMaterial3D:
	# Opaque material for dirt/rock: these must NEVER fade, or the tunnels
	# would go invisible exactly when the camera dives in to look at them.
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m


func _build_terrain() -> void:
	_tile_box = BoxMesh.new()
	_tile_box.size = Vector3(0.96, 0.96, 0.8)

	# Dirt tiles with per-instance color variation (rebuilt when dug).
	var dirt_mm := MultiMesh.new()
	dirt_mm.transform_format = MultiMesh.TRANSFORM_3D
	dirt_mm.use_colors = true
	dirt_mm.mesh = _tile_box
	_dirt_mm = MultiMeshInstance3D.new()
	_dirt_mm.multimesh = dirt_mm
	_dirt_mm.material_override = _solid_mat(Color("#4a2e1a"))
	_dirt_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dirt_mm)
	_refresh_dirt()

	# Rock borders (static, slight variation).
	var rock_mm := MultiMesh.new()
	rock_mm.transform_format = MultiMesh.TRANSFORM_3D
	rock_mm.use_colors = true
	rock_mm.mesh = _tile_box
	var rock_xf: Array = []
	var rock_col: Array = []
	for r in ROWS:
		for c in COLS:
			if tiles[r][c] == T_ROCK:
				rock_xf.append(Transform3D(Basis(), to_3d(world_of_tile(Vector2i(c, r)))))
				var v := 0.92 + float(_hash2(c, r, 11) % 16) / 100.0
				rock_col.append(Color(0.31 * v, 0.31 * v, 0.34 * v))
	rock_mm.instance_count = rock_xf.size()
	for i in rock_xf.size():
		rock_mm.set_instance_transform(i, rock_xf[i])
		rock_mm.set_instance_color(i, rock_col[i])
	var rock_mmi := MultiMeshInstance3D.new()
	rock_mmi.multimesh = rock_mm
	rock_mmi.material_override = _solid_mat(Color("#4e4f55"))
	rock_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rock_mmi)

	# Dark backdrop behind the slab: tunnels read as dark cavities.
	var back := MeshInstance3D.new()
	var back_box := BoxMesh.new()
	back_box.size = Vector3(27.5, 14.5, 0.4)
	back.mesh = back_box
	back.position = Vector3(0, -6.75, -0.75)
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color("#0f0a06")
	back_mat.roughness = 1.0
	back.material_override = back_mat
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)

	# Warm amber tunnel lights: tight pools of lantern glow in the chambers,
	# not a wash over the whole slab — the soil must stay dark and rich.
	# No shadows, small ranges — cheap even on phones.
	for lp in [Vector3(0, -5.5, 1.6), Vector3(0.25, -2.5, 1.6), Vector3(-3.0, -8.0, 1.6)]:
		var omni := OmniLight3D.new()
		omni.position = lp
		omni.light_color = Color("#ff9a3c")
		omni.light_energy = 1.1
		omni.omni_range = 4.5
		omni.omni_attenuation = 1.2
		omni.shadow_enabled = false
		add_child(omni)
	# Extra glow in the queen's chamber: the heart of the colony.
	var qp := to_3d(world_of_tile(QUEEN_TILE))
	var qomni := OmniLight3D.new()
	qomni.position = qp + Vector3(0, 0.6, 1.6)
	qomni.light_color = Color("#ffb35c")
	qomni.light_energy = 1.0
	qomni.omni_range = 4.0
	qomni.omni_attenuation = 1.2
	qomni.shadow_enabled = false
	add_child(qomni)

	# Grass surface: a narrow strip, NEVER a deep slab, so it cannot occlude
	# the underground cutaway no matter the camera angle.
	var surf := Node3D.new()
	surf.name = "Surface"
	add_child(surf)
	var grass := MeshInstance3D.new()
	var grass_box := BoxMesh.new()
	grass_box.size = Vector3(46, 0.6, 10)
	grass.mesh = grass_box
	grass.position = Vector3(0, -0.31, 2.0)
	grass.material_override = _surf_mat(Color("#3e5c2a"))
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surf.add_child(grass)
	# Lighter grass tuft strip on top for depth.
	var grass2 := MeshInstance3D.new()
	var grass2_box := BoxMesh.new()
	grass2_box.size = Vector3(46, 0.12, 10)
	grass2.mesh = grass2_box
	grass2.position = Vector3(0, -0.03, 2.0)
	grass2.material_override = _surf_mat(Color("#48632d"))
	grass2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surf.add_child(grass2)

	# Entrance hole marker on the surface.
	var ex3d := to_3d(Vector2(entrance_world_x(), SURFACE_Y))
	var hole := MeshInstance3D.new()
	var hole_cyl := CylinderMesh.new()
	hole_cyl.top_radius = 0.42
	hole_cyl.bottom_radius = 0.5
	hole_cyl.height = 0.3
	hole_cyl.radial_segments = 16
	hole.mesh = hole_cyl
	hole.position = Vector3(ex3d.x, 0.1, ENTITY_Z)
	hole.material_override = _surf_mat(Color("#14100b"))
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surf.add_child(hole)

	# Grass blades: natural varied green (per-instance color), never neon.
	var blade := CylinderMesh.new()
	blade.top_radius = 0.0
	blade.bottom_radius = 0.07
	blade.height = 0.8
	blade.radial_segments = 5
	var blade_mm := MultiMesh.new()
	blade_mm.transform_format = MultiMesh.TRANSFORM_3D
	blade_mm.use_colors = true
	blade_mm.mesh = blade
	var n_blades := 70
	blade_mm.instance_count = n_blades
	for i in n_blades:
		var h := _hash2(i, 7, 3)
		var bx := -20.0 + float(h % 400) * 0.1
		var bz := -2.0 + float((h / 400) % 80) * 0.1
		var lean := float((h / 32000) % 20 - 10) * 0.02
		var basis := Basis(Vector3(0, 0, 1), lean)
		blade_mm.set_instance_transform(i, Transform3D(basis, Vector3(bx, 0.4, bz)))
		# Natural grass: desaturated greens with per-blade variation, plus dry
		# yellowish blades mixed in. No neon.
		var lv := float((h / 640000) % 100) / 100.0
		if h % 6 == 0:
			blade_mm.set_instance_color(i, Color(0.42 + lv * 0.10, 0.35 + lv * 0.08, 0.15 + lv * 0.05))
		else:
			blade_mm.set_instance_color(i, Color(0.18 + lv * 0.10, 0.28 + lv * 0.12, 0.11 + lv * 0.06))
	var blades := MultiMeshInstance3D.new()
	blades.multimesh = blade_mm
	blades.material_override = _surf_mat(Color("#ffffff"))
	blades.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surf.add_child(blades)

	# Dirt-brown patches breaking up the grass: natural, not mottled neon.
	var patch_mm := MultiMesh.new()
	patch_mm.transform_format = MultiMesh.TRANSFORM_3D
	patch_mm.use_colors = true
	patch_mm.mesh = Geo3D.box
	var n_patch := 10
	patch_mm.instance_count = n_patch
	for i in n_patch:
		var h := _hash2(i, 55, 13)
		var px := -19.0 + float(h % 380) * 0.1
		var pz := -1.5 + float((h / 380) % 60) * 0.1
		var pw := 1.2 + float((h / 22800) % 20) * 0.12
		patch_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(px, 0.02, pz)).scaled(Vector3(pw, 0.06, pw * 0.7)))
		var v := float((h / 456000) % 100) / 100.0
		patch_mm.set_instance_color(i, Color(0.36 + v * 0.10, 0.25 + v * 0.07, 0.15 + v * 0.05))
	var patches := MultiMeshInstance3D.new()
	patches.multimesh = patch_mm
	patches.material_override = _surf_mat(Color("#ffffff"))
	patches.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surf.add_child(patches)

	# Pebbles: backyard-at-ant-scale feel, cheap and static.
	var peb_mm := MultiMesh.new()
	peb_mm.transform_format = MultiMesh.TRANSFORM_3D
	peb_mm.use_colors = true
	peb_mm.mesh = Geo3D.sphere
	var n_peb := 14
	peb_mm.instance_count = n_peb
	for i in n_peb:
		var h := _hash2(i, 21, 5)
		var px := -19.0 + float(h % 380) * 0.1
		var pz := -2.0 + float((h / 380) % 70) * 0.1
		var ps := 0.25 + float((h / 26600) % 20) * 0.02
		peb_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(px, ps * 0.5, pz)).scaled(Vector3(ps, ps * 0.7, ps)))
		var g := 0.45 + float((h / 532000) % 20) / 100.0
		peb_mm.set_instance_color(i, Color(g, g, g * 1.05))
	var pebbles := MultiMeshInstance3D.new()
	pebbles.multimesh = peb_mm
	pebbles.material_override = _surf_mat(Color("#777777"))
	pebbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surf.add_child(pebbles)

	# Fallen twigs.
	var twig_mm := MultiMesh.new()
	twig_mm.transform_format = MultiMesh.TRANSFORM_3D
	twig_mm.mesh = Geo3D.cyl
	var n_twig := 5
	twig_mm.instance_count = n_twig
	for i in n_twig:
		var h := _hash2(i, 33, 9)
		var tx := -16.0 + float(h % 320) * 0.1
		var tz := -1.0 + float((h / 320) % 50) * 0.1
		var rot := Basis(Vector3(0, 1, 0), float(h % 314) / 100.0) * Basis(Vector3(0, 0, 1), PI / 2.0)
		var tl := 2.0 + float((h / 100480) % 20) * 0.1
		twig_mm.set_instance_transform(i, Transform3D(rot.scaled(Vector3(tl, 0.22, 0.22)), Vector3(tx, 0.12, tz)))
	var twigs := MultiMeshInstance3D.new()
	twigs.multimesh = twig_mm
	twigs.material_override = _surf_mat(Color("#5d4126"))
	twigs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surf.add_child(twigs)


func _refresh_dirt() -> void:
	if _dirt_mm == null:
		return
	var xf: Array = []
	var cols: Array = []
	for r in ROWS:
		for c in COLS:
			if tiles[r][c] == T_DIRT:
				xf.append(Transform3D(Basis(), to_3d(world_of_tile(Vector2i(c, r)))))
				# Rich dark soil like the reference: deep browns that stay
				# dark even under the warm tunnel lights, never terracotta.
				var v := float(_hash2(c, r, 4) % 100) / 100.0
				cols.append(Color(0.36 + v * 0.15, 0.32 + v * 0.13, 0.28 + v * 0.11))
	var mm := _dirt_mm.multimesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
