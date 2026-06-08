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
