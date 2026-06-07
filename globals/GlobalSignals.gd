extends Node

# Player
signal active_room(room_name: String)
signal player_exists()
signal broadcast_player_position(position: Vector2)
signal player_health_changed(health: float)
signal player_energy_changed(energy: float)
signal update_speed(speed: float)

# Combat / Noise
signal made_noise(intensity: float, position: Vector2, source: String, height_layer: int)
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
