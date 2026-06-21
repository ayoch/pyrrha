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
# priority: higher shows first and can preempt a lower one (story > reactive).
# ttl: seconds the line may wait in queue before being dropped as stale
#      (-1 = never expires; story lines use this so they're guaranteed to play).
# Emitted by DialogDirector; consumed by DialogBox.
signal dialog_message(speaker: String, icon_key: String, text: String, priority: int, ttl: float)

# Game-event signals that drive dialog (and anything else interested).
# Emitted by AsteroidManager.
signal stage_started(stage_idx: int)
signal boss_started(stage_idx: int, pattern: String)
signal respite_started(stage_idx: int)
signal earth_impact(deaths: int, size: int, stage_idx: int, was_threat: bool)
signal threat_inbound(size: int)

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
var upgrade_capacitors: int = 0

func award_credits(amount: int) -> void:
	credits += amount
	emit_signal("credits_changed", credits)

func spend_credits(amount: int) -> void:
	credits = max(0, credits - amount)
	emit_signal("credits_changed", credits)

# Run stats — written by AsteroidManager before reset_progress() on death.
var run_stage_reached: int = 1
var run_earth_casualties: int = 0
var run_asteroids_destroyed: int = 0
# Diagnostic — written by Player on the lethal collision so the DeathScreen
# can show which rock killed us (used to debug invisible-asteroid bugs etc.).
var last_killer_info: String = ""

# Deaths tally broken down by impactor size so the player can see which class
# of rock is actually doing the damage. Keys are Asteroid.size (4=whole, 1=small).
var deaths_by_size: Dictionary = {4: 0, 3: 0, 2: 0, 1: 0}

func reset_progress() -> void:
	credits = 0
	upgrade_hull = 0
	upgrade_shields = 0
	upgrade_energy = 0
	upgrade_engines = 0
	upgrade_capacitors = 0
	emit_signal("credits_changed", credits)
signal game_won()
signal player_died()
signal turret_state_changed(enabled: bool)
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
