extends Node

#Arrays.
var removed_asteroids = []
var C1_breaks = []
var C2_breaks = []
var S1_breaks = []
var S2_breaks = []
var M1_breaks = []
var M2_breaks = []
var asteroid_queue = []
var break_queue = []

#Physics frequency timer.
var frequency_counter: int = 0
onready var updates_per_second: int = 1

#Asteroid texture variables.
var C1 = preload("res://asteroids/Chondrite/C1/C1whole.png")
var S1 = preload("res://asteroids/Stony/S1/S1whole.png")
var complete_path: String
var num_fragments: int = 0

#Asteroid spawning.
var asteroid_spawn_location = Vector2.ZERO
export var maximum_number_asteroids = 50
var num_asteroids_in_wave: int = 0
var time_till_spawn: int = 0
onready var spawn_timer = $Asteroid_Spawn_Timer
var break_spawn_offset = 50
var breaks_are_prepared: bool = true

#Current number of asteroids.
var current_number_asteroids: int = 0

#Maximum asteroid distance.
export var maximum_asteroid_distance = 50000

#Threading.
var counter = 0
var mutex
var break_thread_semaphore
var break_thread
var exit_thread = false

#Preloads for spawning scenes.
const BREAK = preload("res://Break.tscn")
const ASTEROID = preload("res://actors/Player/Asteroid.tscn")

#Stages.
var stage: int = 1
onready var stage_timer = $Stage_Timer

#Special asteroids.
const PACK_SIX = preload("res://Pack_Six.tscn")
const PACK_TWELVE = preload("res://Pack_Twelve.tscn")
var special_queue = []

#Other.
var rng = RandomNumberGenerator.new()


func _ready():
	GlobalSignals.connect("asteroid_died", self, "on_asteroid_died")
	
	rng.randomize()
	set_spawn_timer()
	
#	Thread stuff.
	mutex = Mutex.new()
	break_thread_semaphore = Semaphore.new()
	exit_thread = false
	break_thread = Thread.new()
	break_thread.start(self, "run_in_break_thread")
	
	prepare_breaks()

func run_in_break_thread():
	while true:
		break_thread_semaphore.wait() #Wait until posted.
		
		mutex.lock()
		var should_exit = exit_thread #Protect with mutex.
		mutex.unlock()
		
		if should_exit:
			break
		
		mutex.lock()
#		if breaks_are_prepared == false:
		manage_stages()
		prepare_breaks()
		mutex.unlock()
		
		mutex.lock()
		counter += 1
		mutex.unlock()


func activate_break_thread():
	break_thread_semaphore.post() # Make the thread process.


func get_counter():
	mutex.lock()
	var counter_value = counter
	mutex.unlock()
	return counter_value


func _exit_tree():
	mutex.lock()
	exit_thread = true
	mutex.unlock()
	
#	Open semaphore and let thread finish current task.
	break_thread_semaphore.post()
	break_thread.wait_to_finish()
	
	print("Counter is:                                          ", counter)


func manage_physics_frequency():
	frequency_counter += 1
	if frequency_counter % (120/updates_per_second) == 0:
#		GlobalSignals.emit_signal("update_minimap")
#		remove_extra_asteroids()
#		activate_break_thread()
		pass
#		print(C1_breaks)
#		print(C1_breaks.size())
	if frequency_counter % (60/updates_per_second) == 0:
		remove_extra_asteroids()
		
#		if break_thread.is_alive() == true:
		activate_break_thread()
	if frequency_counter == 60:
		frequency_counter = 1


func _physics_process(delta):
	manage_physics_frequency()
	update_current_num_asteroids()
	add_rocks_to_tree()


func update_current_num_asteroids():
	current_number_asteroids = 0
	for child in self.get_children():
		if child.is_in_group("asteroid"):
			current_number_asteroids += 1


func generate_number_in_wave():
	num_asteroids_in_wave = rng.randi_range(1, 16)


func spawn_asteroids():
#	print("Spawning ", num_asteroids_in_wave, " asteroids.")
	for each in num_asteroids_in_wave:
		var new_asteroid = get_usable_asteroid()
		new_asteroid.can_break = true
		new_asteroid.integrity = 100
