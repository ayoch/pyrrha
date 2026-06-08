extends Node3D

# Stand-in explosion: a glowing sphere that grows and fades, then queue_frees.
# Replace this scene's 3D content with the real model + AnimationPlayer when
# the asset lands.

@export var lifetime: float = 1.6
@export var start_scale: float = 0.04
@export var end_scale: float = 0.35
@export var color: Color = Color(1.0, 0.55, 0.1)

@onready var mesh: MeshInstance3D = $Mesh
var _age: float = 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 2.5
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = _material
	mesh.scale = Vector3.ONE * start_scale


func _process(delta: float) -> void:
	_age += delta
	var t: float = clamp(_age / lifetime, 0.0, 1.0)
	mesh.scale = Vector3.ONE * lerp(start_scale, end_scale, t)
	var c: Color = color
	c.a = 1.0 - t
	_material.albedo_color = c
	if _age >= lifetime:
		queue_free()
