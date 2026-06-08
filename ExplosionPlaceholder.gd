extends Node3D

# Stand-in explosion: a glowing sphere that grows and fades, then queue_frees.
# Replace this scene's 3D content with the real model + AnimationPlayer when
# the asset lands.

@export var lifetime: float = 5.0
@export var start_scale: float = 0.02
@export var end_scale: float = 0.55
@export var color: Color = Color(1.0, 0.55, 0.1)
# Fraction of lifetime spent expanding vs. fading.
# e.g. 0.5 = first half grows, second half holds then fades.
@export var expand_fraction: float = 0.45
@export var hold_fraction: float = 0.25   # after expand, before fade

@onready var mesh: MeshInstance3D = $Mesh
var _age: float = 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 3.0
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = _material
	mesh.scale = Vector3.ONE * start_scale


func _process(delta: float) -> void:
	_age += delta
	var t: float = clamp(_age / lifetime, 0.0, 1.0)

	var expand_end: float = expand_fraction
	var hold_end: float = expand_fraction + hold_fraction

	var scale_t: float
	if t <= expand_end:
		# Slow ease-in during expansion: sqrt gives fast start, then decelerates.
		scale_t = sqrt(t / expand_end)
	else:
		scale_t = 1.0
	mesh.scale = Vector3.ONE * lerp(start_scale, end_scale, scale_t)

	var alpha: float
	if t <= hold_end:
		alpha = 1.0
	else:
		alpha = 1.0 - clamp((t - hold_end) / (1.0 - hold_end), 0.0, 1.0)

	var c: Color = color
	c.a = alpha
	_material.albedo_color = c
	if _age >= lifetime:
		queue_free()