#		new_asteroid.get_child(0).set_texture(C1)
		species_update(new_asteroid)
		asteroid_spawn_location.x = rng.randf_range(-1,1)
		asteroid_spawn_location.y = rng.randf_range(-1,1)
		asteroid_spawn_location = asteroid_spawn_location.normalized()
		asteroid_spawn_location = asteroid_spawn_location * rng.randi_range(15000, 20000)
		new_asteroid.position = asteroid_spawn_location
		new_asteroid.velocity.x = rng.randf_range(-1,1)
		new_asteroid.velocity.y = rng.randf_range(-1,1)
		new_asteroid.velocity = new_asteroid.velocity.normalized()
		new_asteroid.velocity = new_asteroid.velocity * rng.randf_range(1, 1000)
		new_asteroid.rotation_rate = rng.randf_range(-.2, .2)
#		if should_add == true:
#			add_child(new_asteroid)
		add_child(new_asteroid)
	set_spawn_timer()	


func set_spawn_timer():
	spawn_timer.wait_time = rng.randi_range(1, 5)
#	print("Time until next wave: ", spawn_timer.wait_time) 
	spawn_timer.start()


func on_asteroid_died(asteroid):
#	exit_thread = true
	print("A rock just died: ", asteroid.name)
	if asteroid.can_break == false:
#		print("This rock can't break. Destroying it.")
		removed_asteroids.append(asteroid)
		self.remove_child(asteroid)
		
	else:
#		print("This rock can break. Trying to break it now.")
		break_asteroid(asteroid)
		asteroid.integrity = 100
		removed_asteroids.append(asteroid)
#		print("The parent of the rock that's breaking is: ", asteroid.get_parent())
		remove_child(asteroid)


func remove_extra_asteroids():
	var zero_vec = Vector2.ZERO
	var inactive
	
	for child in self.get_children():
		if child.is_in_group("asteroid") and child.global_position.distance_to(zero_vec) > maximum_asteroid_distance:
			removed_asteroids.append(child)
			remove_child(child)
	
	inactive = removed_asteroids.size()
	var message = "t: " + str(current_number_asteroids + removed_asteroids.size()) + " a: " + str(current_number_asteroids) + " i: " + str(inactive)
	GlobalSignals.emit_signal("set_debug_display", message)


func break_asteroid(asteroid):
#	print("The rock that's breaking has a species of: ", asteroid.species)
	var new_break = get_usable_break(asteroid.species)
#	print("In break_asteroid, the break is: ", new_break)
#	print("It has these children: ", new_break.get_children())
	for child in new_break.get_children():
		if child.size == 3:
			child.integrity = 50
			child.position.x = asteroid.position.x + rng.randf_range(-break_spawn_offset, break_spawn_offset)
			child.position.y = asteroid.position.y + rng.randf_range(-break_spawn_offset, break_spawn_offset)
			child.velocity.x = asteroid.velocity.x + rng.randf_range(-100, 100)
			child.velocity.y = asteroid.velocity.y + rng.randf_range(-100, 100)
			child.rotation_rate = asteroid.rotation_rate + rng.randf_range(-.05, .05)
				
		elif child.size == 2:
			child.integrity = 40
			child.position.x = asteroid.position.x + rng.randf_range(-break_spawn_offset, break_spawn_offset)
			child.position.y = asteroid.position.y + rng.randf_range(-break_spawn_offset, break_spawn_offset)
			child.velocity.x = asteroid.velocity.x + rng.randf_range(-200, 200)
			child.velocity.y = asteroid.velocity.y + rng.randf_range(-200, 200)
			child.rotation_rate = asteroid.rotation_rate + rng.randf_range(-.1, .1)
			
		elif child.size == 1:
			child.integrity = 20
			child.position.x = asteroid.position.x + rng.randf_range(-break_spawn_offset, break_spawn_offset)
			child.position.y = asteroid.position.y + rng.randf_range(-break_spawn_offset, break_spawn_offset)
			child.velocity.x = asteroid.velocity.x + rng.randf_range(-300, 300)
			child.velocity.y = asteroid.velocity.y + rng.randf_range(-300, 300)
			child.rotation_rate = asteroid.rotation_rate + rng.randf_range(-.2, .2)
