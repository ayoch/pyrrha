extends CanvasLayer

@onready var health_bar: ProgressBar = $StatsPanel/HealthSection/HealthBar
@onready var shield_bar: ProgressBar = $StatsPanel/ShieldSection/ShieldBar
@onready var energy_bar: ProgressBar = $StatsPanel/EnergySection/EnergyBar
@onready var stats_panel: VBoxContainer = $StatsPanel
@onready var minimap_panel: Control = $MinimapPanel

var player: Player
var _score_label: Label
var _status_label: Label

# --- HUD edit mode (ported from Farwend) ---
const CORNER_SIZE := 12

var _editable_panels: Dictionary = {}
var _panel_defaults: Dictionary = {}
var _edit_overlay: Control = null
var _dragging: String = ""
var _drag_offset: Vector2 = Vector2.ZERO
var _resizing: String = ""
var _resize_corner: int = -1
var _resize_origin: Vector2 = Vector2.ZERO
var _resize_start_rect: Rect2 = Rect2()
var _grid_overlay: Control = null
var _last_minimap_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
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
	_bind_player()
	_register_editable_panels()
	_restore_hud_layout()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _process(_delta: float) -> void:
	if Settings.ui_edit_mode:
		_update_corner_positions()
		_update_dimension_labels()
	_sync_minimap_to_panel()


func _sync_minimap_to_panel() -> void:
	if minimap_panel.size == _last_minimap_size:
		return
	_last_minimap_size = minimap_panel.size
	var mini_map: Node = minimap_panel.get_node_or_null("Mini_Map")
	if mini_map == null:
		return
	var r: float = minimap_panel.size.x * 0.5
	mini_map.display_radius_px = r
	mini_map._conversion = r / mini_map.detection_radius
	mini_map.position = Vector2(r, r)
	mini_map.queue_redraw()


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
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


# ----------------------------------------------------------------------
# HUD edit mode
# ----------------------------------------------------------------------

func _register_editable_panels() -> void:
	_editable_panels["stats"] = stats_panel
	_editable_panels["minimap"] = minimap_panel
	_editable_panels["score"] = _score_label
	for panel_name: String in _editable_panels:
		_save_panel_default(panel_name, _editable_panels[panel_name])


func _save_panel_default(panel_name: String, panel: Control) -> void:
	_panel_defaults[panel_name] = {
		"al": panel.get_anchor(SIDE_LEFT),
		"at": panel.get_anchor(SIDE_TOP),
		"ar": panel.get_anchor(SIDE_RIGHT),
		"ab": panel.get_anchor(SIDE_BOTTOM),
		"ol": panel.get_offset(SIDE_LEFT),
		"ot": panel.get_offset(SIDE_TOP),
		"or": panel.get_offset(SIDE_RIGHT),
		"ob": panel.get_offset(SIDE_BOTTOM),
	}


func _restore_hud_layout() -> void:
	var layout: Dictionary = Settings.hud_layout
	if layout.get("v", 0) != 3:
		return
	var screen: Vector2 = get_viewport().get_visible_rect().size
	for panel_name: String in _editable_panels:
		if not layout.has(panel_name):
			continue
		var data: Dictionary = layout[panel_name]
		var panel: Control = _editable_panels[panel_name]
		if data.has("x") and data.has("y") and data.has("w") and data.has("h"):
			_set_panel_rect(panel, data["x"] * screen.x, data["y"] * screen.y,
				data["w"] * screen.x, data["h"] * screen.y)


func reset_hud_layout() -> void:
	for panel_name: String in _panel_defaults:
		if not _editable_panels.has(panel_name):
			continue
		var panel: Control = _editable_panels[panel_name]
		var d: Dictionary = _panel_defaults[panel_name]
		panel.set_anchor(SIDE_LEFT,   d["al"])
		panel.set_anchor(SIDE_TOP,    d["at"])
		panel.set_anchor(SIDE_RIGHT,  d["ar"])
		panel.set_anchor(SIDE_BOTTOM, d["ab"])
		panel.set_offset(SIDE_LEFT,   d["ol"])
		panel.set_offset(SIDE_TOP,    d["ot"])
		panel.set_offset(SIDE_RIGHT,  d["or"])
		panel.set_offset(SIDE_BOTTOM, d["ob"])
	Settings.hud_layout = {}
	Settings.save()


