extends Node3D
## Ant Simulator 2026 - prototype game manager.
## Owns the colony, all ants, spiders, food pellets, eggs, HUD and input.
## Game logic runs in 2D logic space (same as the 2D prototype); Colony maps
## it to 3D. Pointer input (dig taps) is handled by CameraRig.

const WORKER_COST := 25
const SOLDIER_COST := 40
const PELLET_VALUE := 12
const MAX_WORKERS := 40
const MAX_SOLDIERS := 15

var colony: Colony
var rig: CameraRig
var food := 70
var ants: Array = [] # Array[Ant]
var spiders: Array = [] # Array[Spider]
var pellets: Array = [] # Array[Vector2] logic-space positions
var pellet_nodes: Array = [] # Array[MeshInstance3D], kept in sync with pellets
var eggs: Array = [] # Array[Dictionary]; each has "node" -> MeshInstance3D
var queen: Ant = null
var dig_mode := false
var game_over := false

var pellet_timer := 3.0
var spider_timer := 50.0
var spider_wave := 0
var queen_timer := 35.0
var hint_timer := 0.0

# Headless smoke-test hook: run with `-- --autotest` to exercise
# digging, spider spawn and combat without user input.
var _autotest := false
var _autotest_t := 0.0
var _autotest_stage := 0
var _autotest_tile := Vector2i(10, 5)

var food_label: Label
var worker_label: Label
var soldier_label: Label
var dig_button: Button
var hint_label: Label
var gameover_panel: CenterContainer

# Tap-to-move / selection (EotU-style).
var selected: Array = [] # Array[Ant] with visible selection rings
var _markers: Array = [] # active tap marker effects

# Settings / debug panel.
var dbg_panel: PanelContainer
var dbg_labels := {}
var _dbg_open := false

# Game flow: pause menu + fps readout (tied to GameSettings).
var pause_menu: PauseMenu
var fps_label: Label

# ---- In-app updater ---------------------------------------------------------
var updater: Updater
var upd_center: CenterContainer
var upd_panel: PanelContainer
var upd_title: Label
var upd_notes: Label
var upd_bar: ProgressBar
var upd_dl_btn: Button
var upd_later_btn: Button
var upd_install_btn: Button
var _upd_dl_url := ""
var _upd_apk_path := ""
var _upd_dl_name := "update.apk"
var _upd_version := ""

const DEFAULT_HINT := "Toggle Dig, then tap dirt touching a tunnel. Workers forage on their own."


func _ready() -> void:
	GameSettings.load_settings()
	Geo3D.ensure()
	colony = Colony.new()
	add_child(colony)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	rig.game = self
	add_child(rig)
	# Let the colony fade surface props when the camera dives underground.
	colony.view_rig = rig
	# Queen in the starting chamber.
	queen = _spawn_ant(Ant.Caste.QUEEN, colony.world_of_tile(Colony.QUEEN_TILE))
	# Starting workforce.
	for i in 4:
		_spawn_ant(Ant.Caste.WORKER, colony.world_of_tile(Colony.STORAGE_TILE) + Vector2(i * 14 - 21, 8))
	var guard := _spawn_ant(Ant.Caste.SOLDIER, colony.surface_point(colony.entrance_world_x()))
	guard.guard_post = colony.surface_point(colony.entrance_world_x() + 60.0)
	_build_hud()
	set_hint(DEFAULT_HINT)
	if OS.get_cmdline_user_args().has("--autotest") or OS.get_cmdline_args().has("--autotest"):
		_autotest = true
		print("AUTOTEST: enabled")
	_setup_updater()


func _spawn_ant(caste: int, pos: Vector2) -> Ant:
	var a := Ant.new()
	add_child(a)
	a.setup(caste, colony, self, pos)
	a.died.connect(_on_ant_died)
	ants.append(a)
	if caste == Ant.Caste.QUEEN:
		queen = a
	return a


