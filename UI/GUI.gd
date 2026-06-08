extends CanvasLayer

@onready var health_bar: ProgressBar = $MarginContainer/Rows/BottomRow/VBoxContainer/HealthSection/HealthBar
@onready var shield_bar: ProgressBar = $MarginContainer/Rows/BottomRow/VBoxContainer/ShieldSection/ShieldBar
@onready var energy_bar: ProgressBar = $MarginContainer/Rows/BottomRow/VBoxContainer/EnergySection/EnergyBar

@onready var debug_display = $MarginContainer/Rows/TopRow/HBoxContainer/VBoxContainer/Debug_Display
@onready var debug_display2 = $MarginContainer/Rows/TopRow/HBoxContainer/VBoxContainer/Debug_Display2
@onready var debug_display3 = $MarginContainer/Rows/TopRow/HBoxContainer/VBoxContainer/Debug_Display3
@onready var debug_display4 = $MarginContainer/Rows/TopRow/HBoxContainer/VBoxContainer/Debug_Display4

var player: Player
var _score_label: Label
var _status_label: Label


func _ready() -> void:
	GlobalSignals.add_to_debug_display.connect(_on_add_to_debug)
	GlobalSignals.set_debug_display.connect(_on_set_debug)
	GlobalSignals.add_to_debug2_display.connect(_on_add_to_debug2)
	GlobalSignals.set_debug2_display.connect(_on_set_debug2)
	GlobalSignals.broadcast_player_position.connect(_on_player_position)
	GlobalSignals.player_health_changed.connect(_set_health)
	GlobalSignals.player_energy_changed.connect(_set_energy)
	GlobalSignals.player_shield_changed.connect(_set_shield)
	GlobalSignals.player_exists.connect(_bind_player)
	GlobalSignals.total_deaths_changed.connect(_on_deaths_changed)
	GlobalSignals.status_message.connect(_on_status_message)
	_build_score_label()
	_build_status_label()
	_label_bar(health_bar, "HULL")
	_label_bar(shield_bar, "SHIELD")
	_label_bar(energy_bar, "ENERGY")
	# Player may already exist if Main scene ordering put it first.
	_bind_player()


func _label_bar(bar: ProgressBar, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 4)
	label.size = Vector2(95, 30)
	label.position = Vector2(-100, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)


func _build_score_label() -> void:
	_score_label = Label.new()
	_score_label.text = "0 deaths"
	_score_label.add_theme_font_size_override("font_size", 32)
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	_score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_score_label.add_theme_constant_override("outline_size", 6)
	_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score_label.position = Vector2(-150, 18)
	_score_label.custom_minimum_size = Vector2(300, 0)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_score_label)


func _on_deaths_changed(total: int) -> void:
	_score_label.text = "%s deaths" % _format_thousands(total)


func _build_status_label() -> void:
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_status_label.add_theme_constant_override("outline_size", 5)
	_status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status_label.position = Vector2(-400, -60)
	_status_label.custom_minimum_size = Vector2(800, 0)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)


func _on_status_message(text: String) -> void:
	_status_label.text = text


func _format_thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func _bind_player() -> void:
	if player != null:
		return
	var found := get_tree().get_first_node_in_group("player")
	if found is Player:
		player = found
		_set_health(player.health)
		_set_energy(player.energy)
		_set_shield(player.shield)


func _set_health(new_health: float) -> void:
	health_bar.value = new_health


func _set_energy(new_energy: float) -> void:
	energy_bar.value = new_energy


func _set_shield(new_shield: float) -> void:
	shield_bar.value = new_shield


func _on_add_to_debug(msg: String) -> void:
	debug_display.text += msg


func _on_set_debug(msg: String) -> void:
	debug_display.text = msg


func _on_add_to_debug2(msg: String) -> void:
	debug_display2.text += msg


func _on_set_debug2(msg: String) -> void:
	debug_display2.text = msg


func _on_player_position(pos: Vector2) -> void:
	debug_display4.text = "pos: %0.0f, %0.0f" % [pos.x, pos.y]
