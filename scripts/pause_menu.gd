class_name PauseMenu
extends CanvasLayer
## In-game pause overlay: Resume / Restart / Quit to Menu.
## Lives in the game scene only; toggled by the HUD pause button, Esc or P.
## process_mode is ALWAYS so its buttons work while the tree is paused.

var _game: Node = null
var _panel: CenterContainer


func setup(g: Node) -> void:
	_game = g


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	add_child(dim)

	_panel = CenterContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	_panel.add_child(box)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 32)
	box.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("#e8a33d"))
	vb.add_child(title)

	vb.add_child(_mk_button("Resume", resume))
	vb.add_child(_mk_button("Restart", _on_restart))
	vb.add_child(_mk_button("Quit to Menu", _on_quit_to_menu))


func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 72)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(cb)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k == KEY_ESCAPE or k == KEY_P:
			toggle()
			get_viewport().set_input_as_handled()


func _game_is_over() -> bool:
	return _game != null and bool(_game.get("game_over"))


func toggle() -> void:
	if visible:
		resume()
	else:
		pause_game()


func pause_game() -> void:
	if _game_is_over():
		return
	visible = true
	get_tree().paused = true


func resume() -> void:
	visible = false
	get_tree().paused = false


## Hidden without touching pause state (used when the game ends while paused).
func hide_silent() -> void:
	visible = false


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
