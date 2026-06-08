extends Node

# Control scheme. Read by Player; written by PauseMenu's Settings panel.
enum ControlMode { MOUSE_TURN, KEYBOARD_TURN }
var control_mode: int = ControlMode.MOUSE_TURN

# Player lifecycle
signal player_exists()
signal broadcast_player_position(position: Vector2)
signal player_health_changed(health: float)
signal player_energy_changed(energy: float)
signal player_shield_changed(shield: float)

# Casualty score (cumulative deaths from Earth impacts).
signal total_deaths_changed(total: int)

# Stage / status bar — fired by AsteroidManager, displayed by GUI.
signal status_message(text: String)

# Dialog box — queued, auto-dismissed. speaker is a display name; icon_key
# maps to a portrait in DialogBox.PORTRAITS ("kaowitz", etc.).
signal dialog_message(speaker: String, icon_key: String, text: String)

# Dialog settings (read by DialogBox; written by PauseMenu settings).
var dialog_enabled: bool = true
var dialog_dismiss_sec: float = 7.0

# Station shop
signal open_station_shop()
signal station_shop_departed()
signal credits_changed(amount: int)

var credits: int = 0
var upgrade_hull: int = 0
var upgrade_shields: int = 0
var upgrade_energy: int = 0
var upgrade_engines: int = 0

func award_credits(amount: int) -> void:
	credits += amount
	emit_signal("credits_changed", credits)

func spend_credits(amount: int) -> void:
	credits = max(0, credits - amount)
	emit_signal("credits_changed", credits)

func reset_progress() -> void:
	credits = 0
	upgrade_hull = 0
	upgrade_shields = 0
	upgrade_energy = 0
	upgrade_engines = 0
	emit_signal("credits_changed", credits)
signal game_won()
signal player_died()
signal update_speed(speed: float)

# Combat
signal player_hit_asteroid(asteroid_name: String, damage: int)

# Asteroids
signal asteroid_died(asteroid)

# Save / Load
signal request_save()
signal request_load()

# Pause
signal paused(is_paused: bool)

# Debug display
signal add_to_debug_display(message: String)
signal set_debug_display(message: String)
signal add_to_debug2_display(message: String)
signal set_debug2_display(message: String)

# Minimap
signal send_minimap_data()
signal request_minimap_data()
