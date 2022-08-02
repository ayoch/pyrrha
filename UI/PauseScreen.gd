extends CanvasLayer


func _ready() -> void:
	get_tree().paused = true


func _on_ContinueButton_pressed() -> void:
	get_tree().paused = false
	queue_free()


func _on_MainMenuButton_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene("res://UI/MainMenuScreen.tscn")


func _on_SaveButton_pressed():
	GlobalSignals.emit_signal("request_save")


func _on_LoadButton_pressed() -> void:
	GlobalSignals.emit_signal("request_load")
