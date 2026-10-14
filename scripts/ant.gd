class_name Ant
extends Node
## A single ant: worker, soldier or queen. Workers dig and forage,
## soldiers guard and fight, the queen stays in the chamber.
##
## Game logic runs in 2D logic space (position is a Vector2, as before).
## The 3D body is built from primitives and synced to the logic position.
##
## Animation is fully procedural: alternating tripod gait, body bob and roll,
## antennae wiggle, mandible snap + lunge on attack, queen breathing.

signal died(ant: Ant)

enum Caste { WORKER, SOLDIER, QUEEN }
enum State { IDLE, TO_DIG, DIGGING, EXITING, FORAGING, SEEK_FOOD, RETURNING, DEPOSITING, GUARD, ENGAGE, FLEE, ORDERED }

const SPEED := { 0: 75.0, 1: 90.0, 2: 0.0 }
const MAX_HP := { 0: 12.0, 1: 32.0, 2: 120.0 }
const BODY := { 0: 1.0, 1: 1.45, 2: 2.3 }

var caste: int = Caste.WORKER
var state: int = State.IDLE
var hp: float = 10.0
var colony: Colony
var game # Main game manager (untyped to avoid cyclic dependency)
var position := Vector2.ZERO # logic-space position (Vector2, as before)
var path: Array = [] # Array[Vector2] world waypoints
var dig_target := Vector2i(-1, -1)
var dig_timer := 0.0
var carrying := false
var attack_cd := 0.0
var wander_target := Vector2.ZERO
var wander_timer := 0.0
var flee_timer := 0.0
var deposit_timer := 0.0
var target_spider: Spider = null
var facing := 1.0
var step_phase := 0.0
var guard_post := Vector2.ZERO
# Manual orders (tap-to-rally): while order_cooldown > 0 the idle AI leaves
# the ant alone so player orders are never instantly overridden.
var order_cooldown := 0.0
var _order_target := Vector2.ZERO

# 3D visual nodes.
var _root: Node3D
var _body: Node3D
var _legs: Array = [] # Array[Node3D] hip pivots
var _knees: Array = [] # Array[Node3D] knee pivots (parallel to _legs)
var _leg_phase: Array = [] # Array[float] tripod phase per leg
var _ant_l: Node3D
var _ant_r: Node3D
var _mand_l: Node3D
var _mand_r: Node3D
var _gaster: MeshInstance3D
var _hp_bg: MeshInstance3D
var _hp_fg: MeshInstance3D
var _carry_ball: MeshInstance3D
var _sel_ring: MeshInstance3D
var _move_blend := 0.0
var _last_pos := Vector2.ZERO
var _lunge := 0.0
var _body_base_y := 0.0


func setup(p_caste: int, p_colony: Colony, p_game, pos: Vector2) -> void:
	caste = p_caste
	colony = p_colony
	game = p_game
	position = pos
	_last_pos = pos
	hp = MAX_HP[caste]
	if caste == Caste.SOLDIER:
		state = State.GUARD
		guard_post = pos
	_build_visual()
	_sync_visual()


func max_hp() -> float:
	return MAX_HP[caste]


func speed() -> float:
	return SPEED[caste]


func is_free_worker() -> bool:
	return caste == Caste.WORKER and state == State.IDLE and not carrying


func set_selected(v: bool) -> void:
	if _sel_ring != null:
		_sel_ring.visible = v


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		died.emit(self)
		queue_free()


# ---- Player orders ----------------------------------------------------------

