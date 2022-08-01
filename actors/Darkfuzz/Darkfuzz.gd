extends KinematicBody2D

signal died

var navigation_polygon
var player

onready var coffee_table 
onready var rand 
onready var timer = $Timer
onready var animation_player = $Sprite/AnimationPlayer
onready var sprite = $Sprite
onready var collision_shape = $CollisionShape2D 
onready var darkfuzz_destination = get_node("/root/Main/DarkfuzzDestination")
onready var path_line = $PathLine
onready var navigation_controller 

var speed = 70
var base_speed = 70
export (bool) var should_draw_path_line := true

var height_layer: int = 1
var health: int = 100
var velocity: Vector2 = Vector2.ZERO
var physics_timer: int = 0

# Navigation.
var needs_to_start_transition = false
var is_in_transition = false
var destination_list = PoolVector2Array()
var path = PoolVector2Array()
var last_position: Vector2 = Vector2.ZERO

# Personality.
var aggression: float = 0.0
var bravery: float = 0.0
var perception: float = 0.0
var curiosity: float = 0.0
var mercy: float = 0.0

var flags = {
	"interested" : false,
	"fixated" : false,
	"fleeing" : false, 
	"knows_about_player" : false
	}


# Behavior flags.
var is_wandering = false
var has_destination = false
var is_interested = false
var is_fixated = false
var knows_about_player = false
var is_fleeing = false
var current_destination = Vector2.ZERO
var current_destination_height: int = 0


# Debugging flags.
export (bool) var noise_verbose = false
export (bool) var wander_verbose = false
export (bool) var targeting_verbose = false

# Utility.
var should_delay_ai = false
var ai_delay: float = 0.0
var second_timer: int = 0
var walk_noise_timer: int = 0
var no_progress_counter: int = 0
var last_noise_local_intensity: float = 0
var last_noise_position = Vector2.ZERO


func set_wander_destination(minimum: int, maximum: int):
	is_interested = false
	sprite.self_modulate = Color("#ffffff")
	var distance = rand.get_random_int(minimum, maximum)
	current_destination = self.global_position
	current_destination.x = current_destination.x + lerp(-distance, distance, randf())
	current_destination.y = current_destination.y + lerp(-distance, distance, randf())
	current_destination = navigation_polygon.get_closest_point(current_destination)


func handle_player_exists():
#	if(is_instance_valid(player)) == false:
#		player = get_node("/root/Main/Player")
#		print("Grabbed new player instance.")
	var test = get_tree().get_nodes_in_group("player")
	for stuff in test:
		player = stuff
#	print("Fuzzy's code can now reference the player. Wandering.")
	knows_about_player = false
	has_destination = false
	ai_process()


func _ready() -> void:
#	speed = 0.5 * base_speed
#	self.flags
	noise_verbose = false
	should_draw_path_line = true
	self.visible = false
	rand = get_node("/root/Main/Randomness")
#	self.speed = 70
	navigation_polygon = get_node("/root/Main/Navigation2D2")
	if perception == 0:
		set_personality()
#	print("per", perception)
#	print("agg", aggression)
	GlobalSignals.connect("made_noise", self, "handle_noise_heard")
	GlobalSignals.connect("player_exists", self, "handle_player_exists")


func follow_destination_list() -> void:
#	print("trying to follow destination list")
#	print("destination list size is: ", destination_list.size())
	if destination_list.size() > 0:
		if self.global_position.distance_to(destination_list[0]) < 2:
			print("close to first destination")
			destination_list.remove(0)
		else:
#			if destination_list.size() > 0:
#			print("heading to ", destination_list[0])
#			print("fuzzy is at: ", self.global_position)
			var d = destination_list[0].distance_to(self.global_position)
			print("distance between fuzzy and next destination is ", d)
#			go_to_destination(destination_list[0])
#			current_destination = destination_list[0]
			current_destination = navigation_polygon.get_closest_point(destination_list[0])
	else:
#		needs_to_start_transition = false
		pass


func handle_noise_heard(intensity: int, position: Vector2, type, height: int):
	if type == "fuzzy":
		return
#	if knows_about_player == true:
#		has_destination = true
#		interact_with_player()
#		return

	

	# If the noise isn't made by a fuzzy.
	if not type == "fuzzy":
		if position != self.global_position:
	
			# Diminish noise intensity based on distance.
			var distance_from_noise = position.distance_to(self.global_position)
			var local_intensity = intensity - (distance_from_noise / 300)
		
			# Ignore negative noise. Fix this later.
			if local_intensity < 0:
				local_intensity = 0 
				
			var perception_correction = .01 * perception
			if noise_verbose == true:
				print("Distance from noise is: ", distance_from_noise)
				print("Fuzzy's perception is: ", perception)
				print("Perception correction is: ", perception_correction)
				print("Fuzzy hears a sound with local intensity of: ", local_intensity)
			var chance_of_hearing = (0.08 * local_intensity)
			if chance_of_hearing != 0:
				chance_of_hearing += perception_correction
			if noise_verbose == true:
				print("Chance of hearing is: ", chance_of_hearing)
