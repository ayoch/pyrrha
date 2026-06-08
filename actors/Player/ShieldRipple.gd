extends Sprite2D
class_name ShieldRipple

@export var lifetime: float = 0.4
@export var start_scale: float = 0.4
@export var end_scale: float = 1.2

var _age: float = 0.0
var _on_done: Callable


func emit(at_global_position: Vector2, normal: Vector2, callback: Callable) -> void:
	global_position = at_global_position
	rotation = normal.angle()
	scale = Vector2.ONE * start_scale
	modulate.a = 1.0
	visible = true
	_age = 0.0
	_on_done = callback
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	var t: float = clamp(_age / lifetime, 0.0, 1.0)
	scale = Vector2.ONE * lerp(start_scale, end_scale, t)
	modulate.a = 1.0 - t
	if _age >= lifetime:
		visible = false
		set_process(false)
		if _on_done.is_valid():
			_on_done.call(self)