func _process(delta: float) -> void:
	_update_markers(delta)
	if game_over:
		return
	if _autotest:
		_autotest_tick(delta)
	# Food pellets.
	pellet_timer -= delta
	if pellet_timer <= 0.0:
		pellet_timer = 5.0
		if pellets.size() < 7:
			_add_pellet(Vector2(randf_range(80.0, 1200.0), Colony.SURFACE_Y - 10.0))
	# Spiders.
	spider_timer -= delta
	if spider_timer <= 0.0:
		spider_timer = 42.0
		if spiders.size() < 3:
			_spawn_spider()
	# Queen lays worker eggs.
	queen_timer -= delta
	if queen_timer <= 0.0:
		queen_timer = 35.0
		if food >= WORKER_COST and _count_caste(Ant.Caste.WORKER) < MAX_WORKERS:
			_lay_egg(Ant.Caste.WORKER, true)
	# Eggs hatch (pulse the 3D egg visuals).
	var pulse := 1.0 + sin(Time.get_ticks_msec() / 300.0) * 0.12
	for i in range(eggs.size() - 1, -1, -1):
		var e: Dictionary = eggs[i]
		e["timer"] = float(e["timer"]) - delta
		var node: MeshInstance3D = e["node"]
		if is_instance_valid(node):
			node.scale = Vector3.ONE * (0.28 * pulse)
		if float(e["timer"]) <= 0.0:
			if is_instance_valid(node):
				node.queue_free()
			_spawn_ant(int(e["caste"]), e["pos"])
			eggs.remove_at(i)
			set_hint("An egg hatched!")
	# Hint fade back.
	if hint_timer > 0.0:
		hint_timer -= delta
		if hint_timer <= 0.0:
			hint_label.text = DEFAULT_HINT
	_update_hud()


func _add_pellet(p: Vector2) -> void:
	pellets.append(p)
	var node := MeshInstance3D.new()
	node.mesh = Geo3D.sphere
	node.scale = Vector3(0.24, 0.24, 0.24)
	node.position = colony.to_3d(p) + Vector3(0, 0, Colony.ENTITY_Z)
	node.material_override = Geo3D.mat("pellet", Color("#4f9c33"))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	pellet_nodes.append(node)


func _spawn_spider() -> void:
	spider_wave += 1
	var s := Spider.new()
	add_child(s)
	var x := 60.0 if randf() < 0.5 else 1220.0
	s.setup(colony, self, Vector2(x, Colony.SURFACE_Y - 6.0), 35.0 + 5.0 * spider_wave)
	s.died.connect(_on_spider_died)
	spiders.append(s)
	set_hint("A spider is coming! Soldiers to the surface!")


func _lay_egg(caste: int, free: bool) -> bool:
	var cost := WORKER_COST if caste == Ant.Caste.WORKER else SOLDIER_COST
	if not free:
		if food < cost:
			set_hint("Need %d food for that." % cost)
			return false
		food -= cost
	if eggs.size() >= 10:
		set_hint("Too many eggs already.")
		return false
	var qp: Vector2 = queen.position if queen != null else colony.world_of_tile(Colony.QUEEN_TILE)
	var node := MeshInstance3D.new()
	node.mesh = Geo3D.sphere
	node.scale = Vector3.ONE * 0.28
	var ep: Vector2 = qp + Vector2(randf_range(-24.0, 24.0), randf_range(-10.0, 10.0))
	node.position = colony.to_3d(ep) + Vector3(0, 0, Colony.ENTITY_Z)
	node.material_override = Geo3D.mat("egg", Color("#f2ead8"))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	eggs.append({
		"pos": ep,
		"caste": caste,
		"timer": 12.0 if caste == Ant.Caste.WORKER else 16.0,
		"node": node,
	})
	return true


func _count_caste(caste: int) -> int:
	var n := 0
	for a in ants:
		if is_instance_valid(a) and a.caste == caste:
			n += 1
	return n


# ---- Ant / spider services ------------------------------------------------