#			print("Chance of hearing is: ", chance_of_hearing)
			var chance = rand.get_random_float(0.0, 1.0)
			if noise_verbose == true:
				print("Chance variable is: ", chance)
				
			# If Fuzzy hears a new noise.
			if chance < chance_of_hearing:
				
				if noise_verbose == true:
					print("Fuzzy heard something.")
				
				# If new noise is close to the last one, follow it because it's
				# likely from the same source.
#				if last_noise_position.distance_to(position) <= 200:
#					current_destination = position
#					self.is_interested = true
#					self.flags.interested = true
#					sprite.self_modulate = Color("f37d0b")
				
				# This check happens only if Fuzzy thinks the noise is not from
				# his previous target.
				elif check_interest() == true:
					current_destination_height = height
					if height != self.height_layer:
						needs_to_start_transition = true
						
					current_destination = position
#					destination_list.append(position)
					last_noise_position = position
					has_destination = true
#					current_destination = position
					is_interested = true
				else:
					sprite.self_modulate = Color("#ffffff")
					has_destination = false
					is_interested = false
					
			


#		if is_instance_valid(player) == true:
#			if chance < chance_of_hearing and position == player.global_position:
#				knows_about_player = true
#				has_destination = true
#				if noise_verbose == true:
#					print("Fuzzy heard the player! Approaching the player.")
##			go_to_destination(position)
#				interact_with_player()


func check_interest() -> bool:
	var interest_chance = curiosity * 0.1
	var interest_roll = rand.get_random_float(0, 1)
	
	if noise_verbose == true:
		print("Chance of interest is: ", interest_chance)
		print("Interest roll is: ", interest_roll)
	
	if interest_roll < interest_chance:
		if noise_verbose == true:
			print("Fuzzy is interested in a sound and will head to it.")
		return true
	
	else:
		if noise_verbose == true:
			print("Though fuzzy heard something, he isn't interested in it right now.")
#		self.is_interested = false
		return false


func arrived_at_destination():
	has_destination = false
	is_interested = false
	pass


func loiter(loiter_time_seconds: int):
	pass



#func interact_with_player():
##	if player != null:
#	go_to_destination(player.global_position)


func adjust_modulation():
	
	if self.is_wandering:
		sprite.self_modulate = Color("ffffff")
	
	if self.is_interested:
		sprite.self_modulate = Color("f37d0b")
	
	


func set_personality():
	aggression = rand.get_random_int(1, 3)
	bravery = rand.get_random_int(2, 4)
	perception = rand.get_random_int(6, 8)
	curiosity = rand.get_random_int(7, 9)
	mercy = rand.get_random_int(6, 8)


func ai_process():
#	if has_destination == false and knows_about_player == false:
#		set_wander_destination()
#		go_to_destination(current_destination)
#	elif has_destination == true and knows_about_player == false:
#		go_to_destination(current_destination)
#	elif knows_about_player == true:
#		interact_with_player()
	
	# This flag is used to ensure that the invader only executes certain code
	# related to moving up or down once when the need arises.
#	if current_destination_height != height_layer:
#		needs_to_transition = true
		
	if has_destination == false:
		set_wander_destination(40, 1000)
		has_destination = true
		go_to_destination()
	elif has_destination == true:
		go_to_destination()


func _physics_process(delta) -> void:
	self.z_index = 100
#	self.speed = 0.5 * self.base_speed
	coffee_table = get_node("/root/Main/Rooms/LivingRoom/CoffeeTable")
#	wait(1)
#	player = get_node("/root/Main/Player")
	var p = get_tree().get_nodes_in_group("player")
#		for stuff in test:
#			player = stuff
	player = p[0]
	
#	if is_in_transition == true:
#		self.z_index = 2
	
#	print("in physics per", perception)
#	print("in physics agg", aggression)
	path_line.visible = false
	physics_timer += 1
#	print("physics timer is: ", physics_timer)
	if physics_timer == 1:
		physics_timer = 0
#		print("In physics process, destination list is: ", destination_list)
		
		if navigation_controller == null:
			navigation_controller = get_node("/root/Main/Navigation2D2")
#		print("number of nav polygons: ", navigation_controller.get_polygon_count())
		if(is_instance_valid(player)) == false:
			player = get_node("/root/Main/Player")
		var test = get_tree().get_nodes_in_group("player")
		for stuff in test:
			player = stuff
			
		if ai_delay == 0:
			ai_process()
		else:
			if timer.time_left == 0:
