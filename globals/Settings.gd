extends Node

const CONFIG_PATH := "user://settings.cfg"

var ui_scale: float = 1.0
var ui_edit_mode: bool = false
var ui_snap_enabled: bool = true
var ui_snap_size: int = 8
var ui_show_grid: bool = false
var hud_layout: Dictionary = {}


func _ready() -> void:
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	# Control scheme lives on GlobalSignals (the live source of truth); we just
	# persist it here. GlobalSignals is an earlier autoload, so it already exists.
	GlobalSignals.control_mode = int(cfg.get_value("controls", "control_mode", GlobalSignals.control_mode))
	ui_scale = cfg.get_value("ui", "scale", 1.0)
	ui_snap_enabled = cfg.get_value("hud", "snap_enabled", true)
	ui_snap_size = cfg.get_value("hud", "snap_size", 8)
	ui_show_grid = cfg.get_value("hud", "show_grid", false)
	var layout_raw = cfg.get_value("hud", "layout", {})
	if layout_raw is Dictionary:
		hud_layout = layout_raw


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("controls", "control_mode", GlobalSignals.control_mode)
	cfg.set_value("ui", "scale", ui_scale)
	cfg.set_value("hud", "snap_enabled", ui_snap_enabled)
	cfg.set_value("hud", "snap_size", ui_snap_size)
	cfg.set_value("hud", "show_grid", ui_show_grid)
	cfg.set_value("hud", "layout", hud_layout)
	cfg.save(CONFIG_PATH)
