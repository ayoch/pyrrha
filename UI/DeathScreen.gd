extends CanvasLayer

@onready var retry_button: Button = $Center/Panel/Rows/RetryButton
@onready var stats_label: Label = $Center/Panel/Rows/Stats


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	GlobalSignals.player_died.connect(_on_died)
	retry_button.pressed.connect(_on_retry_pressed)


func _on_died() -> void:
	stats_label.text = _build_report()
	visible = true
	get_tree().paused = true


func _on_retry_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Main.tscn")


func _build_report() -> String:
	var total_stages: int = 6
	var stage: int = GlobalSignals.run_stage_reached
	var casualties: int = GlobalSignals.run_earth_casualties
	var destroyed: int = GlobalSignals.run_asteroids_destroyed
	var base := "Stage %d of %d\n%s Earth casualties\n%d asteroids destroyed" % [
		stage, total_stages, _fmt(casualties), destroyed
	]
	var killer: String = GlobalSignals.last_killer_info
	if killer != "":
		base += "\n\n" + killer
	return base


func _fmt(n: int) -> String:
	if n == 0:
		return "No"
	if n >= 1_000_000:
		return "%.1fM" % (float(n) / 1_000_000.0)
	if n >= 1_000:
		return "%.1fk" % (float(n) / 1_000.0)
	return str(n)
