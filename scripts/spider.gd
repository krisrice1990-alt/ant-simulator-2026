class_name Spider
extends Node
## Enemy: stalks in from the surface toward the nest entrance, attacks
## ants, then descends to hunt the queen.
##
## Game logic runs in 2D logic space (position is a Vector2, as before).
## The 3D body is built from primitives and synced to the logic position.

signal died(spider: Spider)

enum SState { SEEK, DESCEND, HUNT }

var hp := 35.0
var max_hp := 35.0
var speed := 58.0
var colony: Colony
var game # Main game manager
var state: int = SState.SEEK
var position := Vector2.ZERO # logic-space position (Vector2, as before)
var path: Array = [] # Array[Vector2]
var attack_cd := 0.0
var facing := -1.0
var step_phase := 0.0
var flash := 0.0

# 3D visual nodes.
var _root: Node3D
var _body: Node3D
var _legs: Array = [] # Array[Node3D] hip pivots
var _leg_phase: Array = [] # Array[float] alternating tetrapod phase
var _fang_l: MeshInstance3D
var _fang_r: MeshInstance3D
var _body_mat: StandardMaterial3D
var _hp_bg: MeshInstance3D
var _hp_fg: MeshInstance3D
var _move_blend := 0.0
var _last_pos := Vector2.ZERO


func setup(p_colony: Colony, p_game, pos: Vector2, p_hp: float) -> void:
	colony = p_colony
	game = p_game
	position = pos
	_last_pos = pos
	hp = p_hp
	max_hp = p_hp
	_build_visual()
	_sync_visual()


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	flash = 0.12
	if hp <= 0.0:
		game.on_spider_killed(self)
		died.emit(self)
		queue_free()


func _physics_process(delta: float) -> void:
	if game == null or game.game_over:
		return
	attack_cd = maxf(0.0, attack_cd - delta)
	flash = maxf(0.0, flash - delta)
	var moved: float = position.distance_to(_last_pos) / maxf(delta, 0.0001)
	_last_pos = position
	_move_blend = lerpf(_move_blend, 1.0 if moved > 8.0 else 0.0, minf(1.0, delta * 8.0))
	step_phase += delta * (8.0 + moved * 0.05) * (0.25 + 0.75 * _move_blend)
	match state:
		SState.SEEK:
			_seek(delta)
		SState.DESCEND:
			var et := colony.world_of_tile(Vector2i(Colony.ENTRANCE_COL, 0))
			if _move_toward(et, delta):
				state = SState.HUNT
				_path_to_queen()
		SState.HUNT:
			_hunt(delta)
	_sync_visual()


func _seek(delta: float) -> void:
	# Attack any ant close by instead of moving.
	var ant: Ant = game.nearest_ant(position, 36.0)
	if ant != null:
		if attack_cd <= 0.0:
			ant.take_damage(6.0)
			attack_cd = 0.8
		return
	var ex := colony.entrance_world_x()
	if absf(position.x - ex) < 26.0:
		state = SState.DESCEND
		return
	_move_toward(Vector2(ex, Colony.SURFACE_Y - 6.0), delta)


func _hunt(delta: float) -> void:
	var q: Ant = game.queen
	if q != null and is_instance_valid(q):
		if position.distance_to(q.position) < 42.0:
			if attack_cd <= 0.0:
				q.take_damage(9.0)
				attack_cd = 1.0
			return
	# Swat nearby ants while hunting.
	var ant: Ant = game.nearest_ant(position, 34.0)
	if ant != null and attack_cd <= 0.0:
		ant.take_damage(6.0)
		attack_cd = 0.8
	if path.is_empty():
		_path_to_queen()
	else:
		_follow_path(delta)


func _path_to_queen() -> void:
	path.clear()
	var q: Ant = game.queen
	if q == null or not is_instance_valid(q):
		return
	var cur := colony.tile_at_world(position)
	var qt := colony.tile_at_world(q.position)
	var steps: Array = colony.find_path(cur, qt)
	for s in steps:
		path.append(colony.world_of_tile(s))


func _move_toward(p: Vector2, delta: float) -> bool:
	var d: Vector2 = p - position
	var dist := d.length()
	if dist < 5.0:
		return true
	position += d.normalized() * minf(speed * delta, dist)
	if absf(d.x) > 1.0:
		facing = signf(d.x)
	return false


func _follow_path(delta: float) -> bool:
	if path.is_empty():
		return true
	if _move_toward(path[0], delta):
		path.pop_front()
	return path.is_empty()


# ---- 3D visuals ------------------------------------------------------------

