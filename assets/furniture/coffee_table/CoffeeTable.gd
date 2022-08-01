extends StaticBody2D
#
#
#onready var transitionable_area = $TransitionableArea
#
## Declare member variables here. Examples:
## var a = 2
## var b = "text"
#
#
## Called when the node enters the scene tree for the first time.
#func _ready():
#	pass # Replace with function body.
#
##GlobalSignals.emit_signal("made_noise", intensity, self.global_position, "cat", height_layer)
#
#func handle_noise_heard(intensity: int, position: Vector2, type, height: int):
#	if Geometry.is_point_in_polygon(position, tabletop.get_polygon()) == true:
#		return
##	if knows_about_player == true:
##		has_destination = true
##		interact_with_player()
##		return
#
#
#
#	# If the noise isn't made by a fuzzy.
#	if not type == "fuzzy":
#		if position != self.global_position:
#
#			# Diminish noise intensity based on distance.
#			var distance_from_noise = position.distance_to(self.global_position)
#			var local_intensity = intensity - (distance_from_noise / 300)
#
#
#