#		print("in break_asteroid, this rock has a rotation_rate of: ", child.rotation_rate)
#		print("in break_asteroid, this rock has a size of: ", child.size)
		new_break.remove_child(child)
		asteroid_queue.append(child)
#		self.add_child(child)
	new_break.is_ready_to_break = false
	if break_queue.size() > 0:
#		print("Breaks in queue: ", break_queue)
		pass
	if asteroid_queue.size() > 0:
#		print("Asteroids in queue: ", asteroid_queue)
		pass
	
#
#	var is_preloaded_break = false
#	num_fragments = 0
#	if asteroid.can_break == false:
#		return
#	var path
#
#	var files = return_files_in_directory(path)
#	for file in files:
##		print(path)
##		print(file)
#		complete_path = path + file
#		if not "import" in str(file):
#			num_fragments += 1
##			var fragment = ASTEROID.instance()
#			var fragment
##			if spare_breaks.size() > 0:
##				fragment = spare_breaks[0].get_child(0)
##				is_preloaded_break = true
##			else:
##				fragment = get_usable_asteroid()
#			if !fragment:
#				print("              Can't find a fragment for some reason!")
#				break
#			fragment.visible = true
#			fragment.can_break = false
#			fragment.is_active = true
#			fragment.get_child(0).set_texture(load(complete_path))
#
#			if "large" in str(file):
#				fragment.integrity = 50
#				fragment.position.x = asteroid.position.x + rng.randf_range(-2, 2)
#				fragment.position.y = asteroid.position.y + rng.randf_range(-2, 2)
#				fragment.velocity.x = asteroid.velocity.x + rng.randf_range(-100, 100)
#				fragment.velocity.y = asteroid.velocity.y + rng.randf_range(-100, 100)
#				fragment.rotation_rate = asteroid.rotation_rate + rng.randf_range(-.05, .05)
#
#			elif "medium" in str(file):
#				fragment.integrity = 40
#				fragment.position.x = asteroid.position.x + rng.randf_range(-2, 2)
#				fragment.position.y = asteroid.position.y + rng.randf_range(-2, 2)
#				fragment.velocity.x = asteroid.velocity.x + rng.randf_range(-200, 200)
#				fragment.velocity.y = asteroid.velocity.y + rng.randf_range(-200, 200)
#				fragment.rotation_rate = asteroid.rotation_rate + rng.randf_range(-.1, .1)
#
#			elif "small" in str(file):
#				fragment.integrity = 20
#				fragment.position.x = asteroid.position.x + rng.randf_range(-2, 2)
#				fragment.position.y = asteroid.position.y + rng.randf_range(-2, 2)
#				fragment.velocity.x = asteroid.velocity.x + rng.randf_range(-300, 300)
#				fragment.velocity.y = asteroid.velocity.y + rng.randf_range(-300, 300)
#				fragment.rotation_rate = asteroid.rotation_rate + rng.randf_range(-.2, .2)
#	#		fragment.get_child(1).disabled = true
##			if should_add == true:
##			if is_preloaded_break == true:
##				spare_breaks[0].remove_child(fragment)
#			self.add_child(fragment)
##			if is_preloaded_break == true:
##				print("                                Starting block to delete empty break.")
##				print("                                ", spare_breaks[0].get_child_count())
##				if spare_breaks[0].get_child_count() == 0:
##					print("                                Deleting empty break.")
##					spare_breaks.pop_front()
##	print("Number of fragments out of that asteroid: ", num_fragments)


#Return usable asteroid from the array of inactives or a new one.
func get_usable_asteroid():
	if removed_asteroids.size() > 0:
		var asteroid_to_return = removed_asteroids[0]
		removed_asteroids.remove(0)
		species_update(asteroid_to_return)
		return asteroid_to_return
	else:
		var ast = ASTEROID.instance()