func _build_visual() -> void:
	Geo3D.ensure()
	# Per-spider body material so the damage flash doesn't affect others.
	# Glossy dark chitin with a hint of menace.
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color("#1c1c22")
	_body_mat.roughness = 0.3
	_body_mat.metallic = 0.15
	_body_mat.metallic_specular = 0.85
	var leg_mat := Geo3D.chitin("spider_leg", Color("#26262e"), 0.4)

	_root = Node3D.new()
	_root.name = "Visual"
	add_child(_root)
	_body = Node3D.new()
	_root.add_child(_body)

	# Segmented abdomen (two lobes) and cephalothorax.
	Geo3D.part(_body, Geo3D.sphere, Vector3(-0.34, 0.34, 0), Vector3(0.52, 0.46, 0.48), _body_mat)
	Geo3D.part(_body, Geo3D.sphere, Vector3(-0.10, 0.32, 0), Vector3(0.40, 0.40, 0.42), _body_mat)
	Geo3D.part(_body, Geo3D.sphere, Vector3(0.28, 0.30, 0), Vector3(0.40, 0.36, 0.38), _body_mat)
	# Spinneret dots.
	var silk := Geo3D.mat("spider_silk", Color("#8a8a92"))
	Geo3D.part(_body, Geo3D.sphere, Vector3(-0.58, 0.30, 0.08), Vector3(0.08, 0.08, 0.08), silk)
	Geo3D.part(_body, Geo3D.sphere, Vector3(-0.58, 0.30, -0.08), Vector3(0.08, 0.08, 0.08), silk)
	# Fangs (raise when striking).
	for side in [-1.0, 1.0]:
		var fang := MeshInstance3D.new()
		fang.mesh = Geo3D.leg_mesh
		fang.scale = Vector3(0.10, 0.26, 0.10)
		fang.position = Vector3(0.50, 0.12, side * 0.10)
		fang.rotation.z = 0.6
		fang.material_override = leg_mat
		fang.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(fang)
		if side < 0.0:
			_fang_l = fang
		else:
			_fang_r = fang
	# Cluster of red eyes.
	var eye := Geo3D.glow("spider_eye", Color("#ff2e2e"), 2.0)
	Geo3D.part(_body, Geo3D.sphere, Vector3(0.44, 0.40, 0.0), Vector3(0.11, 0.11, 0.11), eye)
	Geo3D.part(_body, Geo3D.sphere, Vector3(0.40, 0.34, 0.12), Vector3(0.08, 0.08, 0.08), eye)
	Geo3D.part(_body, Geo3D.sphere, Vector3(0.40, 0.34, -0.12), Vector3(0.08, 0.08, 0.08), eye)

	# Eight tapered legs, alternating tetrapod gait.
	for i in 4:
		for side in [-1.0, 1.0]:
			var hip := Node3D.new()
			hip.position = Vector3((-0.30 + i * 0.22), 0.28, side * 0.18)
			hip.rotation.x = side * 0.65
			_body.add_child(hip)
			var leg := MeshInstance3D.new()
			leg.mesh = Geo3D.leg_mesh
			leg.scale = Vector3(0.09, 0.95, 0.09)
			leg.position = Vector3(0, -0.46, 0)
			leg.material_override = leg_mat
			leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hip.add_child(leg)
			_legs.append(hip)
			var side_idx := 0 if side < 0.0 else 1
			_leg_phase.append(0.0 if (i + side_idx) % 2 == 0 else PI)

	# HP bar (not flipped with the body).
	var top := Node3D.new()
	_root.add_child(top)
	_hp_bg = Geo3D.part(top, Geo3D.box, Vector3(0, 1.0, 0), Vector3(0.9, 0.10, 0.03), Geo3D.mat("hpbg", Color("#1a1a1a")))
	_hp_fg = Geo3D.part(top, Geo3D.box, Vector3(0, 1.0, 0.005), Vector3(0.9, 0.10, 0.03), Geo3D.glow("hpf", Color("#ff5a4e"), 0.8))


func _sync_visual() -> void:
	if _root == null or colony == null:
		return
	_root.position = colony.to_3d(position) + Vector3(0, 0, Colony.ENTITY_Z)
	_body.rotation.y = PI if facing < 0.0 else 0.0
	for i in _legs.size():
		var hip: Node3D = _legs[i]
		hip.rotation.z = sin(step_phase + _leg_phase[i]) * 0.5 * _move_blend
	# Body sway while walking; fangs lift right after a strike.
	_body.position.y = sin(step_phase * 2.0) * 0.03 * _move_blend
	_body.rotation.z = sin(step_phase) * 0.04 * _move_blend
	var strike := 0.0
	if attack_cd > 0.55:
		strike = (attack_cd - 0.55) / 0.25
	if _fang_l != null:
		_fang_l.rotation.z = 0.6 - strike * 0.7
		_fang_r.rotation.z = 0.6 - strike * 0.7
	_body_mat.albedo_color = Color("#7a2020") if flash > 0.0 else Color("#1c1c22")
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	_hp_fg.scale.x = 0.9 * frac
	_hp_fg.position.x = -0.45 * (1.0 - frac)
