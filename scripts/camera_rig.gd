class_name CameraRig
extends Node3D
## RTS camera, mobile-first.
##
## - One-finger drag (or left-drag): pan. Content follows the pointer.
## - Pinch (or mouse wheel): zoom TOWARD the pinch focal point / cursor.
## - Two-finger slide (no pinch change): orbit. Right-drag: orbit.
## - Quick tap: forwarded to the game (select / rally / dig).
## - Double-tap: forwarded as a group-select request.
## - Right-click (no drag): order request without changing selection.
##
## Tap detection: press+release with < TAP_PX movement and < TAP_TIME seconds.

var game # Main game manager (set by main.gd)
var camera: Camera3D

var target := Vector3(0, -4.5, 0)
var yaw := 0.0
var pitch := 0.56 # ~32 degrees elevation
var dist := 26.0

const TAP_PX := 12.0
const TAP_TIME := 0.45
const DOUBLE_TAP_TIME := 0.38
const DOUBLE_TAP_PX := 26.0
const MIN_DIST := 8.0
const MAX_DIST := 70.0
const MIN_PITCH := 0.26
const MAX_PITCH := 1.13
const MAX_YAW := 1.2
# Free movement across the whole map: colony is 26 wide, 13 deep;
# surface foraging spans x in [-12, 14].
const MIN_TX := -19.0
const MAX_TX := 19.0
const MIN_TY := -15.0
const MAX_TY := 4.0

# Mouse gesture state.
var _l_down := false
var _l_moved := false
var _l_start := Vector2.ZERO
var _l_time := 0.0
var _r_down := false
var _r_moved := false
var _r_start := Vector2.ZERO
var _r_time := 0.0

# Touch gesture state: touch index -> {pos, start, time, moved}.
var _touches := {}
var _pinch_d := 0.0
var _pinch_mid := Vector2.ZERO

# Double-tap tracking (shared mouse/touch).
var _last_tap_t := -10.0
var _last_tap_pos := Vector2.ZERO


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 55.0
	camera.far = 400.0
	add_child(camera)
	camera.current = true
	_update_camera()


func _process(delta: float) -> void:
	if _l_down:
		_l_time += delta
	if _r_down:
		_r_time += delta
	_update_camera()


func _update_camera() -> void:
	target.x = clampf(target.x, MIN_TX, MAX_TX)
	target.y = clampf(target.y, MIN_TY, MAX_TY)
	target.z = 0.0
	dist = clampf(dist, MIN_DIST, MAX_DIST)
	pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
	yaw = clampf(yaw, -MAX_YAW, MAX_YAW)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	camera.global_position = target + off
	camera.look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_drag(event as InputEventScreenDrag)


# ---- Mouse -----------------------------------------------------------------

func _mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_l_down = true
				_l_moved = false
				_l_start = mb.position
				_l_time = 0.0
			else:
				if _l_down and not _l_moved and _l_time < TAP_TIME:
					_tap(mb.position)
				_l_down = false
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_r_down = true
				_r_moved = false
				_r_start = mb.position
				_r_time = 0.0
			else:
				if _r_down and not _r_moved and _r_time < TAP_TIME:
					_order_tap(mb.position)
				_r_down = false
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_zoom_at(mb.position, 0.9)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_zoom_at(mb.position, 1.1)


func _mouse_motion(mm: InputEventMouseMotion) -> void:
	if _l_down:
		if (mm.position - _l_start).length() > TAP_PX:
			_l_moved = true
		if _l_moved:
			_pan(mm.relative)
	elif _r_down:
		if (mm.position - _r_start).length() > TAP_PX:
			_r_moved = true
		if _r_moved:
			_orbit(mm.relative)


# ---- Touch -----------------------------------------------------------------

