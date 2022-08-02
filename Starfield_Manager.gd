extends Node2D


var radius: int = 30000
var center_point = Vector2.ZERO
var position_array = []
var rng = RandomNumberGenerator.new()
var last_position = Vector2.ZERO
var randomized_rotation: int = 0
var spacing: int = 2000
var starfield_visibility_radius = 8000
var counter = 0


func _ready():
	GlobalSignals.connect("broadcast_player_position", self, "_on_received_player_position")
	rng.randomize()
	generate_star_fields()


func _physics_process(delta):
	if counter % 30 == 0:
		pass
#		print(self.get_child_count(), " starfields currently.")
	counter += 1
	if counter == 60:
		counter == 0


func generate_star_fields():
	var current_point = center_point
	var distance = current_point.distance_to(center_point)
	
#	Move to bottom.
	while current_point.distance_to(center_point) < radius:
		current_point.y += spacing
	

	while true:
		#	Move to the left.
		while true:
			if current_point.distance_to(center_point) > radius:
				current_point.x += spacing
				break
			current_point.x -= spacing
		
		
		if current_point.distance_to(center_point) > radius:
			break
		make_row(current_point)
		current_point.y -= spacing
	print(self.get_child_count(), " starfields created. Woah.")


func make_row(current_point):
	while current_point.distance_to(center_point) <= radius:
		current_point.x += spacing
		if is_duplicate_starfield(current_point) == false:
			var sf = generate_starfield()
			sf.global_position = current_point
			self.add_child(sf)


func report_distance(current_point):
	print("Distance from current point to center is: ", current_point.distance_to(center_point))
	print("Current point is: ", current_point)


func clean_up_fields():
	var deleted = 0
	var fields = self.get_children()
	for field in fields:
		for other_field in fields:
			if (field.global_position.x == other_field.global_position.x) and (field.global_position.y == other_field.global_position.y) and (field.name != other_field.name):
				other_field.queue_free()
				deleted += 1
	print("Deleted " , deleted, " fields.")


func is_duplicate_starfield(position):
	var true_or_false = false
	var fields = self.get_children()
	for starfield in fields:
		if starfield.global_position == position:
				true_or_false = true
	return true_or_false


func generate_starfield():
	var new_starfield = Sprite.new()
	new_starfield.texture = load("res://2000x2000pxStarfield_2_LessStars.png")
	randomized_rotation = rng.randi_range(1, 4)
	if randomized_rotation == 2:
		new_starfield.rotation_degrees = 90
	elif randomized_rotation == 3:
		new_starfield.rotation_degrees = 180
	elif randomized_rotation == 4:
		new_starfield.rotation_degrees = 270
	
	return new_starfield


func _on_received_player_position(position):
	for child in self.get_children():
		if child.global_position.distance_to(position) > starfield_visibility_radius:
			child.visible = false
		else:
			child.visible = true
