extends Node2D
class_name DefenseLaserTurret

@export var range_units: float = 800.0
@export var fire_rate_hz: float = 4.0
@export var laser_damage_per_tick: int = 8
@export var beam_color: Color = Color(1.0, 0.35, 0.05, 1.0)
@export var beam_flash_duration: float = 0.07

var energy_fraction: float = 1.0
var _cooldown: float = 0.0
var _beam_timer: float = 0.0
var _beam_end: Vector2 = Vector2.ZERO
var _beam: Line2D
var _ray: RayCast2D
var _active_target: bool = false


func _ready() -> void:
	_beam = Line2D.new()
	_beam.width = 2.0
	_beam.default_color = beam_color
	_beam.joint_mode = Line2D.LINE_JOINT_ROUND
	_beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_beam.end_cap_mode = Line2D.LINE_CAP_ROUND
	_beam.antialiased = true
	_beam.z_index = 8
	_beam.visible = false
	add_child(_beam)

	_ray = RayCast2D.new()
	_ray.collision_mask = 6
	_ray.enabled = true
	add_child(_ray)


func _physics_process(delta: float) -> void:
	_cooldown = max(0.0, _cooldown - delta)
	_beam_timer = max(0.0, _beam_timer - delta)

	if _beam_timer > 0.0:
		_beam.clear_points()
		_beam.add_point(Vector2.ZERO)
		_beam.add_point(_beam_end)
		_beam.visible = true
	else:
		_beam.clear_points()
		_beam.visible = false

	var target: Node2D = _find_nearest_asteroid()
	_active_target = target != null
	if target == null:
		return

	look_at(target.global_position)

	if _cooldown > 0.0:
		return

	_fire(target)
	_cooldown = 1.0 / fire_rate_hz


func is_firing() -> bool:
	return _active_target


func _find_nearest_asteroid() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist_sq: float = range_units * range_units
	for body: Node in get_tree().get_nodes_in_group("asteroid"):
		if not body is Node2D:
			continue
		var d: float = global_position.distance_squared_to((body as Node2D).global_position)
		if d < nearest_dist_sq:
			nearest_dist_sq = d
			nearest = body as Node2D
	return nearest


func _fire(target: Node2D) -> void:
	var to_target: Vector2 = to_local(target.global_position)
	_ray.target_position = to_target
	_ray.force_raycast_update()

	var end_point: Vector2 = to_target
	if _ray.is_colliding():
		var collider: Node = _ray.get_collider()
		end_point = to_local(_ray.get_collision_point())
		if collider != null and "type" in collider and collider.type == "asteroid":
			var dmg: int = max(1, int(laser_damage_per_tick * energy_fraction))
			GlobalSignals.emit_signal("player_hit_asteroid", collider.name, dmg)

	_beam_end = end_point
	_beam_timer = beam_flash_duration
	var alpha: float = lerpf(0.25, 1.0, energy_fraction)
	_beam.modulate = Color(1.0, 1.0, 1.0, alpha)
