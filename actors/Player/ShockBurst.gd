extends Node2D
class_name ShockBurst

# Brief radial spark/flash at a contact point. Pooled — emit() resets state,
# _process animates fade and slight expansion, returns to pool via callback.

@export var lifetime: float = 0.18
@export var num_rays: int = 8
@export var inner_radius: float = 3.0
@export var outer_radius: float = 22.0
@export var color: Color = Color(1.0, 0.95, 0.7, 1.0)
@export var line_width: float = 1.6

var _age: float = 0.0
var _on_done: Callable
var _rot: float = 0.0


func emit(at_pos: Vector2, callback: Callable) -> void:
	global_position = at_pos
	_rot = randf() * TAU
	visible = true
	_age = 0.0
	_on_done = callback
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		visible = false
		set_process(false)
		if _on_done.is_valid():
			_on_done.call(self)
		return
	queue_redraw()


func _draw() -> void:
	var t: float = _age / lifetime
	var a: float = 1.0 - t
	var outer: float = lerp(outer_radius * 0.4, outer_radius, t)
	var c: Color = color
	c.a *= a
	for i in num_rays:
		var ang: float = _rot + i * TAU / num_rays
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		draw_line(dir * inner_radius, dir * outer, c, line_width, true)