func nearest_pellet(p: Vector2) -> int:
	var best := -1
	var best_d := 1e9
	for i in pellets.size():
		var d: float = p.distance_to(pellets[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func take_pellet(idx: int) -> bool:
	if idx < 0 or idx >= pellets.size():
		return false
	pellets.remove_at(idx)
	var node: MeshInstance3D = pellet_nodes[idx]
	pellet_nodes.remove_at(idx)
	if is_instance_valid(node):
		node.queue_free()
	return true


func deposit_food() -> void:
	food += PELLET_VALUE


func try_assign_forage(ant: Ant) -> bool:
	if pellets.is_empty():
		return false
	var foragers := 0
	for a in ants:
		if is_instance_valid(a) and a.caste == Ant.Caste.WORKER:
			if a.state == Ant.State.FORAGING or a.state == Ant.State.SEEK_FOOD or a.state == Ant.State.RETURNING or a.state == Ant.State.EXITING:
				foragers += 1
	if foragers >= 5:
		return false
	ant.send_to_forage()
	return true


func on_dig_done(_ant: Ant) -> void:
	pass


func nearest_spider(p: Vector2, radius: float) -> Spider:
	var best: Spider = null
	var best_d := radius
	for s in spiders:
		if is_instance_valid(s):
			var d: float = p.distance_to(s.position)
			if d < best_d:
				best_d = d
				best = s
	return best


func nearest_ant(p: Vector2, radius: float) -> Ant:
	var best: Ant = null
	var best_d := radius
	for a in ants:
		if is_instance_valid(a):
			var d: float = p.distance_to(a.position)
			if d < best_d:
				best_d = d
				best = a
	return best


func on_spider_killed(spider: Spider) -> void:
	food += 5
	set_hint("Spider defeated! +5 food.")


func _on_ant_died(ant: Ant) -> void:
	ants.erase(ant)
	selected.erase(ant)
	if ant == queen:
		_do_game_over()


func _on_spider_died(spider: Spider) -> void:
	spiders.erase(spider)


func _do_game_over() -> void:
	game_over = true
	print("GAME OVER: queen died (t=", snappedf(_autotest_t, 0.1), ")")
	if pause_menu != null:
		pause_menu.hide_silent()
	gameover_panel.visible = true
	get_tree().paused = true


func _autotest_tick(delta: float) -> void:
	_autotest_t += delta
	if _autotest_stage == 0 and _autotest_t > 2.0:
		_autotest_stage = 1
		dig_mode = true
		for a in ants:
			if is_instance_valid(a) and a.caste == Ant.Caste.WORKER:
				a.state = Ant.State.IDLE
				a.carrying = false
				break
		_handle_tap(colony.world_of_tile(_autotest_tile))
		print("AUTOTEST: dig order issued at ", _autotest_tile)
	elif _autotest_stage == 1 and colony.is_open(_autotest_tile):
		_autotest_stage = 2
		print("AUTOTEST: tile dug open OK")
	elif _autotest_stage == 2 and _autotest_t > 8.0:
		_autotest_stage = 3
		spider_timer = 0.5
		# Test-only reinforcements so the colony can survive the forced wave;
		# game balance itself is untouched. Spawned on the open entrance tile
		# (13,0) so tunnel pathfinding works for them.
		var ex := colony.surface_point(colony.entrance_world_x())
		_spawn_ant(Ant.Caste.SOLDIER, ex + Vector2(-10, 0))
		_spawn_ant(Ant.Caste.SOLDIER, ex + Vector2(10, 0))
		print("AUTOTEST: spider spawn forced (+2 test soldiers)")
	elif _autotest_stage == 3 and spiders.size() > 0:
		_autotest_stage = 4
		print("AUTOTEST: spider alive, combat running")
	elif _autotest_stage == 4 and _autotest_t > 40.0:
		_autotest_stage = 5
		print("AUTOTEST: done. food=", food, " workers=", _count_caste(Ant.Caste.WORKER), " spiders=", spiders.size())


# ---- Input (called by CameraRig) --------------------------------------------

## Tap: dig in dig mode; otherwise EotU-style direct control:
## tap a spider = attack order, tap an ant = select it,
## tap the ground = every relevant ant moves there (no selection needed).
func _handle_tap(world: Vector2) -> void:
	if game_over:
		return
	if dig_mode:
		_dig_tap(world)
		return
	# Tap a spider: soldiers attack it.
	var sp := nearest_spider(world, 48.0)
	if sp != null:
		var attackers := _selected_soldiers()
		if attackers.is_empty():
			attackers = _soldiers()
		if attackers.is_empty():
			set_hint("No soldiers - hatch some to fight spiders!")
			return
		for a in attackers:
			a.order_attack(sp)
		_spawn_marker(sp.position, true)
		set_hint("Soldiers attacking!")
		return
	# Tap an ant: select it (glowing ring).
	var a := _nearest_selectable_ant(world, 36.0)
	if a != null:
		_clear_selection()
		_select_ant(a)
		var role := "Worker" if a.caste == Ant.Caste.WORKER else "Soldier"
		set_hint("%s selected - tap ground to move, tap a spider to attack." % role)
		return
	# Tap the queen: she stays safe in the chamber.
	if queen != null and is_instance_valid(queen) and world.distance_to(queen.position) < 60.0:
		set_hint("The queen stays safe in the chamber.")
		return
	# Tap the ground: rally. The selection moves if there is one;
	# otherwise every idle worker and all soldiers respond.
	var movers: Array = []
	if selected.is_empty():
		movers = _idle_responders()
	else:
		for x in selected:
			if is_instance_valid(x):
				movers.append(x)
	if movers.is_empty():
		set_hint("No ants free right now.")
		return
	for x in movers:
		x.order_move(world)
	_spawn_marker(world, false)
	set_hint("Ants on the move!")


## Double-tap: select every ant of the tapped ant's caste.
func _handle_double_tap(world: Vector2) -> void:
	if game_over or dig_mode:
		return
	var a := _nearest_selectable_ant(world, 44.0)
	if a == null:
		return
	_clear_selection()
	var n := 0
	for x in ants:
		if is_instance_valid(x) and x != queen and x.caste == a.caste:
			_select_ant(x)
			n += 1
	var role := "workers" if a.caste == Ant.Caste.WORKER else "soldiers"
	set_hint("Selected all %d %s." % [n, role])


## Right-click: issue a move/attack order without changing the selection.
func _handle_order(world: Vector2) -> void:
	if game_over or dig_mode:
		return
	var movers: Array = []
	if selected.is_empty():
		movers = _idle_responders()
	else:
		for x in selected:
			if is_instance_valid(x):
				movers.append(x)
	var sp := nearest_spider(world, 48.0)
	if sp != null:
		var attackers: Array = []
		for x in movers:
			if x.caste == Ant.Caste.SOLDIER:
				attackers.append(x)
		if attackers.is_empty():
			attackers = _soldiers()
		if attackers.is_empty():
			set_hint("No soldiers - hatch some to fight spiders!")
			return
		for x in attackers:
			x.order_attack(sp)
		_spawn_marker(sp.position, true)
		set_hint("Soldiers attacking!")
		return
	if movers.is_empty():
		set_hint("No ants free right now.")
		return
	for x in movers:
		x.order_move(world)
	_spawn_marker(world, false)


func _dig_tap(world: Vector2) -> void:
	var t := colony.tile_at_world(world)
	if not colony.in_bounds(t):
		return
	if not colony.is_diggable(t):
		set_hint("Can't dig there - tap dirt that touches an open tunnel.")
		return
	for a in ants:
		if is_instance_valid(a) and a.is_free_worker():
			if a.assign_dig(t):
				set_hint("Worker assigned - digging...")
				return
	set_hint("No free workers right now.")


func _select_ant(a: Ant) -> void:
	if not selected.has(a):
		selected.append(a)
		a.set_selected(true)


func _clear_selection() -> void:
	for a in selected:
		if is_instance_valid(a):
			a.set_selected(false)
	selected.clear()


## Nearest ant the player may select (the queen is never selectable).
func _nearest_selectable_ant(p: Vector2, radius: float) -> Ant:
	var best: Ant = null
	var best_d := radius
	for a in ants:
		if is_instance_valid(a) and a != queen:
			var d: float = p.distance_to(a.position)
			if d < best_d:
				best_d = d
				best = a
	return best


func _soldiers() -> Array:
	var out: Array = []
	for a in ants:
		if is_instance_valid(a) and a.caste == Ant.Caste.SOLDIER:
			out.append(a)
	return out


func _selected_soldiers() -> Array:
	var out: Array = []
	for a in selected:
		if is_instance_valid(a) and a.caste == Ant.Caste.SOLDIER:
			out.append(a)
	return out


## Ants that answer a rally tap with no selection: idle workers + soldiers.
func _idle_responders() -> Array:
	var out: Array = []
	for a in ants:
		if not is_instance_valid(a) or a == queen:
			continue
		if a.caste == Ant.Caste.SOLDIER or a.state == Ant.State.IDLE:
			out.append(a)
	return out


# ---- Tap markers ------------------------------------------------------------

## Glowing marker puff at a tap point: green = rally, red = attack.
func _spawn_marker(logic_pos: Vector2, attack: bool) -> void:
	Geo3D.ensure()
	var n := Node3D.new()
	n.position = colony.to_3d(logic_pos) + Vector3(0, 0, Colony.ENTITY_Z + 0.15)
	add_child(n)
	var key := "attack" if attack else "move"
	var col := Color("#ff4a3d") if attack else Color("#7dff5e")
	var ring := Geo3D.flat_ring(n, 0.45, Geo3D.glow("marker_ring_" + key, col))
	Geo3D.part(n, Geo3D.sphere, Vector3.ZERO, Vector3(0.2, 0.2, 0.2), Geo3D.glow("marker_dot_" + key, col))
	_markers.append({"node": n, "ring": ring, "t": 0.0, "dur": 0.9})


func _update_markers(delta: float) -> void:
	for i in range(_markers.size() - 1, -1, -1):
		var m: Dictionary = _markers[i]
		m["t"] = float(m["t"]) + delta
		var frac := clampf(float(m["t"]) / float(m["dur"]), 0.0, 1.0)
		var node: Node3D = m["node"]
		if not is_instance_valid(node):
			_markers.remove_at(i)
			continue
		var ring: MeshInstance3D = m["ring"]
		var s := 0.45 + frac * 1.3
		ring.scale = Vector3(s, s, s)
		if frac >= 1.0:
			node.queue_free()
			_markers.remove_at(i)


# ---- HUD -------------------------------------------------------------------

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	top.add_child(margin)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	margin.add_child(hb)

	food_label = _mk_label(hb, "Food: 0")
	worker_label = _mk_label(hb, "Workers: 0")
	soldier_label = _mk_label(hb, "Soldiers: 0")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	dig_button = Button.new()
	dig_button.text = "Dig: OFF"
	dig_button.toggle_mode = true
	dig_button.custom_minimum_size = Vector2(150, 56)
	dig_button.toggled.connect(_on_dig_toggled)
	hb.add_child(dig_button)

	var bw := Button.new()
	bw.text = "+Worker (%d)" % WORKER_COST
	bw.custom_minimum_size = Vector2(190, 56)
	bw.pressed.connect(_on_hatch_worker)
	hb.add_child(bw)

	var bs := Button.new()
	bs.text = "+Soldier (%d)" % SOLDIER_COST
	bs.custom_minimum_size = Vector2(190, 56)
	bs.pressed.connect(_on_hatch_soldier)
	hb.add_child(bs)

	var gear := Button.new()
	gear.text = "⚙"
	gear.custom_minimum_size = Vector2(64, 56)
	gear.add_theme_font_size_override("font_size", 28)
	gear.pressed.connect(_toggle_debug)
	hb.add_child(gear)

	var pb := Button.new()
	pb.text = "⏸"
	pb.custom_minimum_size = Vector2(64, 56)
	pb.add_theme_font_size_override("font_size", 28)
	pb.pressed.connect(_on_pause_pressed)
	hb.add_child(pb)
	hud.add_child(top)

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-560, -70)
	hint_label.custom_minimum_size = Vector2(1120, 40)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 22)
	hint_label.add_theme_color_override("font_color", Color("#ffffff"))
	hint_label.add_theme_color_override("font_shadow_color", Color("#000000cc"))
	hint_label.add_theme_constant_override("shadow_offset_x", 2)
	hint_label.add_theme_constant_override("shadow_offset_y", 2)
	hint_label.visible = GameSettings.show_hints
	hud.add_child(hint_label)

	fps_label = Label.new()
	fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fps_label.position = Vector2(12, 78)
	fps_label.add_theme_font_size_override("font_size", 20)
	fps_label.add_theme_color_override("font_color", Color("#e8a33d"))
	fps_label.visible = GameSettings.show_fps
	hud.add_child(fps_label)

	# Game over panel.
	gameover_panel = CenterContainer.new()
	gameover_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	gameover_panel.visible = false
	gameover_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var gp := PanelContainer.new()
	var gmargin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		gmargin.add_theme_constant_override(m, 36)
	gp.add_child(gmargin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	gmargin.add_child(vb)
	var title := Label.new()
	title.text = "The queen has fallen."
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Your colony did not survive."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var restart := Button.new()
	restart.text = "Start Over"
	restart.custom_minimum_size = Vector2(220, 64)
	restart.pressed.connect(_on_restart)
	vb.add_child(restart)
	var quitm := Button.new()
	quitm.text = "Quit to Menu"
	quitm.custom_minimum_size = Vector2(220, 64)
	quitm.pressed.connect(_on_quit_to_menu)
	vb.add_child(quitm)
	gameover_panel.add_child(gp)
	hud.add_child(gameover_panel)

	_build_debug_panel(hud)
	_build_update_dialog(hud)

	# Pause overlay (Esc / P / HUD button).
	pause_menu = PauseMenu.new()
	pause_menu.setup(self)
	add_child(pause_menu)


# ---- Settings / debug panel -------------------------------------------------

func _build_debug_panel(hud: CanvasLayer) -> void:
	dbg_panel = PanelContainer.new()
	dbg_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dbg_panel.position = Vector2(-330, 84)
	dbg_panel.custom_minimum_size = Vector2(300, 0)
	dbg_panel.visible = false
	hud.add_child(dbg_panel)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 14)
	dbg_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)
	var title := Label.new()
	title.text = "Debug"
	title.add_theme_font_size_override("font_size", 24)
	vb.add_child(title)
	for key in ["version", "fps", "food", "workers", "soldiers", "queen", "eggs", "spiders"]:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 20)
		vb.add_child(l)
		dbg_labels[key] = l
	_update_debug()