func _make_absolute(panel: Control, pos: Vector2) -> void:
	_set_panel_rect(panel, pos.x, pos.y, panel.size.x, panel.size.y)


func _snap_all_panels() -> void:
	for panel_name: String in _editable_panels:
		var panel: Control = _editable_panels[panel_name]
		var gp: Vector2 = panel.global_position
		var sz: Vector2 = panel.size
		_set_panel_rect(panel, gp.x, gp.y, sz.x, sz.y)


func set_ui_edit_mode(enabled: bool) -> void:
	Settings.ui_edit_mode = enabled
	if enabled:
		get_tree().paused = true
		_show_edit_overlay()
		update_grid_visibility()
		if Settings.ui_snap_enabled:
			_snap_all_panels()
	else:
		get_tree().paused = false
		_hide_edit_overlay()
		_save_hud_layout_and_save()


func _show_edit_overlay() -> void:
	if _edit_overlay:
		return
	_edit_overlay = Label.new()
	_edit_overlay.text = "HUD EDIT MODE — Drag to move, drag corner to resize, Esc to save & exit"
	_edit_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit_overlay.set_anchor(SIDE_LEFT, 0.0)
	_edit_overlay.set_anchor(SIDE_RIGHT, 1.0)
	_edit_overlay.set_anchor(SIDE_TOP, 0.0)
	_edit_overlay.set_offset(SIDE_TOP, 4.0)
	_edit_overlay.add_theme_font_size_override("font_size", 16)
	_edit_overlay.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_edit_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_edit_overlay)

	for panel_name: String in _editable_panels:
		var panel: Control = _editable_panels[panel_name]
		_add_edit_corners(panel)
		_add_dimension_labels(panel)
		var tint := ColorRect.new()
		tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tint.color = Color(0.4, 0.35, 0.1, 0.15)
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tint.add_to_group("edit_tint")
		panel.add_child(tint)
		_set_panel_passthrough(panel, true)


func _add_edit_corners(panel: Control) -> void:
	var cs: float = CORNER_SIZE
	for corner: int in 4:
		var handle := ColorRect.new()
		handle.custom_minimum_size = Vector2(cs, cs)
		handle.size = Vector2(cs, cs)
		handle.color = Color(1.0, 0.85, 0.3, 0.8)
		handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		handle.add_to_group("edit_corner")
		handle.set_meta("panel", panel)
		handle.set_meta("corner", corner)
		add_child(handle)
	_update_corner_positions()


func _add_dimension_labels(panel: Control) -> void:
	var w_lbl := Label.new()
	w_lbl.add_theme_font_size_override("font_size", 10)
	w_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 0.9))
	w_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w_lbl.add_to_group("edit_dimension")
	w_lbl.set_meta("panel", panel)
	w_lbl.set_meta("axis", "w")
	add_child(w_lbl)
	var h_lbl := Label.new()
	h_lbl.add_theme_font_size_override("font_size", 10)
	h_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 0.9))
	h_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h_lbl.add_to_group("edit_dimension")
	h_lbl.set_meta("panel", panel)
	h_lbl.set_meta("axis", "h")
	add_child(h_lbl)


func _update_corner_positions() -> void:
	var cs: float = CORNER_SIZE
	for node: Node in get_tree().get_nodes_in_group("edit_corner"):
		var handle: ColorRect = node as ColorRect
		var panel: Control = handle.get_meta("panel")
		var corner: int = handle.get_meta("corner")
		var gp: Vector2 = panel.global_position
		var sz: Vector2 = panel.size
		match corner:
			0: handle.global_position = Vector2(gp.x - cs * 0.5, gp.y - cs * 0.5)
			1: handle.global_position = Vector2(gp.x + sz.x - cs * 0.5, gp.y - cs * 0.5)
			2: handle.global_position = Vector2(gp.x - cs * 0.5, gp.y + sz.y - cs * 0.5)
			3: handle.global_position = Vector2(gp.x + sz.x - cs * 0.5, gp.y + sz.y - cs * 0.5)


