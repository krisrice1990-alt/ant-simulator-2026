extends Control
## Title / main menu for Ant Simulator 2026.
## This is the project's main scene: Play starts the game scene,
## Settings edits the persisted GameSettings.

var _menu_box: VBoxContainer
var _settings_layer: CenterContainer


func _ready() -> void:
	GameSettings.load_settings()
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#17100a")
	add_child(bg)

	# Warm amber band across the top, like tunnel light.
	var band := ColorRect.new()
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = 26
	band.color = Color("#e8a33d")
	band.modulate = Color(1, 1, 1, 0.16)
	add_child(band)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_menu_box = VBoxContainer.new()
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_theme_constant_override("separation", 18)
	center.add_child(_menu_box)

	var title := Label.new()
	title.text = "ANT SIMULATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color("#e8a33d"))
	_menu_box.add_child(title)

	var sub := Label.new()
	sub.text = "2026 — Dig. Forage. Defend the queen."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", Color("#f2ead8"))
	_menu_box.add_child(sub)

	_menu_box.add_child(_spacer(24))
	_menu_box.add_child(_mk_button("Play", _on_play))
	_menu_box.add_child(_mk_button("Settings", _on_settings))
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		_menu_box.add_child(_mk_button("Quit", _on_quit))

	var ver := Label.new()
	ver.text = "v" + Updater.CURRENT_VERSION
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_font_size_override("font_size", 20)
	ver.add_theme_color_override("font_color", Color("#8a7a63"))
	_menu_box.add_child(_spacer(12))
	_menu_box.add_child(ver)

	_build_settings_layer()


func _build_settings_layer() -> void:
	_settings_layer = CenterContainer.new()
	_settings_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_layer.visible = false
	add_child(_settings_layer)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	_settings_layer.add_child(box)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 32)
	box.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color("#e8a33d"))
	vb.add_child(title)

	var hints := CheckButton.new()
	hints.text = "Show hint messages"
	hints.button_pressed = GameSettings.show_hints
	hints.add_theme_font_size_override("font_size", 26)
	hints.toggled.connect(_on_hints_toggled)
	vb.add_child(hints)

	var fps := CheckButton.new()
	fps.text = "Show FPS counter"
	fps.button_pressed = GameSettings.show_fps
	fps.add_theme_font_size_override("font_size", 26)
	fps.toggled.connect(_on_fps_toggled)
	vb.add_child(fps)

	vb.add_child(_mk_button("Back", _on_settings_back))


func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 76)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(cb)
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_settings() -> void:
	_settings_layer.visible = true


func _on_settings_back() -> void:
	_settings_layer.visible = false


func _on_quit() -> void:
	get_tree().quit()


func _on_hints_toggled(on: bool) -> void:
	GameSettings.show_hints = on
	GameSettings.save_settings()


func _on_fps_toggled(on: bool) -> void:
	GameSettings.show_fps = on
	GameSettings.save_settings()
