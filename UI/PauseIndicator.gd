extends TextEdit


# Declare member variables here. Examples:
# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	self.visible = false
	GlobalSignals.connect("paused", self, "handle_pause")


func handle_pause(message):
	if message == "unpaused":
		self.visible = false
	elif message == "paused":
		self.visible = true
