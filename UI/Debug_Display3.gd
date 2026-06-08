extends Label


func _ready() -> void:
	GlobalSignals.update_speed.connect(_on_receive_speed)


func _on_receive_speed(speed: float) -> void:
	text = "speed: %0.0f" % speed
