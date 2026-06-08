extends Area2D
class_name Pellet

var velocity := Vector2.ZERO
var damage: int = 5
var lifetime: float = 1.5


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	_try_hit(body)


func _on_area_entered(area: Node) -> void:
	_try_hit(area)


func _try_hit(other: Node) -> void:
	if "type" in other and other.type == "asteroid":
		GlobalSignals.emit_signal("player_hit_asteroid", other.name, damage)
		queue_free()