func _touch(st: InputEventScreenTouch) -> void:
	if st.pressed:
		_touches[st.index] = {"pos": st.position, "start": st.position, "time": Time.get_ticks_msec() / 1000.0, "moved": false}
		if _touches.size() == 2:
			_pinch_d = _touch_distance()
			_pinch_mid = _touch_midpoint()
	else:
		if _touches.has(st.index):
			var t: Dictionary = _touches[st.index]
			var dt: float = Time.get_ticks_msec() / 1000.0 - float(t["time"])
			if _touches.size() == 1 and not bool(t["moved"]) and dt < TAP_TIME:
				_tap(st.position)
			_touches.erase(st.index)
			if _touches.size() < 2:
				_pinch_d = 0.0


func _drag(sd: InputEventScreenDrag) -> void:
	if not _touches.has(sd.index):
		return
	var t: Dictionary = _touches[sd.index]
	t["pos"] = sd.position
	if (sd.position - t["start"] as Vector2).length() > TAP_PX:
		t["moved"] = true
	_touches[sd.index] = t
	if _touches.size() == 1:
		if bool(t["moved"]):
			_pan(sd.relative)
	elif _touches.size() == 2:
		var nd := _touch_distance()
		var mid := _touch_midpoint()
		if _pinch_d > 0.0 and nd > 0.0:
			if absf(nd - _pinch_d) > 4.0:
				# Pinch: zoom toward the fingers' midpoint.
				_zoom_at(mid, _pinch_d / nd)
				_pinch_d = nd
			else:
				# Two fingers sliding together: orbit.
				_orbit(sd.relative * 0.6)
		else:
			_pinch_d = nd
		_pinch_mid = mid


func _touch_distance() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0]["pos"] as Vector2).distance_to(pts[1]["pos"] as Vector2)


func _touch_midpoint() -> Vector2:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return Vector2.ZERO
	return ((pts[0]["pos"] as Vector2) + (pts[1]["pos"] as Vector2)) * 0.5


# ---- Shared ----------------------------------------------------------------

func _pan(relative_px: Vector2) -> void:
	# Screen drag -> world pan on the colony plane. Dragging moves content
	# with the pointer (target moves opposite the drag).
	var k := dist * 0.0018
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var up_ground := Vector3(-sin(yaw), 0, -cos(yaw))
	target -= right * relative_px.x * k
	target -= up_ground * relative_px.y * k


func _orbit(relative_px: Vector2) -> void:
	yaw -= relative_px.x * 0.005
	pitch += relative_px.y * 0.005


func _screen_to_plane(screen_pos: Vector2) -> Vector3:
	# World point on the gameplay plane (z=0) under a screen position.
	if camera == null:
		return target
	var origin := camera.project_ray_origin(screen_pos)
	var normal := camera.project_ray_normal(screen_pos)
	if absf(normal.z) < 0.0001:
		return target
	var t := -origin.z / normal.z
	if t < 0.0:
		return target
	return origin + normal * t


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	# Zoom while keeping the world point under screen_pos fixed, so a pinch
	# zooms toward the fingers instead of drifting away from them.
	var before := _screen_to_plane(screen_pos)
	dist = clampf(dist * factor, MIN_DIST, MAX_DIST)
	_update_camera()
	var after := _screen_to_plane(screen_pos)
	target += Vector3(before.x - after.x, before.y - after.y, 0.0)


func _tap(screen_pos: Vector2) -> void:
	if game == null or camera == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var hit := _screen_to_plane(screen_pos)
	var world: Vector2 = game.colony.from_3d(hit)
	if now - _last_tap_t < DOUBLE_TAP_TIME and screen_pos.distance_to(_last_tap_pos) < DOUBLE_TAP_PX:
		_last_tap_t = -10.0
		game._handle_double_tap(world)
		return
	_last_tap_t = now
	_last_tap_pos = screen_pos
	game._handle_tap(world)


func _order_tap(screen_pos: Vector2) -> void:
	# Right-click: issue a move/attack order without changing the selection.
	if game == null or camera == null:
		return
	var hit := _screen_to_plane(screen_pos)
	game._handle_order(game.colony.from_3d(hit))
