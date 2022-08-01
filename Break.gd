extends Node2D

const ASTEROID = preload("res://actors/Player/Asteroid.tscn")
var species
var is_ready_to_break = false
var rng = RandomNumberGenerator.new()

func _ready():
	rng.randomize()
	assign_species()
	for child in self.get_children():
		child.species = self.species


#C makes up 75% of all asteroids, S 17%, M 8%.
func assign_species():
	var type_float = rng.randf_range(0, 1)
	if type_float >= 0.0 and type_float <= 0.75: #If it's a C.
		return "C11"
#		var base_int = rng.randi_range(1, 2) #Choose between the base models available.
#		var break_int = rng.randi_range(1, 2) #Choose between the breaks available.
#		if base_int == 1:
#			if break_int == 1:
#				species = "C11"
#			elif break_int == 2:
#				species = "C12"
#		elif
	elif type_float > 0.75 and type_float <= 0.92:
		species = "S11"
	elif type_float > 0.92 and type_float <= 1.0:
		species =  "M11"


func make_children():
	if species == "C11":
		for i in 5:
			self.add_child(ASTEROID.instance())
	elif species == "C12":
		for i in 5:
			self.add_child(ASTEROID.instance())
	elif species == "S11":
		for i in 8:
			self.add_child(ASTEROID.instance())
	elif species == "S12":
		for i in 5:
			self.add_child(ASTEROID.instance())
	elif species == "M11":
		for i in 5:
			self.add_child(ASTEROID.instance())
	elif species == "M12":
		for i in 5:
			self.add_child(ASTEROID.instance())