#		ast.update_physics_shape()

#		Set layers by taking to the power of the desired layer minus one. Add
#		them to set more than one layer.
#		ast.collision_layer = pow(2, 1-1)
		ast.collision_layer = pow(2, (rng.randi_range(1, 3))-1) 
		ast.collision_mask = pow(2, (rng.randi_range(1, 3))-1) 
		species_update(ast)
		return ast


func get_usable_break(species):
	var spare_breaks
	var path
#	print("In get_usable_break(), the asteroid species is: ", asteroid.species)
	if species == "C11":
		path = "res://asteroids/Chondrite/C1/Break1/"
#		print("Selecting C1 breaks.")
		spare_breaks = C1_breaks
	elif species == "C21":
		path = "res://asteroids/Chondrite/C2/Break1/"
		spare_breaks = C2_breaks
	elif species == "S11":
		path = "res://asteroids/Silicate/S1/Break1/"
		spare_breaks = S1_breaks
	elif species == "S21":
		path = "res://asteroids/Silicate/S2/Break1/"
		spare_breaks = S2_breaks
	elif species == "M11":
#		path = "res://asteroids/Chondrite/C1/Break1/"
		spare_breaks = M1_breaks
	elif species == "M21":
#		path = "res://asteroids/Chondrite/C1/Break1/"
		spare_breaks = M2_breaks
#	var files = return_files_in_directory(path)
	var files
#	var path
	
	for new_break in spare_breaks:
		if new_break.is_ready_to_break:
			
			for child in new_break.get_children():
				if child.species == null:
					print("               Found a null species asteroid.")
				child.is_fragment = true
					
#			print("Returning a usable break of type: ", new_break.species)
			return new_break
			

	print("Didn't find a break. Making a new one.")
	var new_break = BREAK.instance()
	new_break.species = species
	fill_break_node(new_break)
	
	for ast in new_break.get_children():
		ast.collision_layer = pow(2, (rng.randi_range(1, 3))-1) 
		ast.collision_mask = pow(2, (rng.randi_range(1, 3))-1)
		ast.is_fragment = true
	
	new_break.is_ready_to_break = true
	return new_break


func return_files_in_directory(path):
	var files = []
	var dir = Directory.new()
	
	dir.open(path)
	dir.list_dir_begin()

	while true:
		var file = dir.get_next()
		if file == "":
			break
		elif not file.begins_with("."):
			files.append(file)

	dir.list_dir_end()

	return files


#Runs in separate thread. Maintains the arrays of breaks.
func prepare_breaks():
	
	var break_array = []
	break_array.append(C1_breaks)
	break_array.append(C2_breaks)
	break_array.append(S1_breaks)
	break_array.append(S2_breaks)
	break_array.append(M1_breaks)
	break_array.append(M2_breaks)
	
	var break_node 
	var path 
#	var fragment
	var files
#	print("break_array's size is: ", break_array.size())
	for arr in break_array:
		while arr.size() < 10:
			break_node = BREAK.instance()
#			fill_break_node(break_node)
#			break_node = get_usable_break("C11")
			
			if arr == break_array[0]:
				break_node.species = "C11" #Store species for adding to asteroids.
				fill_break_node(break_node)
				arr.append(break_node)
			elif arr == break_array[1]:
				break_node.species = "C21"
				fill_break_node(break_node)
				arr.append(break_node)
			elif arr == break_array[2]:
				break_node.species = "S11"
				fill_break_node(break_node)
				arr.append(break_node)
#				print(break_node.species)
#				for break_thing in arr:
#					print(break_thing.species)
			elif arr == break_array[3]:
				break_node.species = "S21"
				fill_break_node(break_node)
				arr.append(break_node)
			elif arr == break_array[4]:
				break_node.species = "M11"
				fill_break_node(break_node)
				arr.append(break_node)
			elif arr == break_array[5]:
				break_node.species = "M21"
				fill_break_node(break_node)
				arr.append(break_node)
					
			break_node.is_ready_to_break = true
