extends CanvasLayer

@onready var menu_button: Button = $Center/Panel/Rows/MenuButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	GlobalSignals.game_won.connect(_on_won)
	menu_button.pressed.connect(_on_menu_pressed)


func _on_won() -> void:
	visible = true
	get_tree().paused = true


func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://UI/MainMenuScreen.tscn")