## Rally order: walk to target (tunnels, surface, or both). Returns false for
## the queen, who never leaves the chamber.
func order_move(target: Vector2) -> bool:
	if caste == Caste.QUEEN:
		return false
	path.clear()
	_order_target = target
	var entrance := Vector2i(Colony.ENTRANCE_COL, 0)
	var start_under: bool = position.y > Colony.SURFACE_Y
	var end_under: bool = target.y > Colony.SURFACE_Y
	if start_under and end_under:
		var t := colony.tile_at_world(target)
		if not colony.is_open(t):
			t = colony.nearest_open_tile(t)
		if t.x >= 0:
			_path_to_tile(t)
		path.append(target)
	elif start_under and not end_under:
		_path_to_tile(entrance)
		path.append(colony.surface_point(colony.entrance_world_x()))
		path.append(target)
	elif not start_under and end_under:
		path.append(colony.surface_point(position.x))
		var t := colony.tile_at_world(target)
		if not colony.is_open(t):
			t = colony.nearest_open_tile(t)
		if t.x >= 0:
			var steps: Array = colony.find_path(entrance, t)
			for s in steps:
				path.append(colony.world_of_tile(s))
		path.append(target)
	else:
		path.append(target)
	target_spider = null
	state = State.ORDERED
	order_cooldown = 9.0
	return true


## Attack order (soldiers only).
func order_attack(spider: Spider) -> bool:
	if caste != Caste.SOLDIER or spider == null:
		return false
	target_spider = spider
	path.clear()
	state = State.ENGAGE
	order_cooldown = 9.0
	return true


func _order_arrived() -> void:
	if carrying:
		# Walk the food back properly instead of depositing on the spot.
		state = State.RETURNING
	elif caste == Caste.SOLDIER:
		guard_post = _order_target
		state = State.GUARD
	else:
		state = State.IDLE


func _physics_process(delta: float) -> void:
	if game == null or game.game_over:
		return
	attack_cd = maxf(0.0, attack_cd - delta)
	order_cooldown = maxf(0.0, order_cooldown - delta)
	_lunge = maxf(0.0, _lunge - delta)
	# Movement blend: legs only swing while actually moving.
	var moved: float = position.distance_to(_last_pos) / maxf(delta, 0.0001)
	_last_pos = position
	var want_blend := 1.0 if moved > 10.0 else 0.0
	_move_blend = lerpf(_move_blend, want_blend, minf(1.0, delta * 8.0))
	step_phase += delta * (9.0 + moved * 0.06) * (0.25 + 0.75 * _move_blend)
	if state == State.DIGGING:
		step_phase += delta * 22.0 # scrambling legs while digging
	match state:
		State.IDLE:
			_idle(delta)
		State.TO_DIG:
			if _follow_path(delta):
				state = State.DIGGING
				dig_timer = 2.5
		State.DIGGING:
			dig_timer -= delta
			# Digging wiggle.
			position += Vector2(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0)) * delta
			if dig_timer <= 0.0:
				if colony.dig(dig_target):
					game.on_dig_done(self)
				dig_target = Vector2i(-1, -1)
				state = State.IDLE
		State.EXITING:
			if _follow_path(delta):
				# Climb up out of the entrance onto the grass.
				var top := colony.surface_point(position.x)
				if _move_toward(top, delta):
					state = State.FORAGING
					wander_timer = 0.0
		State.FORAGING:
			_forage(delta)
		State.SEEK_FOOD:
			_seek_food(delta)
		State.RETURNING:
			_returning(delta)
		State.DEPOSITING:
			deposit_timer -= delta
			if deposit_timer <= 0.0:
				game.deposit_food()
				carrying = false
				state = State.IDLE
		State.GUARD:
			_guard(delta)
		State.ENGAGE:
			_engage(delta)
		State.FLEE:
			_flee(delta)
		State.ORDERED:
			if _follow_path(delta):
				_order_arrived()
	_sync_visual()


func _idle(_delta: float) -> void:
	if order_cooldown > 0.0:
		return # holding a player rally position
	if caste == Caste.WORKER:
		if game.try_assign_forage(self):
			return
	elif caste == Caste.SOLDIER:
		state = State.GUARD
	# Queen just sits.


func _forage(delta: float) -> void:
	if _spider_near(140.0):
		_start_flee()
		return
	var idx: int = game.nearest_pellet(position)
	if idx == -1:
		wander_timer -= delta
		if wander_timer <= 0.0 or _move_toward(wander_target, delta):
			wander_target = Vector2(randf_range(80.0, 1200.0), Colony.SURFACE_Y - 6.0)
			wander_timer = randf_range(1.5, 3.5)
	else:
		state = State.SEEK_FOOD


