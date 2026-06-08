extends CanvasLayer

@onready var retry_button: Button = $Center/Panel/Rows/RetryButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	GlobalSignals.player_died.connect(_on_died)
	retry_button.pressed.connect(_on_retry_pressed)


func _on_died() -> void:
	visible = true
	get_tree().paused = true


func _on_retry_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Main.tscn")