#			files = return_files_in_directory(path) #Grab appropriate dir.
		for node in arr:
			fill_break_node(node)
#			fill_break_node(break_node)
#			arr.append(break_node)
			
#		for other_break_node in arr:
#			if other_break_node.get_child_count() < 5 or other_break_node.is_ready_to_break == false:
#				fill_break_node(other_break_node)
				
#	print("C1: ", C1_breaks.size())
#	for break_thing in C1_breaks:
#		print(break_thing.species)
#	for break_thing in C1_breaks:
#		print(break_thing.species)
#	print("C2: ", C2_breaks.size())
#	print("S1: ", S1_breaks.size())
#	print("S2: ", S2_breaks.size())
#	print("M1: ", M1_breaks.size())
#	print("M2: ", M2_breaks.size())
	
	breaks_are_prepared = false


func fill_break_node(break_node):
#	print("fill_break_node is running.")
	var files
	var path

	if break_node.species == "C11":
		path = "res://asteroids/Chondrite/C1/Break1/"
	#		spare_breaks = C1_breaks
	elif break_node.species == "C21":
		path = "res://asteroids/Chondrite/C1/Break1/"
#		spare_breaks = C2_breaks
	elif break_node.species == "S11":
		path = "res://asteroids/Stony/S1/Break1/"
#		spare_breaks = S1_breaks
	elif break_node.species == "S21":
		path = "res://asteroids/Stony/S1/Break1/"
#		spare_breaks = S2_breaks
	elif break_node.species == "M11":
		path = "res://asteroids/Chondrite/C1/Break1/"
#		spare_breaks = M1_breaks
	elif break_node.species == "M21":
		path = "res://asteroids/Chondrite/C1/Break1/"
#		spare_breaks = M2_breaks
	else:
		path = "res://asteroids/Chondrite/C1/Break1/"

	files = return_files_in_directory(path)
	
	var iteration_count = ((files.size() / 2) - 1)

#	If break doesn't have enough children, fill it.
	if break_node.get_child_count() < (files.size() / 2):
#		print("Adding asteroids to a break.")
		for i in (iteration_count + 1) - break_node.get_child_count():
			var rock = get_usable_asteroid()
			rock.species = break_node.species
			rock.is_fragment = true
#			species_update(rock)
			break_node.add_child(rock)
#		break_node.is_ready_to_break = true
	
	
	if break_node.get_child_count() != 0 and break_node.is_ready_to_break == false:
#		print("Break node child count is not zero. It is: ", break_node.get_child_count())

		var counter = 0
		for file in files:
			complete_path = path + file
			if counter <= iteration_count:
				if counter == iteration_count: #Ignore import files and prevent off-by-one.
					break_node.is_ready_to_break = true
				if not "import" in str(file): #Exclude import files.
					if !break_node.get_child(counter):
						var rock = get_usable_asteroid()
						rock.species = break_node.species
						break_node.add_child(rock)
						
					if "large" in str(file):
						break_node.get_child(counter).size = 3
					elif "medium" in str(file):
						break_node.get_child(counter).size = 2
					elif "small" in str(file):
#						print("Files size is: ", files.size())
#						print("Species of this break is: ", break_node.species)
#						print("The value of counter is: ", counter)
						break_node.get_child(counter).size = 1
	#					fragment.species = break_node.species
	#					fragment = get_usable_asteroid() 
					break_node.get_child(counter).visible = true
	#						print("Break_node is: ", break_node)
					break_node.get_child(counter).can_break = false
	#						print("                            ", complete_path)
#					print("In fill_break_node(), type of this rock is:", break_node.get_child(counter).species)
#					print("In fill_break_node(), the path for the texture is: ", complete_path)
					break_node.get_child(counter).get_child(0).set_texture(load(complete_path))
#					break_node.get_child(counter).update_physics_shape()
#					break_node.get_child(counter).change_sprite_texture(complete_path)
					break_node.get_child(counter).species = break_node.species
					counter += 1

	
	for child in break_node.get_children():
		child.species = break_node.species
		
	break_node.is_ready_to_break = true


