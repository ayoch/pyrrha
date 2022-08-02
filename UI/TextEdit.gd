extends TextEdit


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
#	GlobalSignals.connect("player_position_changed", self, "on_player_position_changed")
	pass

func on_player_position_changed(position):
	var x = stepify(position.x, 0.01)
	var y = stepify(position.y, 0.01)
	var text = "player position: %s, %s" % [x, y]
	self.set_text(text)


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


#func on_player_position_changed(position):
#	position.x = stepify(position.x, 0.01)
#	position.y = stepify(position.y, 0.01)
#	self.set_text(position)
