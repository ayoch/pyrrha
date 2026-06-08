extends Sprite2D
class_name DustCloud

# A pooled puff of asteroid dust. emit() randomizes everything independently
# so a batch of puffs from one break looks chaotic: each has its own texture,
# lifetime, initial scale, expansion rate, spin, drift direction + speed,
# drag, and aspect ratio.

const TEXTURES: Array = [
	preload("res://assets/dust_1.png"),
	preload("res://assets/dust_2.png"),
	preload("res://assets/dust_3.png"),
	preload("res://assets/dust_4.png"),
	preload("res://assets/dust_5.png"),
]

# All puffs start very small and expand outward — initial scale shared between
# normal and mega puffs; mega vs normal differs by lifetime + expansion + speed.
# All dust starts SMALL — universally. The eventual size of a puff is
# determined purely by how long it lives × how fast it expands. "Big" clouds
# earn their size from growth, not from spawning large.
@export var start_scale_min: float = 0.02
@export var start_scale_max: float = 0.08

# Normal puffs — wide spread across lifetimes, growth, drift.
@export var lifetime_min: float = 4.0
@export var lifetime_max: float = 40.0
@export var expansion_min: float = 0.02    # per-second scale growth
@export var expansion_max: float = 2.5
@export var rot_rate_min: float = -0.6
@export var rot_rate_max: float = 0.6
@export var speed_min: float = 0.0         # drift speed (world units/sec)
@export var speed_max: float = 450.0

# Mega puffs — long-lived; expand into something huge over time.
@export var mega_chance: float = 0.20
@export var mega_lifetime_min: float = 60.0
@export var mega_lifetime_max: float = 240.0
@export var mega_expansion_min: float = 0.2
@export var mega_expansion_max: float = 2.0
@export var mega_speed_min: float = 0.0
@export var mega_speed_max: float = 140.0

# Density falloff exponent. 2.0 = physically correct 1/area for a 2D cloud
# (aggressive fade as it grows). 1.0 = 1/linear_scale (gentler). Lower values
# keep clouds visible longer as they expand.
@export var density_power: float = 1.0

# Drift drag: per-second multiplier on velocity (1.0 = no drag, 0 = stop immediately).
@export var drag_min: float = 0.4
@export var drag_max: float = 0.85

# Non-uniform scale: how much the x and y scales can differ. 0 = perfectly
# round, 0.6 = one axis can be 60% smaller than the other.
@export var asymmetry: float = 0.45

# Render layer. Asteroids sit at z=3; below_layer_chance puts a puff at z=2
# (rendered behind the rocks) instead of z=4 (in front). 0.5 = even split.
@export var below_layer_chance: float = 0.5
const Z_ABOVE_ASTEROIDS := 4
const Z_BELOW_ASTEROIDS := 2

# Velocity inheritance. Most puffs carry forward the dying rock's momentum
# (scaled by inherit_factor) plus a radial spray component for spread; a
# small fraction get a fully random velocity instead.
@export var inherit_factor_min: float = 0.5
@export var inherit_factor_max: float = 1.3
@export var random_velocity_chance: float = 0.15

var _age: float = 0.0
var _lifetime: float = 1.5
var _start_scale_x: float = 0.2
var _start_scale_y: float = 0.2
var _expansion_rate: float = 0.2
var _rot_rate: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _drag: float = 1.0
var _is_ghost: bool = false
var _ghost_alpha: float = 0.15
var _on_done: Callable


func emit(at_pos: Vector2, parent_velocity: Vector2, callback: Callable) -> void:
	global_position = at_pos
	texture = TEXTURES[randi() % TEXTURES.size()]
	rotation = randf() * TAU
	z_index = Z_BELOW_ASTEROIDS if randf() < below_layer_chance else Z_ABOVE_ASTEROIDS

	_is_ghost = false
	var s_base: float = randf_range(start_scale_min, start_scale_max)
	var spray_speed: float
	if randf() < mega_chance:
		_lifetime = randf_range(mega_lifetime_min, mega_lifetime_max)
		_expansion_rate = randf_range(mega_expansion_min, mega_expansion_max)
		spray_speed = randf_range(mega_speed_min, mega_speed_max)
	else:
		_lifetime = randf_range(lifetime_min, lifetime_max)
		_expansion_rate = randf_range(expansion_min, expansion_max)
		spray_speed = randf_range(speed_min, speed_max)
	# Velocity: most puffs inherit the dying rock's momentum and add a radial
	# spray so the cloud spreads in all directions. A small fraction get a
	# fully random velocity for visual variety.
	if randf() < random_velocity_chance:
		_velocity = _random_dir() * spray_speed * 2.0
	else:
		var inherit: float = randf_range(inherit_factor_min, inherit_factor_max)
		_velocity = parent_velocity * inherit + _random_dir() * spray_speed

	# Independently squash one axis to break visual symmetry.
	var ax_scale: float = 1.0 + randf_range(-asymmetry, asymmetry)
	_start_scale_x = s_base
	_start_scale_y = s_base * ax_scale

	_rot_rate = randf_range(rot_rate_min, rot_rate_max)
	_drag = randf_range(drag_min, drag_max)

	scale = Vector2(_start_scale_x, _start_scale_y)
	modulate = Color(1, 1, 1, 1)
	visible = true
	_age = 0.0
	_on_done = callback
	set_process(true)


# Rare large wisp: starts as a thin cloud and drifts away slowly over minutes.
func emit_ghost(at_pos: Vector2, callback: Callable) -> void:
	global_position = at_pos
	texture = TEXTURES[randi() % TEXTURES.size()]
	rotation = randf() * TAU
	z_index = Z_BELOW_ASTEROIDS
	_is_ghost = true
	_lifetime = randf_range(400.0, 900.0)
	var s: float = randf_range(4.0, 12.0)
	var ax: float = 1.0 + randf_range(-0.7, 0.7)
	_start_scale_x = s
	_start_scale_y = s * ax
	_expansion_rate = randf_range(0.005, 0.025)
	_rot_rate = randf_range(-0.015, 0.015)
	var speed: float = randf_range(1.0, 12.0)
	_velocity = _random_dir() * speed
	_drag = randf_range(0.97, 0.995)
	_ghost_alpha = randf_range(0.08, 0.18)
	scale = Vector2(_start_scale_x, _start_scale_y)
	modulate = Color(1, 1, 1, _ghost_alpha)
	visible = true
	_age = 0.0
	_on_done = callback
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	rotation += _rot_rate * delta
	global_position += _velocity * delta
	_velocity *= pow(_drag, delta)
	var grow: float = _expansion_rate * _age
	scale = Vector2(_start_scale_x + grow, _start_scale_y + grow)
	var time_fade: float = 1.0 - clamp(_age / _lifetime, 0.0, 1.0)
	if _is_ghost:
		# Ghost wisps barely grow and barely drift; just fade linearly over their long life.
		modulate.a = _ghost_alpha * time_fade
	else:
		# Density-driven alpha. power=1 is 1/linear_scale — gentler so clouds stay visible
		# longer as they expand. Multiplied by linear time fade for lifetime end.
		var area_ratio: float = (scale.x * scale.y) / max(0.0001, _start_scale_x * _start_scale_y)
		var linear_ratio: float = sqrt(area_ratio)
		var density: float = pow(1.0 / linear_ratio, density_power)
		modulate.a = density * time_fade
	if _age >= _lifetime:
		visible = false
		set_process(false)
		if _on_done.is_valid():
			_on_done.call(self)


func _random_dir() -> Vector2:
	var a: float = randf() * TAU
	return Vector2(cos(a), sin(a))