func _toggle_debug() -> void:
	_dbg_open = not _dbg_open
	dbg_panel.visible = _dbg_open
	if _dbg_open:
		_update_debug()


func _update_debug() -> void:
	if dbg_labels.is_empty():
		return
	dbg_labels["version"].text = "Version: %s" % Updater.CURRENT_VERSION
	dbg_labels["fps"].text = "FPS: %d" % Engine.get_frames_per_second()
	dbg_labels["food"].text = "Food: %d" % food
	dbg_labels["workers"].text = "Workers: %d" % _count_caste(Ant.Caste.WORKER)
	dbg_labels["soldiers"].text = "Soldiers: %d" % _count_caste(Ant.Caste.SOLDIER)
	var q := "alive" if (queen != null and is_instance_valid(queen)) else "dead"
	dbg_labels["queen"].text = "Queen: %s" % q
	dbg_labels["eggs"].text = "Eggs: %d" % eggs.size()
	dbg_labels["spiders"].text = "Spiders: %d" % spiders.size()


# ---- In-app updater wiring --------------------------------------------------

func _setup_updater() -> void:
	updater = Updater.new()
	updater.name = "Updater"
	add_child(updater)
	updater.update_available.connect(_on_update_available)
	updater.download_progress.connect(_on_update_progress)
	updater.download_done.connect(_on_update_downloaded)
	updater.check_failed.connect(_on_update_check_failed)
	updater.no_update.connect(_on_update_none)
	# Auto-check shortly after startup on Android and Windows, never in autotest.
	if (OS.get_name() == "Android" or OS.get_name() == "Windows") and not _autotest:
		var t := get_tree().create_timer(2.0)
		t.timeout.connect(_on_update_timer)