func species_update(object):
	if object.species == "C11" or object.species == "C12":
		object.get_child(0).texture = C1
	elif object.species == "S11" or object.species == "S12":
		object.get_child(0).texture = S1
	else: 
		object.get_child(0).texture = C1


#Handles moving objects from break_queue[] and asteroid_queue[] into the asteroid
#manager (and thus into the tree).
#break_queue[] and asteroid_queue[] are arrays that hold breaks and asteroids that
#will be deposited into the tree slowly rather than dumped at once.
func add_rocks_to_tree():
	if break_queue.size() > 0:
		if break_queue.get_children > 0:
			self.add_child(break_queue[0].get_child(0))
			break_queue[0].remove_child(0)
		else:
			add_break_to_correct_array(break_queue[0])
			break_queue.remove[0]
	
	elif asteroid_queue.size() > 0:
		self.add_child(asteroid_queue[0])
		asteroid_queue.remove(0)


#Puts a break in the correct array.
func add_break_to_correct_array(break_node):
	if break_node.species == "C11" or break_node.species == "C12":
		C1_breaks.append(break_node)
	elif break_node.species == "C21" or break_node.species == "C22":
		C2_breaks.append(break_node)
	elif break_node.species == "S11" or break_node.species == "S12":
		S1_breaks.append(break_node)
	elif break_node.species == "S21" or break_node.species == "S22":
		S2_breaks.append(break_node)
	elif break_node.species == "M11" or break_node.species == "M12":
		M1_breaks.append(break_node)
	elif break_node.species == "M21" or break_node.species == "M22":
		M2_breaks.append(break_node)


func _on_Asteroid_Spawn_Timer_timeout():
	if current_number_asteroids <= maximum_number_asteroids:
		generate_number_in_wave()
		spawn_asteroids()
	elif maximum_number_asteroids - current_number_asteroids > 0:
		num_asteroids_in_wave = maximum_number_asteroids - current_number_asteroids
		spawn_asteroids()
#	elif current_number_asteroids >= maximum_number_asteroids:
#		pass


#Stages beyond 1 incorporate special "boss" asteroids from the previous stage.
#Each stage is a relatively quiet period followed by a boss. Each stage's quiet 
#period can spawn all previous bosses, with a slowly increasing chance of spawn, 
#as well as more standard asteroids. Some bosses threaten Earth; some threaten
#the player.

#Stage 1: 20 standard asteroids (1 minute), ended by a fast steroid.
#Stage 2: 30 standard asteroids (1 minute 30), ended by a large converging group (a pack).
#Stage 3: 40 standard asteroids (2 minutes), ended by a homing asteroid.
#Stage 2: 50 standard asteroids (2 minutes 30), ended by a


func manage_stages():
	if stage == 1:
		if stage_timer.get_time_left() == 0.0:
			stage_timer.wait_time = 10
			stage_timer.start()
			print("Started stage 1 timer.")
	
#		stage_timer.wait_time = 10
#		stage_timer.start()
	if stage == 2:
		pass


func spawn_pack_five(position: Vector2):
	var pack_six = PACK_SIX.instance()
	self.add_child(pack_six)
	pack_six.global_position = position
	for child in pack_six.get_children():
		var roid = get_usable_asteroid()
		roid.global_position = child.global_position
		asteroid_queue.append(roid)
	pack_six.queue_free()


func spawn_pack_twelve(position: Vector2):
	var pack_twelve = PACK_TWELVE.instance()
	self.add_child(pack_twelve)
	pack_twelve.global_position = position
	for child in pack_twelve.get_children():
		var roid = get_usable_asteroid()
		roid.global_position = child.global_position
		asteroid_queue.append(roid)
	pack_twelve.queue_free()


func _on_Stage_Timer_timeout():
	pass
	print("Stage timer timed out.")
	if stage == 1:
#		spawn_pack_five(Vector2(-3000, 0))
#		spawn_pack_twelve(Vector2(-4000, 0))
		stage = 2
		return
	
	elif stage == 2:
		print("In stage 2.")
		
