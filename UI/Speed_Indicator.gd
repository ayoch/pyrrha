extends RichTextLabel


func _ready():
	GlobalSignals.connect("update_speed", self, "on_receive_speed")


func on_receive_speed(speed):
	self.text = str(speed)