func _on_update_timer() -> void:
	if is_instance_valid(updater):
		updater.check_for_update()


func _build_update_dialog(hud: CanvasLayer) -> void:
	upd_center = CenterContainer.new()
	upd_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	upd_center.visible = false
	upd_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(upd_center)

	upd_panel = PanelContainer.new()
	upd_panel.custom_minimum_size = Vector2(560, 0)
	upd_center.add_child(upd_panel)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 28)
	upd_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)

	upd_title = Label.new()
	upd_title.text = "Update available"
	upd_title.add_theme_font_size_override("font_size", 30)
	upd_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(upd_title)

	upd_notes = Label.new()
	upd_notes.add_theme_font_size_override("font_size", 20)
	upd_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	upd_notes.custom_minimum_size = Vector2(500, 0)
	vb.add_child(upd_notes)

	upd_bar = ProgressBar.new()
	upd_bar.min_value = 0.0
	upd_bar.max_value = 100.0
	upd_bar.custom_minimum_size = Vector2(500, 28)
	upd_bar.show_percentage = true
	upd_bar.visible = false
	vb.add_child(upd_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)

	upd_dl_btn = Button.new()
	upd_dl_btn.text = "Download"
	upd_dl_btn.custom_minimum_size = Vector2(200, 60)
	upd_dl_btn.pressed.connect(_on_update_download_pressed)
	row.add_child(upd_dl_btn)

	upd_install_btn = Button.new()
	upd_install_btn.text = "Tap to install"
	upd_install_btn.custom_minimum_size = Vector2(200, 60)
	upd_install_btn.visible = false
	upd_install_btn.pressed.connect(_on_update_install_pressed)
	row.add_child(upd_install_btn)

	upd_later_btn = Button.new()
	upd_later_btn.text = "Later"
	upd_later_btn.custom_minimum_size = Vector2(200, 60)
	upd_later_btn.pressed.connect(_on_update_later_pressed)
	row.add_child(upd_later_btn)