#				print("Starting to delay AI process by ", ai_delay)
				timer.wait_time = ai_delay
				timer.one_shot = true
				timer.start()
				yield(timer, "timeout")
#				print("It's now ", ai_delay, " seconds after the timer started.")
				ai_delay = 0.0
				ai_process()
			
			
#		if timer.time_left == 0 and ai_delay > 0.0 and should_delay_ai == true:
#		if timer.time_left == 0 and ai_delay > 0.0:
#			print("Starting to delay AI process by ", ai_delay)
#			timer.wait_time = ai_delay
#			timer.one_shot = true
#			timer.start()
#		yield(timer, "timeout")
#		ai_delay = 0.0
#		ai_process()
#		print("It's now, ", ai_delay, " seconds after the timer started.")
		
		
#		if ai_delay > 0.0:
#			ai_delay = 0.0
			
			
#		else:
#			ai_process()
			
		
#		else:
##			print("Doing ai process.")
#			ai_process()
		
#		ai_process()
		
		
		
#		ai_process()
#		yield(get_tree().create_timer(2), "timeout")
			
#		determine_destination()
#		go_to_destination(player)


func set_visibility(new_visibility: bool):
	visible = new_visibility


#func determine_destination():
#	pass


func wait(time_in_seconds: float):
#	print("Trying to pause.")
#	yield(get_tree().create_timer(time_in_seconds),"timeout")
	# My code that doesn't work.

	if timer.time_left == 0:
		print("Trying to pause for ", time_in_seconds, " seconds.")
		timer.wait_time = time_in_seconds
		timer.one_shot = true
		timer.start()
#		print(timer.time_left)
		yield(timer, "timeout")
		print("This is printed after ", time_in_seconds, " seconds.")

#yield(get_tree().create_timer(5.5),"timeout")

#var t = Timer.new()
#t.set_wait_time(3)
#t.set_one_shot(true)
#self.add_child(t)
#t.start()
#yield(t, "timeout")

#func wait():
#	pass


func elevation_transition() -> void:
#	print("starting elevation transition")
	if destination_list.size() != 0:
		return
	
	if needs_to_start_transition == true:
#		print("needs to start stuff is firing")
		var walk_line 
		var stored_transition
		var stored_distance = 0.0
		var distance_to_rally_point = 0.0
		
		# Select the closest rally transition.
		for node in coffee_table.get_node("Transitions").get_children():
			distance_to_rally_point = node.get_child(0).global_position.distance_to(self.global_position)
			if stored_distance == 0.0:
				stored_distance = distance_to_rally_point
				stored_transition = node
			else:
				if distance_to_rally_point < stored_distance:
					stored_transition = node
#					print("current node is: ", node)
		walk_line = stored_transition
			
		var polygon = coffee_table.get_node("TransitionableArea").get_polygon()
		var temp_destination = coffee_table.to_local(current_destination)
		if Geometry.is_point_in_polygon(temp_destination, polygon) == true:
			print("Heading to rally point.")
#		current_destination = coffee_table.get_node("RallyPointLeft").global_position
			destination_list.resize(0)
#			destination_list.append(walk_line.get_child(0).global_position)
#			for point in walk_line.points:
#				print("Point in walk_line is: ", point)
#				print("Global point in walk_line is: ", to_global(point))
#				destination_list.append(to_global(point))
			destination_list.append(walk_line.get_node("1").global_position)
			destination_list.append(walk_line.get_node("2").global_position)
#				destination_list.append(point)
#			print("destination list is: ", destination_list)
			
			
	
#		var polygon = coffee_table.get_node("TransitionableArea").get_polygon()
#		var temp_destination = coffee_table.to_local(current_destination)
#		if Geometry.is_point_in_polygon(temp_destination, polygon) == true:
#			print("Heading to rally point.")
##		current_destination = coffee_table.get_node("RallyPointLeft").global_position
#			destination_list.resize(0)
#			destination_list.append(walk_line.get_child(0).global_position)
#			for point in walk_line.points:
#				print("Point in walk_line is: ", point)
#				print("Global point in walk_line is: ", to_global(point))
#				destination_list.append(to_global(point))
##				destination_list.append(point)
##			print("destination list is: ", destination_list)
		
			needs_to_start_transition = false
