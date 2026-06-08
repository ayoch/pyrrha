extends CanvasLayer

# Escape-triggered pause menu. Pauses the SceneTree while visible. Settings
# panel toggles between control schemes (stored on GlobalSignals so the Player
# script picks it up live).

@onready var main_panel: PanelContainer = $Backdrop/Center/MainPanel
@onready var settings_panel: PanelContainer = $Backdrop/Center/SettingsPanel
@onready var mouse_turn_btn: Button = $Backdrop/Center/SettingsPanel/Rows/MouseTurnButton
@onready var keyboard_turn_btn: Button = $Backdrop/Center/SettingsPanel/Rows/KeyboardTurnButton
@onready var dialog_toggle: Button = $Backdrop/Center/SettingsPanel/Rows/DialogToggle
@onready var dialog_fast_btn: Button = $Backdrop/Center/SettingsPanel/Rows/DialogSpeedRow/DialogFastButton
@onready var dialog_normal_btn: Button = $Backdrop/Center/SettingsPanel/Rows/DialogSpeedRow/DialogNormalButton
@onready var dialog_slow_btn: Button = $Backdrop/Center/SettingsPanel/Rows/DialogSpeedRow/DialogSlowButton
@onready var ui_scale_slider: HSlider = $Backdrop/Center/SettingsPanel/Rows/UIScaleRow/UIScaleSlider
@onready var ui_scale_label: Label = $Backdrop/Center/SettingsPanel/Rows/UIScaleRow/UIScaleLabel
@onready var center: CenterContainer = $Backdrop/Center
@onready var snap_toggle: CheckButton = $Backdrop/Center/SettingsPanel/Rows/HUDSnapRow/SnapToggle
@onready var show_grid_toggle: CheckButton = $Backdrop/Center/SettingsPanel/Rows/HUDSnapRow/ShowGridToggle


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	settings_panel.visible = false
	_apply_ui_scale(Settings.ui_scale)


func _unhandled_input(event: InputEvent) -> void:
	if Settings.ui_edit_mode:
		return
	if event.is_action_pressed("pause"):
		if visible:
			if settings_panel.visible:
				_back_to_main()
			else:
				_hide_menu()
		else:
			_show_menu()
		get_viewport().set_input_as_handled()


func _show_menu() -> void:
	visible = true
	main_panel.visible = true
	settings_panel.visible = false
	get_tree().paused = true


func _hide_menu() -> void:
	visible = false
	get_tree().paused = false


func _back_to_main() -> void:
	settings_panel.visible = false
	main_panel.visible = true


# ---- Main panel buttons -----------------------------------------------------

func _on_resume_pressed() -> void:
	_hide_menu()


func _on_save_pressed() -> void:
	GlobalSignals.emit_signal("request_save")


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Main.tscn")


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://UI/MainMenuScreen.tscn")


func _on_settings_pressed() -> void:
	main_panel.visible = false
	settings_panel.visible = true
	_refresh_settings_state()


func _on_quit_pressed() -> void:
	get_tree().quit()


# ---- Settings panel ---------------------------------------------------------

func _apply_ui_scale(scale_val: float) -> void:
	center.pivot_offset = center.size / 2.0
	center.scale = Vector2(scale_val, scale_val)


func _refresh_settings_state() -> void:
	var m: int = GlobalSignals.control_mode
	mouse_turn_btn.button_pressed = (m == GlobalSignals.ControlMode.MOUSE_TURN)
	keyboard_turn_btn.button_pressed = (m == GlobalSignals.ControlMode.KEYBOARD_TURN)
	dialog_toggle.button_pressed = GlobalSignals.dialog_enabled
	var d: float = GlobalSignals.dialog_dismiss_sec
	dialog_fast_btn.button_pressed   = (d == 4.0)
	dialog_normal_btn.button_pressed = (d == 7.0)
	dialog_slow_btn.button_pressed   = (d == 12.0)
	ui_scale_slider.value = Settings.ui_scale
	ui_scale_label.text = "%.2fx" % Settings.ui_scale
	snap_toggle.button_pressed = Settings.ui_snap_enabled
	show_grid_toggle.button_pressed = Settings.ui_show_grid


func _on_mouse_turn_pressed() -> void:
	GlobalSignals.control_mode = GlobalSignals.ControlMode.MOUSE_TURN
	_refresh_settings_state()


func _on_keyboard_turn_pressed() -> void:
	GlobalSignals.control_mode = GlobalSignals.ControlMode.KEYBOARD_TURN
	_refresh_settings_state()


func _on_dialog_toggle_toggled(pressed: bool) -> void:
	GlobalSignals.dialog_enabled = pressed
	_refresh_settings_state()


func _on_dialog_fast_pressed() -> void:
	GlobalSignals.dialog_dismiss_sec = 4.0
	_refresh_settings_state()


func _on_dialog_normal_pressed() -> void:
	GlobalSignals.dialog_dismiss_sec = 7.0
	_refresh_settings_state()


func _on_dialog_slow_pressed() -> void:
	GlobalSignals.dialog_dismiss_sec = 12.0
	_refresh_settings_state()


func _on_ui_scale_changed(value: float) -> void:
	Settings.ui_scale = value
	Settings.save()
	ui_scale_label.text = "%.2fx" % value
	_apply_ui_scale(value)


func _on_edit_hud_pressed() -> void:
	visible = false
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_ui_edit_mode"):
		hud.set_ui_edit_mode(true)


func _on_snap_toggled(pressed: bool) -> void:
	Settings.ui_snap_enabled = pressed
	Settings.save()


func _on_show_grid_toggled(pressed: bool) -> void:
	Settings.ui_show_grid = pressed
	Settings.save()
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_grid_visibility"):
		hud.update_grid_visibility()


func _on_reset_hud_pressed() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("reset_hud_layout"):
		hud.reset_hud_layout()


func _on_back_pressed() -> void:
	_back_to_main()