func _seek_food(delta: float) -> void:
	if _spider_near(140.0):
		_start_flee()
		return
	var idx: int = game.nearest_pellet(position)
	if idx == -1:
		state = State.FORAGING
		return
	var ppos: Vector2 = game.pellets[idx]
	if _move_toward(Vector2(ppos.x, Colony.SURFACE_Y - 6.0), delta):
		if game.take_pellet(idx):
			carrying = true
			state = State.RETURNING
		else:
			state = State.FORAGING


func _returning(delta: float) -> void:
	if _spider_near(120.0):
		_start_flee()
		return
	var ex := colony.entrance_world_x()
	if position.y < Colony.SURFACE_Y - 20.0:
		# On the surface: walk to the entrance.
		_move_toward(Vector2(ex, Colony.SURFACE_Y - 6.0), delta)
	else:
		# At the entrance: go down to the entrance tile, then to storage.
		var et := colony.world_of_tile(Vector2i(Colony.ENTRANCE_COL, 0))
		if position.distance_to(et) < 8.0:
			_path_to_tile(Colony.STORAGE_TILE)
			state = State.DEPOSITING
			deposit_timer = 0.4
		else:
			_move_toward(et, delta)


func _guard(_delta: float) -> void:
	var sp: Spider = game.nearest_spider(position, 300.0)
	if sp != null:
		target_spider = sp
		state = State.ENGAGE
		return
	# Drift back to the guard post near the entrance.
	if position.distance_to(guard_post) > 12.0:
		_move_toward(guard_post, 60.0)


func _engage(delta: float) -> void:
	if target_spider == null or not is_instance_valid(target_spider):
		target_spider = null
		state = State.GUARD
		return
	var sp: Vector2 = target_spider.position
	if position.distance_to(sp) < 34.0:
		if attack_cd <= 0.0:
			target_spider.take_damage(7.0)
			attack_cd = 0.8
			_lunge = 0.22
	else:
		if sp.y <= Colony.SURFACE_Y and position.y <= Colony.SURFACE_Y:
			# Both on the surface: chase directly.
			_move_toward(sp, delta)
		else:
			# Spider is underground (or we are): path through tunnels.
			if path.is_empty():
				_path_to_tile(colony.tile_at_world(sp))
			_follow_path(delta)


func _flee(delta: float) -> void:
	flee_timer -= delta
	var sp: Spider = game.nearest_spider(position, 400.0)
	if sp != null:
		var away: Vector2 = (position - sp.position).normalized()
		_move_toward(position + away * 60.0, delta)
	if flee_timer <= 0.0:
		if caste == Caste.SOLDIER:
			state = State.GUARD
		else:
			carrying = false
			state = State.IDLE


func _spider_near(radius: float) -> bool:
	return game.nearest_spider(position, radius) != null


func _start_flee() -> void:
	if state != State.FLEE:
		state = State.FLEE
		flee_timer = 1.4


func assign_dig(tile: Vector2i) -> bool:
	var stand := colony.open_neighbor_of(tile)
	if stand == Vector2i(-1, -1):
		return false
	dig_target = tile
	_path_to_tile(stand)
	state = State.TO_DIG
	return true


func send_to_forage() -> void:
	_path_to_tile(Vector2i(Colony.ENTRANCE_COL, 0))
	state = State.EXITING


func _path_to_tile(t: Vector2i) -> void:
	path.clear()
	var cur := colony.tile_at_world(position)
	var steps: Array = colony.find_path(cur, t)
	for s in steps:
		path.append(colony.world_of_tile(s))


