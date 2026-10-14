class_name GameSettings
extends RefCounted
## Persisted player settings (user://settings.cfg). Loaded at startup by both
## the menu and the game scene; saved whenever a toggle changes.

const PATH := "user://settings.cfg"

static var show_fps := false
static var show_hints := true


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		show_fps = bool(cfg.get_value("ui", "show_fps", false))
		show_hints = bool(cfg.get_value("ui", "show_hints", true))


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "show_fps", show_fps)
	cfg.set_value("ui", "show_hints", show_hints)
	cfg.save(PATH)