func _upd_show() -> void:
	if upd_center != null:
		upd_center.get_parent().move_child(upd_center, -1)
		upd_center.visible = true


func _upd_hide() -> void:
	if upd_center != null:
		upd_center.visible = false


func _on_update_available(version: String, changelog: String, apk_url: String, windows_url: String) -> void:
	_upd_version = version
	# Pick the download for this platform.
	var os_name := OS.get_name()
	if os_name == "Windows":
		_upd_dl_url = windows_url
		_upd_dl_name = "ant-sim-2026-update.zip"
	elif os_name == "Android":
		_upd_dl_url = apk_url
		_upd_dl_name = "update.apk"
	else:
		# Desktop editor / other: prefer whatever exists.
		if not apk_url.is_empty():
			_upd_dl_url = apk_url
			_upd_dl_name = "update.apk"
		else:
			_upd_dl_url = windows_url
			_upd_dl_name = "ant-sim-2026-update.zip"
	if _upd_dl_url.is_empty():
		print("Updater: update v%s has no download for this platform." % version)
		return
	_upd_apk_path = ""
	upd_title.text = "Update v%s available" % version
	upd_notes.text = changelog if not changelog.is_empty() else "A new version of Ant Simulator 2026 is ready."
	upd_bar.visible = false
	upd_bar.value = 0.0
	upd_dl_btn.visible = true
	upd_install_btn.visible = false
	_upd_show()
	set_hint("Update v%s available - see the popup." % version)