## Returns true when the destination is reached.
func _move_toward(p: Vector2, delta: float, spd: float = -1.0) -> bool:
	if spd < 0.0:
		spd = speed()
	var d: Vector2 = p - position
	var dist := d.length()
	if dist < 5.0:
		return true
	var step: Vector2 = d.normalized() * minf(spd * delta, dist)
	position += step
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
	var s: float = BODY[caste]
	# Glossy chitin per caste: catches the sun like a real exoskeleton.
	var shell: StandardMaterial3D
	var dark: StandardMaterial3D
	var gaster_mat: StandardMaterial3D
	match caste:
		Caste.SOLDIER:
			# Copper-red head/thorax, near-black gaster — matches the target
			# reference (dark abdomen, reddish front). Soldiers run darker.
			shell = Geo3D.chitin("ant_shell_soldier", Color("#7a3a18"))
			dark = Geo3D.chitin("ant_dark_soldier", Color("#170c06"), 0.32)
			gaster_mat = Geo3D.chitin("ant_gaster_soldier", Color("#1c0e07"), 0.25)
		Caste.QUEEN:
			# Deep amber-brown with gold accents.
			shell = Geo3D.chitin("ant_shell_queen", Color("#6e3c14"), 0.24)
			dark = Geo3D.chitin("ant_dark_queen", Color("#2a1608"), 0.3)
			gaster_mat = Geo3D.chitin("ant_gaster_queen", Color("#3a2110"), 0.22)
		_:
			shell = Geo3D.chitin("ant_shell_worker", Color("#8a4a20"))
			dark = Geo3D.chitin("ant_dark_worker", Color("#1e1008"), 0.35)
			gaster_mat = Geo3D.chitin("ant_gaster_worker", Color("#201008"), 0.28)
	var eye_mat := Geo3D.chitin("ant_eye", Color("#0d0a08"), 0.12)

	_root = Node3D.new()
	_root.name = "Visual"
	add_child(_root)
	_body = Node3D.new()
	_root.add_child(_body)
	_body_base_y = 0.0

	# Gaster: teardrop — full bulb tapering to a rear tip, no more beach ball.
	var gaster_s := 1.0
	if caste == Caste.QUEEN:
		gaster_s = 1.35
	_gaster = Geo3D.part(_body, Geo3D.sphere, Vector3(-0.26 * s, 0.18 * s, 0), Vector3(0.56 * s * gaster_s, 0.42 * s, 0.38 * s), gaster_mat)
	Geo3D.part(_body, Geo3D.sphere, Vector3(-0.56 * s, 0.16 * s, 0), Vector3(0.28 * s * gaster_s, 0.30 * s, 0.26 * s), gaster_mat) # tapered tip
	Geo3D.part(_body, Geo3D.sphere, Vector3(-0.03 * s, 0.15 * s, 0), Vector3(0.14 * s, 0.14 * s, 0.12 * s), dark) # petiole node
	Geo3D.part(_body, Geo3D.sphere, Vector3(0.06 * s, 0.15 * s, 0), Vector3(0.42 * s, 0.26 * s, 0.24 * s), shell) # thorax: longer, narrower
	var head_s := 1.35 if caste == Caste.SOLDIER else 1.0
	# Head: elongated and distinct from the thorax.
	Geo3D.part(_body, Geo3D.sphere, Vector3(0.32 * s, 0.18 * s, 0), Vector3(0.38 * s * head_s, 0.30 * s * head_s, 0.28 * s * head_s), dark) # head
	# Big glossy eyes.
	Geo3D.part(_body, Geo3D.sphere, Vector3(0.44 * s, 0.26 * s, 0.11 * s), Vector3(0.11, 0.11, 0.11), eye_mat)
	Geo3D.part(_body, Geo3D.sphere, Vector3(0.44 * s, 0.26 * s, -0.11 * s), Vector3(0.11, 0.11, 0.11), eye_mat)

	# Mandibles: curved two-segment pincers (soldiers get big ones).
	var mand_s := 1.9 if caste == Caste.SOLDIER else 1.0
	for side in [-1.0, 1.0]:
		var mp := Node3D.new()
		mp.position = Vector3(0.50 * s, 0.12 * s, side * 0.09 * s)
		mp.rotation.y = side * -0.30
		_body.add_child(mp)
		var mseg1 := MeshInstance3D.new()
		mseg1.mesh = Geo3D.leg_mesh
		mseg1.scale = Vector3(0.08 * s * mand_s, 0.22 * s * mand_s, 0.08 * s * mand_s)
		mseg1.rotation.z = -PI * 0.5
		mseg1.position = Vector3(0.11 * s * mand_s, 0, 0)
		mseg1.material_override = dark
		mseg1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mp.add_child(mseg1)
		var mtip := Node3D.new()
		mtip.position = Vector3(0.22 * s * mand_s, 0, 0)
		mtip.rotation.y = side * -0.85
		mp.add_child(mtip)
		var mseg2 := MeshInstance3D.new()
		mseg2.mesh = Geo3D.leg_mesh
		mseg2.scale = Vector3(0.06 * s * mand_s, 0.15 * s * mand_s, 0.06 * s * mand_s)
		mseg2.rotation.z = -PI * 0.5
		mseg2.position = Vector3(0.075 * s * mand_s, 0, 0)
		mseg2.material_override = dark
		mseg2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mtip.add_child(mseg2)
		if side < 0.0:
			_mand_l = mp
		else:
			_mand_r = mp

	# Elbowed antennae on wiggle pivots.
	for side in [-1.0, 1.0]:
		var ap := Node3D.new()
		ap.position = Vector3(0.40 * s, 0.28 * s, side * 0.06 * s)
		ap.rotation.z = -0.9
		_body.add_child(ap)
		var seg1 := MeshInstance3D.new()
		seg1.mesh = Geo3D.leg_mesh
		seg1.scale = Vector3(0.035 * s, 0.22 * s, 0.035 * s)
		seg1.position = Vector3(0, 0.11 * s, 0)
		seg1.material_override = dark
		seg1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ap.add_child(seg1)
		var tip := Node3D.new()
		tip.position = Vector3(0, 0.22 * s, 0)
		tip.rotation.z = -0.7
		ap.add_child(tip)
		var seg2 := MeshInstance3D.new()
		seg2.mesh = Geo3D.leg_mesh
		seg2.scale = Vector3(0.03 * s, 0.18 * s, 0.03 * s)
		seg2.position = Vector3(0, 0.09 * s, 0)
		seg2.material_override = dark
		seg2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tip.add_child(seg2)
		if side < 0.0:
			_ant_l = ap
		else:
			_ant_r = ap

	# Six two-segment legs: femur angling up-out from the hip, a knee joint,
	# then the tibia folding back down to the ground. Tripod phase per leg.
	for i in 3:
		for side in [-1.0, 1.0]:
			var hip := Node3D.new()
			hip.position = Vector3((-0.08 + i * 0.14) * s, 0.12 * s, side * 0.10 * s)
			hip.rotation.x = side * 0.85
			_body.add_child(hip)
			var femur := MeshInstance3D.new()
			femur.mesh = Geo3D.leg_mesh
			femur.scale = Vector3(0.085 * s, 0.30 * s, 0.085 * s)
			femur.position = Vector3(0, 0.15 * s, 0)
			femur.material_override = dark
			femur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hip.add_child(femur)
			var knee := Node3D.new()
			knee.position = Vector3(0, 0.30 * s, 0)
			knee.rotation.x = -side * 0.72
			hip.add_child(knee)
			var tibia := MeshInstance3D.new()
			tibia.mesh = Geo3D.leg_mesh
			tibia.scale = Vector3(0.05 * s, 0.38 * s, 0.05 * s)
			tibia.position = Vector3(0, -0.19 * s, 0)
			tibia.material_override = dark
			tibia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			knee.add_child(tibia)
			_legs.append(hip)
			_knees.append(knee)
			var side_idx := 0 if side < 0.0 else 1
			_leg_phase.append(0.0 if (i + side_idx) % 2 == 0 else PI)

	if caste == Caste.QUEEN:
		# Golden wing pads, crown dots, and gold banding on the dark gaster.
		var gold := Geo3D.chitin("ant_gold", Color("#d9a832"), 0.18)
		for side in [-1.0, 1.0]:
			Geo3D.part(_body, Geo3D.sphere, Vector3(-0.05 * s, 0.30 * s, side * 0.14 * s), Vector3(0.30 * s, 0.10 * s, 0.16 * s), gold)
		for i in 3:
			Geo3D.part(_body, Geo3D.sphere, Vector3((0.20 + i * 0.09) * s, 0.34 * s, 0), Vector3(0.09, 0.09, 0.09), gold)
		# Gold bands across the gaster.
		for i in 3:
			var band := Geo3D.part(_body, Geo3D.box, Vector3((-0.52 + i * 0.22) * s, 0.18 * s, 0), Vector3(0.07 * s, 0.40 * s, 0.44 * s), gold)
			band.rotation.z = 0.35

	# Selection ring (on the root so it never flips with the body).
	_sel_ring = Geo3D.flat_ring(_root, 0.85 * s, Geo3D.glow("sel_ring", Color("#7dff5e")))
	_sel_ring.position = Vector3(0, 0.03, 0.01)
	_sel_ring.visible = false

	# Non-flipping top layer: carried food + HP bar.
	var top := Node3D.new()
	_root.add_child(top)
	_carry_ball = Geo3D.part(top, Geo3D.sphere, Vector3(0.05, 0.52 * s, 0), Vector3(0.20, 0.20, 0.20), Geo3D.glow("leaf", Color("#7ddb52"), 0.6))
	_carry_ball.visible = false
	_hp_bg = Geo3D.part(top, Geo3D.box, Vector3(0, 0.74 * s, 0), Vector3(0.55, 0.08, 0.03), Geo3D.mat("hpbg", Color("#1a1a1a")))
	_hp_fg = Geo3D.part(top, Geo3D.box, Vector3(0, 0.74 * s, 0.005), Vector3(0.55, 0.08, 0.03), Geo3D.glow("hpf", Color("#ff5a4e"), 0.8))
	_hp_bg.visible = false
	_hp_fg.visible = false


