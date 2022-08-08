extends TextEdit


func _ready():
	GlobalSignals.connect("broadcast_player_position", self, "on_receive_player_position")


func on_receive_player_position(pos):
	pass
