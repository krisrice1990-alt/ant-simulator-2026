extends SceneTree
## Dev screenshot tool (not shipped in gameplay). Run with:
##   xvfb-run -a ~/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path ~/workspace/ant-simulator-2026 --resolution 1920x1080 -s tools/shoot.gd
## Captures 3 framed shots to screenshots/ then quits.

var _t := 0.0
var _stage := 0
var _main: Node = null


func _init() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)


func _process(delta: float) -> bool:
	_t += delta
	match _stage:
		0:
			if _t > 2.0:
				_frame_ant()
				_snap("gfx_ant_closeup.png")
				_stage = 1
		1:
			if _t > 2.6:
				_frame_mid()
				_snap("gfx_colony_mid.png")
				_stage = 2
		2:
			if _t > 3.2:
				_frame_wide()
				_snap("gfx_scene_wide.png")
				return true
	return false


func _snap(fname: String) -> void:
	_main.rig._update_camera()
	var img := root.get_texture().get_image()
	var err := img.save_png("res://screenshots/" + fname)
	print("SHOT: ", fname, " err=", err)


func _frame_ant() -> void:
	# First worker ant, framed close.
	var ant = null
	for a in _main.ants:
		if a.caste == 0: # Ant.Caste.WORKER
			ant = a
			break
	if ant == null and not _main.ants.is_empty():
		ant = _main.ants[0]
	var p: Vector3 = _main.colony.to_3d(ant.position)
	_main.rig.target = p + Vector3(0, 0.25, 0)
	_main.rig.dist = 8.0
	_main.rig.pitch = 0.5
	_main.rig.yaw = 0.0


func _frame_mid() -> void:
	# Underground colony view: tunnels + chambers in amber light.
	_main.rig.target = Vector3(0, -5.5, 0)
	_main.rig.dist = 15.0
	_main.rig.pitch = 0.62
	_main.rig.yaw = 0.0


func _frame_wide() -> void:
	# Whole scene: surface strip + colony below.
	_main.rig.target = Vector3(0, -3.0, 0)
	_main.rig.dist = 34.0
	_main.rig.pitch = 0.56
	_main.rig.yaw = 0.0