func _on_update_progress(percent: float) -> void:
	if upd_bar != null:
		upd_bar.value = percent


func _on_update_download_pressed() -> void:
	upd_dl_btn.visible = false
	upd_later_btn.visible = false
	upd_bar.visible = true
	upd_bar.value = 0.0
	upd_notes.text = "Downloading update v%s..." % _upd_version
	updater.download_update(_upd_dl_url, _upd_dl_name)


func _on_update_downloaded(path: String) -> void:
	_upd_apk_path = path
	upd_bar.visible = false
	if OS.get_name() == "Windows":
		upd_notes.text = "Download complete. Unzip it into your game folder to finish updating to v%s." % _upd_version
		upd_install_btn.text = "Open folder"
	else:
		upd_notes.text = "Download complete. Install update v%s now?" % _upd_version
		upd_install_btn.text = "Tap to install"
	upd_install_btn.visible = true
	upd_later_btn.visible = true


func _on_update_install_pressed() -> void:
	var os_name := OS.get_name()
	# Real Android device: hand the APK to the install plugin.
	if os_name == "Android" and Engine.has_singleton("AntUpdater"):
		var plugin = Engine.get_singleton("AntUpdater")
		if not bool(plugin.call("canRequestInstallPermission")):
			set_hint("Allow 'install unknown apps' for Ant Simulator, then tap install again.")
			plugin.call("openInstallPermissionSettings")
			return
		plugin.call("installApk", _upd_apk_path)
		_upd_hide()
		set_hint("Installing update...")
	elif os_name == "Windows":
		# A running EXE cannot replace itself: open the folder with the zip
		# so the player can unzip it over the game folder.
		_upd_hide()
		OS.shell_open(OS.get_user_data_dir())
		set_hint("Update downloaded - unzip it into your game folder to finish.")
	else:
		# Desktop / editor fallback: open the download page instead.
		_upd_hide()
		if not _upd_dl_url.is_empty():
			OS.shell_open(_upd_dl_url)
		set_hint("Opened the update download in your browser.")


