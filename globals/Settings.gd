extends Node

const CONFIG_PATH := "user://settings.cfg"

var ui_scale: float = 1.0


func _ready() -> void:
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	ui_scale = cfg.get_value("ui", "scale", 1.0)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("ui", "scale", ui_scale)
	cfg.save(CONFIG_PATH)