func _update_dimension_labels() -> void:
	for node: Node in get_tree().get_nodes_in_group("edit_dimension"):
		var lbl: Label = node as Label
		var panel: Control = lbl.get_meta("panel")
		var axis: String = lbl.get_meta("axis")
		var gp: Vector2 = panel.global_position
		var sz: Vector2 = panel.size
		var grid: float = maxf(Settings.ui_snap_size, 1)
		if axis == "w":
			lbl.text = "%.1f" % (sz.x / grid)
			lbl.global_position = Vector2(gp.x + sz.x * 0.5 - lbl.size.x * 0.5, gp.y + sz.y - lbl.size.y - 2)
		else:
			lbl.text = "%.1f" % (sz.y / grid)
			lbl.global_position = Vector2(gp.x + sz.x - lbl.size.x - 4, gp.y + sz.y * 0.5 - lbl.size.y * 0.5)


func update_grid_visibility() -> void:
	if Settings.ui_edit_mode and Settings.ui_show_grid:
		_show_grid()
	else:
		_hide_grid()


func _show_grid() -> void:
	if _grid_overlay:
		return
	_grid_overlay = Control.new()
	_grid_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_overlay.draw.connect(_draw_grid)
	add_child(_grid_overlay)
	move_child(_grid_overlay, 0)


func _hide_grid() -> void:
	if _grid_overlay:
		_grid_overlay.queue_free()
		_grid_overlay = null


func _draw_grid() -> void:
	if _grid_overlay == null:
		return
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var grid: int = Settings.ui_snap_size
	var color := Color(1.0, 1.0, 1.0, 0.08)
	var x: float = 0.0
	while x <= screen.x:
		_grid_overlay.draw_line(Vector2(x, 0), Vector2(x, screen.y), color)
		x += grid
	var y: float = 0.0
	while y <= screen.y:
		_grid_overlay.draw_line(Vector2(0, y), Vector2(screen.x, y), color)
		y += grid


func _hide_edit_overlay() -> void:
	if _edit_overlay:
		_edit_overlay.queue_free()
		_edit_overlay = null
	_dragging = ""
	_resizing = ""
	_hide_grid()
	for panel_name: String in _editable_panels:
		_set_panel_passthrough(_editable_panels[panel_name], false)
	for node: Node in get_tree().get_nodes_in_group("edit_corner"):
		node.queue_free()
	for node: Node in get_tree().get_nodes_in_group("edit_dimension"):
		node.queue_free()
	for node: Node in get_tree().get_nodes_in_group("edit_tint"):
		node.queue_free()


func _set_panel_passthrough(panel: Control, _passthrough: bool) -> void:
	# Pyrrha's HUD panels are display-only — always IGNORE so clicks reach the game world.
	var queue: Array[Control] = [panel]
	while queue.size() > 0:
		var ctrl: Control = queue.pop_front()
		ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child: Node in ctrl.get_children():
			if child is Control and not child.is_in_group("edit_corner"):
				queue.append(child as Control)


