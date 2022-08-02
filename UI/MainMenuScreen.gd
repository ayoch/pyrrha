extends CanvasLayer


func _on_New_GameButton_pressed() -> void:
	get_tree().change_scene("res://CutSceneScreen.tscn")


func _on_QuitButton_pressed() -> void:
	get_tree().quit()


func _on_LoadButton_pressed() -> void:
	GlobalSignals.emit_signal("request_load")