#			is_in_transition = true
	
	
#	var left_leg_area = coffee_table.get_node("LeftLegArea").get_polygon()
#	var temp_position = coffee_table.to_local(self.global_position)
#	if Geometry.is_point_in_polygon(temp_position, left_leg_area) == true:
#			is_in_transition = true
#	else:
#			is_in_transition = false
#
#	if is_in_transition == true:
#		speed = (0.5 * base_speed)
#		self.z_index = 100
#		self.collision_layer = 2
#		self.collision_mask = 2
#		self.visible = true
#	else:
#		speed = base_speed
#		self.z_index = 1
#		self.collision_layer = 1
#		self.collision_mask = 1
#		self.visible = true
#	if self.global_position.distance_to(walk_line.points[0]) > 5 and self.height_layer == 1:
#		current_destination = walk_line.points[0]
#		print("trying to walk up leg")
#
#	elif self.global_position.distance_to(walk_line.points[0]) > 5 and self.height_layer == 2:
#		current_destination = walk_line.points[1]
#
#	# Near lower end of path. Go to its other end.
#	elif self.global_position.distance_to(walk_line.points[0]) < 5 and self.height_layer == 1:
#		current_destination = walk_line.points[1]
#
#	# Near upper end of path. Go to its other end.
#	elif self.global_position.distance_to(walk_line.points[1]) < 5 and self.height_layer == 2:
#		current_destination = walk_line.points[0]
#	if self.global_position.distance_to(coffee_table.get_node("RallyPointLeft").global_position) < 5:
#		print("updating destination list")
#		destination_list.resize(0)
#		destination_list.append(walk_line.points[0])
#		destination_list.append(walk_line.points[1])
	
#	coffee_table.get_node("LeftLegLine").to_global


# Expects a point.
func go_to_destination() -> void:
	animation_player.play("undulate_down_up")
#	var polygon = coffee_table.get_node("TableTop").get_polygon()
#	var temp_destination = coffee_table.to_local(destination)
##	if Geometry.is_point_in_polygon(temp_destination, polygon) == true:
##		print("Heading to rally point.")
##		destination = coffee_table.get_node("RallyPoint").global_position
	
	
	elevation_transition()
	follow_destination_list()
	
	walk_noise_timer += 1
	if walk_noise_timer == 30:
		walk_noise_timer = 0
		GlobalSignals.emit_signal("made_noise", 2, self.global_position, "fuzzy", height_layer)
#	print("Going to %s." % destination)
#	print("Current position is: ", self.global_position)
	if navigation_controller == null:
		navigation_controller = get_node("/root/Main/Navigation2D2")
#	if player != null:
#		player = get_node("/root/Main/Player")
	
	# Get path.
	path = navigation_controller.get_simple_path(self.global_position, current_destination, true)
	set_path_line(path)
	
	if path.size() > 0:
		# Stop if near destination.
		if self.global_position.distance_to(current_destination) == 0:
			path_line.clear_points()
			path = []
			print("Near destination. Stopping.")
#			has_destination = false
			arrived_at_destination()
#			wait(3)
#			ai_delay = rand.get_random_float(0.2, 1.5)
		# Approach the next point.
		else:
			
			# Store position in order to see if Fuzzy is actually moving.
			last_position = self.global_position
			
#			value = lerp(value, 10, delta)
			var test = self.global_position.direction_to(path[1])
#			var test = lerp(self.global_position, path[1], .0001)
			move_and_slide(test * speed)
			if last_position.distance_to(self.global_position) < 1:
#				print(self.name, " IS NOT MOVING! TRYING TO FIX.")
				no_progress_counter += 1
				if no_progress_counter == 100:
					print("Resetting no progress counter, going back into AI loop.")
					no_progress_counter = 0
					destination_list.resize(0)
					has_destination = false


# Create and show pathing line.
# to_local(global_point) or get_local_mouse_position() are useful
func set_path_line(points: PoolVector2Array):
	if not should_draw_path_line:
		return
		
	path_line.clear_points()
	
	for point in points:
		path_line.add_point(to_local(point), 0)
	
	for point in destination_list:
		path_line.add_point(to_local(point), 0)
	path_line.visible = true


#func perception_sweep():
#	pass


#func rotate_toward(location: Vector2):
#	rotation = lerp_angle(rotation, global_position.direction_to(location).angle(), 0.1)


#func velocity_toward(location: Vector2) -> Vector2:
#	return global_position.direction_to(location) * speed


#func has_reached_position(location: Vector2) -> bool:
#	return global_position.distance_to(location) < 5


func handle_hit():
	health -= 20
	if health <= 0:
		die()


#func do_once_a_second():
#	if second_timer == 60:
#		second_timer = 0
#	pass


func die():
	emit_signal("died")
	queue_free()


func save():
	var save_dict = {
	"filename" : get_filename(),
	"parent" : get_parent().get_path(),
	"pos_x" : self.global_position.x, 
	"pos_y" : self.global_position.y,
	"current_health" : self.health,
	"speed": self.speed,
	"visibility": self.visible
	}
	
	return save_dict

