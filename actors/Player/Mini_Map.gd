extends Node2D

#Physics frequency timer.
var frequency_counter: int = 0
onready var updates_per_second: int = 1

var player_position
var objects_to_display
var conversion_ratio: float

onready var player_sprite = $player
onready var earth = $earth

#detection radius.
export var detection_radius: float = 20000

#Preload minimap icons.
var player_sprite_texture = preload("res://actors/Player/NicePng_spaceship-sprite-png_3369998.png")

var current_visible_asteroid

#var miniw

func _ready():
	conversion_ratio = 130/detection_radius
	GlobalSignals.connect("send_minimap_data", self, "on_send_minimap_data")
#	GlobalSignals.connect("update_minimap", self, "on_update_minimap")


#func on_update_minimap(scene):
#	pass


func manage_physics_frequency():
	frequency_counter += 1
	if frequency_counter % (60/updates_per_second) == 0:
		GlobalSignals.emit_signal("request_minimap_data")
	if frequency_counter == 60:
		frequency_counter = 1


func _physics_process(delta):
	manage_physics_frequency()


#func on_send_minimap_data(data):
#	for child in self.get_children():
#		if child.name != "background" and child.name != "player":
#			child.queue_free()
#
#	objects_to_display = data
#	var player_position
#	for thing in data:
#		if thing.is_in_group("player"):
#			player_position = thing.position
#
#	for object in objects_to_display:
#
#		if object.global_position.distance_to(player_position) <= detection_radius:
#
#			if objects_to_display.size() != 0:
#
#				for node in objects_to_display:
#					if node.is_in_group("player") and node.get_child(0) != null:
#
#						player_sprite.set_texture(player_sprite_texture) 
#						player_sprite.scale.x = 0.05
#						player_sprite.scale.y = 0.05
#						player_sprite.rotation = node.rotation
#
#						player_sprite.global_position = self.global_position
#						player_sprite.visible = true
#					else:
#						player_sprite.visible == false
#
#					if node.is_in_group("asteroid") and node.is_in_group("minimap"):
#						var new_asteroid_sprite = Sprite.new()
#						new_asteroid_sprite.set_texture(load("res://asteroids/Chondrite/C1/C1whole.png"))
#						new_asteroid_sprite.scale.x = .01
#						new_asteroid_sprite.scale.y = .01
#
#						new_asteroid_sprite.visible = true
#
#						self.add_child(new_asteroid_sprite)
#						new_asteroid_sprite.global_position = ((node.global_position - player_position) * conversion_ratio) + self.global_position


func on_send_minimap_data(data, player_pos):
#	Make asteroid pool invisible.
	for child in self.get_children():
		if child.name != "background" and child.name != "player":
			child.visible = false

	player_position = player_pos
	objects_to_display = data
	
	var message = "Minimap objects: " + str(objects_to_display.size())
	GlobalSignals.emit_signal("set_debug2_display", message)
#	print(message)
#	print("Number of objects to display: ", objects_to_display.size())
#	Return if the arrary's empty.
	if objects_to_display.size() == 0:
		return
#	Go through array of list of objects that need to be displayed.
	for object in objects_to_display:
		if object.is_in_group("player"):
			player_sprite.set_texture(player_sprite_texture) 
			player_sprite.scale.x = 0.02
			player_sprite.scale.y = 0.02
			player_sprite.rotation = object.rotation

			player_sprite.global_position = self.global_position
			player_sprite.visible = true
		elif object.is_in_group("earth"):
			earth.scale.x = .02
			earth.scale.y = .02
			earth.visible = true
			earth.global_position = ((object.global_position - player_position) * conversion_ratio) + self.global_position
		else:
			player_sprite.visible == false
		
		if object.is_in_group("asteroid"):
			current_visible_asteroid = get_unused_asteroid()
			
			if !current_visible_asteroid:
				current_visible_asteroid = Sprite.new()
				add_child(current_visible_asteroid)
				
			current_visible_asteroid.scale.x = .5
			current_visible_asteroid.scale.y = .5
			current_visible_asteroid.rotation = object.rotation
			current_visible_asteroid.visible = true
			current_visible_asteroid.set_texture(load("res://asteroids/Chondrite/C1/C1lowres.png"))
			current_visible_asteroid.global_position = ((object.global_position - player_position) * conversion_ratio) + self.global_position
			
#			for child in self.get_children():
#
#	#			print("Adding data to asteroids and making them visible.")
#				if child.visible == false:
#						child.set_texture(load("res://asteroids/Chondrite/C1/C1whole.png"))
#						child.scale.x = .01
#						child.scale.y = .01
#						child.visible = true
#						child.global_position = ((object.global_position - player_position) * conversion_ratio) + self.global_position
#						return


func get_unused_asteroid():
	for child in self.get_children():
		if child.visible == false and child.name != "player" and child.name != "background" and child.name != "earth":
			return child