func _on_update_later_pressed() -> void:
	_upd_hide()


func _on_update_check_failed(reason: String) -> void:
	print("Updater: check failed - ", reason)


func _on_update_none() -> void:
	print("Updater: game is up to date.")


func _mk_label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	l.custom_minimum_size = Vector2(0, 56)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _update_hud() -> void:
	food_label.text = "Food: %d" % food
	worker_label.text = "Workers: %d" % _count_caste(Ant.Caste.WORKER)
	soldier_label.text = "Soldiers: %d" % _count_caste(Ant.Caste.SOLDIER)
	if fps_label != null and GameSettings.show_fps:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if _dbg_open:
		_update_debug()


func set_hint(text: String) -> void:
	if hint_label == null or not GameSettings.show_hints:
		return
	hint_label.text = text
	hint_timer = 5.0


func _on_dig_toggled(on: bool) -> void:
	dig_mode = on
	dig_button.text = "Dig: ON" if on else "Dig: OFF"
	if on:
		set_hint("Tap dirt touching a tunnel to dig it out.")


func _on_hatch_worker() -> void:
	if _count_caste(Ant.Caste.WORKER) >= MAX_WORKERS:
		set_hint("Worker cap reached.")
		return
	if _lay_egg(Ant.Caste.WORKER, false):
		set_hint("Worker egg laid - hatching soon.")


func _on_hatch_soldier() -> void:
	if _count_caste(Ant.Caste.SOLDIER) >= MAX_SOLDIERS:
		set_hint("Soldier cap reached.")
		return
	if _lay_egg(Ant.Caste.WORKER, false):
		set_hint("Soldier egg laid - hatching soon.")


func _on_pause_pressed() -> void:
	if pause_menu != null and not game_over:
		pause_menu.toggle()


func _on_quit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
