extends Area2D


signal entered_player_sight_zone
signal exited_player_sight_zone


func _ready():
	pass


		
#func _on_Area2D_body_entered(body):
#	if body.has_method("set_visibility"):
#		body.set_visibility(true)
#
#
#func _on_Area2D_body_exited(body):
#	if body.has_method("set_visibility"):
#		body.set_visibility(false)


func _on_SightZone_body_entered(body):
#	self.over
	if body.has_method("set_visibility"):
		body.set_visibility(true)
	elif body.is_in_group("ping"):
		print("Trying to make a ping invisible.")
		body.visibility = false


func _on_SightZone_body_exited(body):
	if body.has_method("set_visibility"):
		body.set_visibility(false)
	elif body.is_in_group("ping"):
		print("Trying to make a ping visible.")
		body.visibility = true
