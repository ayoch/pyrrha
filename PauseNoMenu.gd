extends Node2D

#
#func _ready() -> void:
#	pass
#func _physics_process(delta):
#	if event.is_action_pressed("pause_without_menu"):
#		if get_tree().paused == true:
#			get_tree().paused = false
#		elif get_tree().paused == false:
#			get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_without_menu"):
		if get_tree().paused == true:
			GlobalSignals.emit_signal("paused", "unpaused")
			get_tree().paused = false
		elif get_tree().paused == false:
			GlobalSignals.emit_signal("paused", "paused")
			get_tree().paused = true