func _unhandled_input(event: InputEvent) -> void:
	if not Settings.ui_edit_mode:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_ui_edit_mode(false)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for panel_name: String in _editable_panels:
				var panel: Control = _editable_panels[panel_name]
				var corner: int = _hit_corner(panel, event.global_position)
				if corner >= 0:
					_resizing = panel_name
					_resize_corner = corner
					_resize_origin = event.global_position
					_resize_start_rect = Rect2(panel.global_position, panel.size)
					get_viewport().set_input_as_handled()
					return
			for panel_name: String in _editable_panels:
				var panel: Control = _editable_panels[panel_name]
				if Rect2(panel.global_position, panel.size).has_point(event.global_position):
					_dragging = panel_name
					_drag_offset = event.global_position - panel.global_position
					get_viewport().set_input_as_handled()
					return
		else:
			var was_active: bool = _dragging != "" or _resizing != ""
			_dragging = ""
			_resizing = ""
			_resize_corner = -1
			if was_active:
				_save_hud_layout_and_save()
				get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _resizing != "":
			var panel: Control = _editable_panels[_resizing]
			var delta: Vector2 = motion.global_position - _resize_origin
			var r: Rect2 = _resize_start_rect
			match _resize_corner:
				0:
					_set_panel_rect(panel, r.position.x + delta.x, r.position.y + delta.y,
						r.size.x - delta.x, r.size.y - delta.y)
				1:
					_set_panel_rect(panel, r.position.x, r.position.y + delta.y,
						r.size.x + delta.x, r.size.y - delta.y)
				2:
					_set_panel_rect(panel, r.position.x + delta.x, r.position.y,
						r.size.x - delta.x, r.size.y + delta.y)
				3:
					_set_panel_rect(panel, r.position.x, r.position.y,
						r.size.x + delta.x, r.size.y + delta.y)
			get_viewport().set_input_as_handled()
		elif _dragging != "":
			var panel: Control = _editable_panels[_dragging]
			_make_absolute(panel, motion.global_position - _drag_offset)
			get_viewport().set_input_as_handled()


func _hit_corner(panel: Control, mouse_pos: Vector2) -> int:
	var cs: float = CORNER_SIZE
	var gp: Vector2 = panel.global_position
	var sz: Vector2 = panel.size
	var corners: Array[Rect2] = [
		Rect2(gp.x - cs * 0.5, gp.y - cs * 0.5, cs, cs),
		Rect2(gp.x + sz.x - cs * 0.5, gp.y - cs * 0.5, cs, cs),
		Rect2(gp.x - cs * 0.5, gp.y + sz.y - cs * 0.5, cs, cs),
		Rect2(gp.x + sz.x - cs * 0.5, gp.y + sz.y - cs * 0.5, cs, cs),
	]
	for i: int in 4:
		if corners[i].has_point(mouse_pos):
			return i
	return -1


func _snap(val: float) -> float:
	return roundf(val / float(Settings.ui_snap_size)) * float(Settings.ui_snap_size)


func _set_panel_rect(panel: Control, x: float, y: float, w: float, h: float) -> void:
	w = maxf(w, 60.0)
	h = maxf(h, 40.0)
	if Settings.ui_edit_mode and Settings.ui_snap_enabled:
		x = _snap(x)
		y = _snap(y)
		w = _snap(w)
		h = _snap(h)
	var screen: Vector2 = get_viewport().get_visible_rect().size
	x = clampf(x, -w + 30.0, screen.x - 30.0)
	y = clampf(y, -h + 30.0, screen.y - 30.0)
	panel.set_anchor(SIDE_LEFT,   0.0)
	panel.set_anchor(SIDE_TOP,    0.0)
	panel.set_anchor(SIDE_RIGHT,  0.0)
	panel.set_anchor(SIDE_BOTTOM, 0.0)
	panel.set_offset(SIDE_LEFT,   x)
	panel.set_offset(SIDE_TOP,    y)
	panel.set_offset(SIDE_RIGHT,  x + w)
	panel.set_offset(SIDE_BOTTOM, y + h)


func _save_hud_layout() -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var layout: Dictionary = {"v": 3}
	for panel_name: String in _editable_panels:
		var panel: Control = _editable_panels[panel_name]
		var pos: Vector2 = panel.global_position
		layout[panel_name] = {
			"x": pos.x / screen.x,
			"y": pos.y / screen.y,
			"w": panel.size.x / screen.x,
			"h": panel.size.y / screen.y,
		}
	Settings.hud_layout = layout


func _save_hud_layout_and_save() -> void:
	_save_hud_layout()
	Settings.save()


func _on_viewport_resized() -> void:
	if Settings.hud_layout.get("v", 0) == 3:
		_restore_hud_layout()
