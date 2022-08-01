extends KinematicBody2D
class_name Asteroid

#Physics frequency timer.
var frequency_counter: int = 0
onready var updates_per_second: int = 1

#Basic attributes.
var rotation_rate: float = 0.0
var integrity: int = 100
var velocity = Vector2.ZERO
export var is_boss = false

#Self references.
onready var sprite = $Sprite
onready var physics_shape = $Physics_Shape
onready var projectile_shape = $Projectile_Shape
onready var no_physics_timer = $No_Physics_Timer

#Attributes for breaks.
var type = "asteroid"
var species = "C11"
var size: int = 4
var can_break = true
export var is_active: bool = true
var is_fragment = false

var stored_texture_path = ""

var rng = RandomNumberGenerator.new()


func _ready():
	physics_shape.polygon = projectile_shape.polygon
	physics_shape.disabled = true
	GlobalSignals.connect("player_hit_asteroid", self, "on_player_hit_asteroid")
	rng.randomize()
	self.integrity = rng.randi_range(100, 300)
	set_no_physics_timer()
	assign_species()

#C makes up 75% of all asteroids, S 17%, M 8%.
func assign_species():
	var type_float = rng.randf_range(0, 1)
	if type_float >= 0.0 and type_float <= 0.75: #If it's a C.
		species = "C11"
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
		species = "M11"
	else: species = "C11"


func on_player_hit_asteroid(name, damage):
	if self.name == name:
		self.integrity -= damage


func manage_physics_frequency():
	frequency_counter += 1
#	if frequency_counter % (60/updates_per_second) == 0:
#		pass
	if frequency_counter == 60:
		frequency_counter = 1


func _physics_process(delta):
	if !sprite.texture:
		print(self.name, " may have something wrong with it.")
	manage_physics_frequency()
#	GlobalSignals.emit_signal("minimap_ping", self.position, self.rotation, sprite.texture)
	if self.integrity <= 0:
#		print("An asteroid is trying to break apart.")
		GlobalSignals.emit_signal("asteroid_died", self)
#		self.queue_free()
	if self.is_inside_tree() == true:
		move_and_slide(velocity)
		rotation += rotation_rate

func _on_Area2D_area_entered():
	print("Body entered.")


func _on_Area2D_body_entered(body):
	print(body.name, " entered.")


func delay_physics(time: float):
	physics_shape.disabled = true


func set_no_physics_timer():
	if no_physics_timer: 
		no_physics_timer.wait_time = 2
		no_physics_timer.start()


func _on_No_Physics_Timer_timeout():
#	print("No physics timer activated.")
	if self.is_active == true:
		physics_shape.disabled = false
		projectile_shape.disabled = false
	no_physics_timer.stop()
	


func activate():
	self.visible = true
	physics_shape.disabled = false
	projectile_shape.disabled = false
	self.pause_mode = false




func update_physics_shape():
	var image = Image.new()
#	print(path)
	var texture = $Sprite.texture.get_data()
	image = texture

	var bitmap = BitMap.new()
	bitmap.create_from_image_alpha(image)
#	print("Sprite's transform x is times texture width: ", $Sprite.scale.x * texture.get_width())
	var vec = Vector2(texture.get_height(), texture.get_width())
#	var vec = Vector2(texture.get_height(), texture.get_width())
	
#	print("The bitmap size is: ", bitmap.get_size())
	var polygons = bitmap.opaque_to_polygons(Rect2(Vector2(0, 0), vec ))
#	print("Polygons is: ", polygons)
#	print("This is the polygon count: ", polygons.size())
	for poly in polygons:
#		var collider = CollisionPolygon2D.new()
#		collider.polygon = poly
#		projectile_shape.polygon = poly
#		if physics_shape:
#			physics_shape.polygon = poly
#		else:
##			pass
#			print("There was an issue with the physics shape.")
		var stored_magnitude
		$Physics_Shape.polygon = poly
		var c = 0
		for point in $Physics_Shape.polygon:
			c = c+1
#			print("Before change the point is: ", point)
#			stored_magnitude = point.length()
#			point = point.normalized()
			point.x = point.x * $Sprite.scale.x
			point.y = point.y * $Sprite.scale.y
#			point = (point * $Physics_Shape.scale.x)
#			print("After change the point is: ", point)
#			print($Physics_Shape.polygon)
		print("Changed this number of points: ", c)

func get_image_path():
	if self.species == "C11":
		return 


func _on_Asteroid_tree_entered():
	pass
#	if is_fragment:
#		set_no_physics_timer()
