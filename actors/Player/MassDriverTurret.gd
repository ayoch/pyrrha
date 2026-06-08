extends Node2D
class_name MassDriverTurret

# All upgradable later.
@export var range_units: float = 1200.0
@export var fire_rate_hz: float = 6.0
@export var pellet_speed: float = 2400.0
@export var pellet_damage: int = 5
@export var pellet_lifetime: float = 1.5
@export var pellet_scene: PackedScene

var _cooldown := 0.0


func _physics_process(delta: float) -> void:
	_cooldown = max(0.0, _cooldown - delta)

	var target := _find_nearest_asteroid()
	if target == null:
		return

	look_at(target.global_position)

	if _cooldown <= 0.0:
		_fire(target.global_position)
		_cooldown = 1.0 / fire_rate_hz


func _find_nearest_asteroid() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist_sq := range_units * range_units
	for body in get_tree().get_nodes_in_group("asteroid"):
		if not body is Node2D:
			continue
		var d := global_position.distance_squared_to(body.global_position)
		if d < nearest_dist_sq:
			nearest_dist_sq = d
			nearest = body
	return nearest


func _fire(target_pos: Vector2) -> void:
	if pellet_scene == null:
		push_warning("MassDriverTurret has no pellet_scene assigned.")
		return
	var pellet := pellet_scene.instantiate()
	pellet.global_position = global_position
	pellet.velocity = global_position.direction_to(target_pos) * pellet_speed
	pellet.damage = pellet_damage
	pellet.lifetime = pellet_lifetime
	get_tree().current_scene.add_child(pellet)