func _sync_visual() -> void:
	if _root == null or colony == null:
		return
	_root.position = colony.to_3d(position) + Vector3(0, 0, Colony.ENTITY_Z)
	_body.rotation.y = PI if facing < 0.0 else 0.0
	var t := Time.get_ticks_msec() / 1000.0
	# Tripod gait: hips swing fore-aft, knees flex counter-phase for a real
	# stepping look. Amplitude follows actual movement so idle ants stand
	# still instead of skating.
	var digging := state == State.DIGGING
	var amp := _move_blend * 0.55 + (0.5 if digging else 0.0)
	for i in _legs.size():
		var hip: Node3D = _legs[i]
		hip.rotation.z = sin(step_phase + _leg_phase[i]) * amp
		var knee: Node3D = _knees[i]
		knee.rotation.z = -sin(step_phase + _leg_phase[i] - 0.6) * amp * 0.5
	# Body bob (2x step frequency) + roll sway; lunge on attack.
	_body.position.y = _body_base_y + sin(step_phase * 2.0) * 0.035 * _move_blend
	_body.rotation.z = sin(step_phase) * 0.05 * _move_blend
	# Lunge is absolute, not accumulated, so the body can't drift over time.
	_body.position.x = 0.16 * (_lunge / 0.22) if _lunge > 0.0 else 0.0
	# Antennae always wiggle a little: the colony feels alive.
	var wig := sin(t * 3.1) * 0.14 + sin(t * 7.3) * 0.05
	if _ant_l != null:
		_ant_l.rotation.z = -0.9 + wig
		_ant_r.rotation.z = -0.9 - wig
	# Mandible snap right after a bite.
	var snap := 0.0
	if _lunge > 0.0:
		snap = 0.55 * (_lunge / 0.22)
	if _mand_l != null:
		_mand_l.rotation.y = 0.30 + snap
		_mand_r.rotation.y = -0.30 - snap
	# Queen breathing: slow gaster pulse.
	if caste == Caste.QUEEN and _gaster != null:
		var b := 1.0 + sin(t * 1.6) * 0.035
		var bs: Vector3 = _gaster.scale
		_gaster.scale = Vector3(bs.x, bs.y * b, bs.z * b)
	var show_hp := hp < max_hp() and caste != Caste.QUEEN
	_hp_bg.visible = show_hp
	_hp_fg.visible = show_hp
	if show_hp:
		var frac := clampf(hp / max_hp(), 0.0, 1.0)
		_hp_fg.scale.x = 0.55 * frac
		_hp_fg.position.x = -0.275 * (1.0 - frac)
	_carry_ball.visible = carrying
