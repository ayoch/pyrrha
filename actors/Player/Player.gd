extends KinematicBody2D
class_name Player

onready var collision_placeholder = $Collision_Placeholder
var type = "player"
onready var heard_something = preload("res://HearSomething.tscn")
#signal player_health_changed(new_health)
#signal player_energy_changed(new_energy)

#signal made_noise()
signal died

var frequency_counter = 0

#For new movement system.
var player_rotation
export (int) var base_acceleration_forward = 10
export (int) var base_acceleration_back = 2
export (int) var base_acceleration_left = 3
export (int) var base_acceleration_right = 3
var current_velocity
var movement_direction := Vector2.ZERO
var temp_movement_direction = Vector2.ZERO

#New variables.
onready var left_ray = $Left_Laser_Ray_Cast
onready var right_ray = $Right_Laser_Ray_Cast

#Old variables.
export (int) var speed = 350
export (int) var base_speed = 350
export (int) var base_energy_regen_rate = 1
export (int) var energy_loss_rate = 2
export (int) var height_layer = 2

#Old variables.
#var height_layer: int = 2
var health: int = 100
var max_health: int = 100
var player_direction_degrees: int = 0
var last_animation = "idle_left"
var energy:int = 100
var max_energy:int = 100
var noise_timer: int = 0

onready var player_hearing 
onready var player_camera 
#onready var animation_player = $Sprite/AnimationPlayer
#onready var light = $SightZoneLight
onready var laser_eyes_left: Line2D = $LaserEyesLeft
onready var laser_eyes_right: Line2D = $LaserEyesRight
onready var prograde_indicator = $Prograde_Indicator
onready var retrograde_indicator = $Retrograde_Indicator
onready var thrust_indicator = $Thrust_Indicator
onready var planet_indicator = $Planet_Indicator
var earth_location: Vector2 

var nav_is_pressed = false

func _ready() -> void:
	earth_location.x = 0
	earth_location.y = 1


#	player_hearing = get_node("/root/Main/PlayerHearing")
#	weapon_manager.initialize(team.team)
	player_camera = get_node("/root/Main/PlayerCamera")
	laser_eyes_left.visible = false
	laser_eyes_right.visible = false
	
	GlobalSignals.emit_signal("active_room", "LivingRoom")
	
	GlobalSignals.connect("made_noise", self, "handle_noise_heard")
	GlobalSignals.emit_signal("player_exists")


func handle_noise_heard(intensity: int, position: Vector2, type, height: int):
#	pass
	if position != self.global_position:
		var hear_something = heard_something.instance()
#		hear_something.set_visibility(false)
		hear_something.global_position = position
		player_hearing.add_child(hear_something)


func _physics_process(delta: float) -> void:
	frequency_counter += 1
	if frequency_counter == 30:
		GlobalSignals.emit_signal("broadcast_player_position", self.global_position)
	if frequency_counter == 60:
		frequency_counter = 0
	nav_is_pressed = false #For toggling nav indicators.
#	Set retrograde and prograde indicators to their correct positions
	var mouse_angle = get_angle_to(get_global_mouse_position())
#	print(mouse_angle)
	look_at(get_global_mouse_position())
	energy = 100
#	set_camera_transform()
	
#	fog_of_war.visible = true
	player_camera.global_position.x = global_position.x
	player_camera.global_position.y = global_position.y
	laser_eyes_left.clear_points()
	laser_eyes_right.clear_points()
#	update_energy()
#	print("Player energy is: ", self.energy)
#	GlobalSignals.emit_signal("player_energy_changed", self.energy)
#	if energy == 100:
#		emit_signal("player_energy_changed", energy)
#		print("Player energy is at 100.")
#	emit_signal("player_energy_changed", energy)
#	print("in physics energy is: ", energy)
	
#	var movement_direction := Vector2.ZERO
#	rotate_head(get_global_mouse_position())
#	light.look_at(get_global_mouse_position())
#	weapon_manager.look_at(get_global_mouse_position())
	
	if Input.is_action_pressed("shoot"):
		laser_eyes()
	
#	if Input.is_action_pressed("speed") and no_movement_input() == false:
#		speed = base_speed
#		energy = clamp(energy -2, 0, max_energy)
##		update_energy()
##		GlobalSignals.emit_signal("player_energy_changed", energy)
#		make_noise(8)
#		if energy > 0:
#			speed = base_speed * 2
#	else:
#		speed = 350
	player_rotation = self.global_rotation
	if Input.is_action_pressed("forward"):
		movement_direction += Vector2.RIGHT.rotated(player_rotation) * base_acceleration_forward
		
	if Input.is_action_pressed("back"):
		temp_movement_direction = Vector2.ZERO
		temp_movement_direction += Vector2.RIGHT.rotated(player_rotation) * base_acceleration_back
		var x = temp_movement_direction.x
		var y = temp_movement_direction.y
		temp_movement_direction.x = x * -1
		temp_movement_direction.y = y * -1
		movement_direction += temp_movement_direction
		
	if Input.is_action_pressed("left"):
		temp_movement_direction = Vector2.ZERO
		temp_movement_direction += Vector2.RIGHT.rotated(player_rotation) * base_acceleration_left
		var x = temp_movement_direction.x
		var y = temp_movement_direction.y
		temp_movement_direction.x = y
		temp_movement_direction.y = -1 * x
		movement_direction += temp_movement_direction
		
	if Input.is_action_pressed("right"):
		temp_movement_direction = Vector2.ZERO
		temp_movement_direction += Vector2.RIGHT.rotated(player_rotation) * base_acceleration_right
		var x = temp_movement_direction.x
		var y = temp_movement_direction.y
		temp_movement_direction.x = y * -1
		temp_movement_direction.y = x
		movement_direction += temp_movement_direction
	
	if Input.is_action_pressed("back") and Input.is_action_pressed("shift"):
		temp_movement_direction = Vector2.ZERO
		
	if Input.is_action_pressed("zoom in"):
#		print("trying to change camera zoom out")
		player_camera.zoom.x += .01
		player_camera.zoom.y += .01
	if Input.is_action_pressed("zoom out"):
#		print("trying to change camera zoom in")
		player_camera.zoom.x = clamp(player_camera.zoom.x -.01, 0.1, 100)
		player_camera.zoom.y = clamp(player_camera.zoom.y -.01, 0.1, 100)
#		if (player_camera.zoom.x -.1) != 0:
#			player_camera.zoom.x -= .1
#			player_camera.zoom.y -= .1

	if Input.is_action_just_pressed("Nav"):
		print("Nav was pressed.")
		
		if planet_indicator.visible == true and thrust_indicator.visible == true:
				print("Turning both navs off.")
				planet_indicator.visible = false
				thrust_indicator.visible = false
		elif planet_indicator.visible == false and thrust_indicator.visible == false:
			print("Turning on thrust indicator.")
			thrust_indicator.visible = true
		elif thrust_indicator.visible == true and planet_indicator.visible == false:
			print("Turninf off thrust indicator and turning on planet indicator.")
			thrust_indicator.visible = false
			planet_indicator.visible = true
		elif planet_indicator.visible == true and thrust_indicator.visible == false:
			print("Turning on thrust indicator because it's off and planet indicator is on.")
			thrust_indicator.visible = true	
		
	
	if (movement_direction.y != 0.0) and (movement_direction.x != 0.0):
		thrust_indicator.rotation = movement_direction.angle() - self.rotation
		thrust_indicator.rotation += PI/2
		var p = self.position.angle_to(earth_location)
		p += self.rotation
		p += PI/2
	
		planet_indicator.position.x = self.position.x + cos(p) * 160
		planet_indicator.position.y = self.position.y + sin(p) * 160
#		planet_indicator.position.x -= self.position.x
#		planet_indicator.position.y -= self.position.y
		planet_indicator.position -= self.position
		planet_indicator.position.y = planet_indicator.position.y * -1
	else:
		prograde_indicator.rotation = 0
		retrograde_indicator.rotation = 0
	planet_indicator.rotation -= self.rotation
#	X := originX + cos(angle)*radius;
#	Y := originY + sin(angle)*radius;

	move_and_slide(movement_direction)
	GlobalSignals.emit_signal("update_speed", movement_direction.length())


func set_directional_animations(direction):
#	print("Player direction index is in radians: ", player_direction_degrees)
	player_direction_degrees = rad2deg(direction.angle())
	
	if player_direction_degrees < 0:
		player_direction_degrees += 360
		
#	if player_direction_degrees == 179:
#		player_direction_degrees = 180
#		print(player_direction_degrees)
		
#	print("Player direction index is: ", player_direction_degrees)
#	print("last animation was: ", last_animation)
#	if player_direction_degrees == 0 and no_movement_input() == true:
#	if no_movement_input() == true:
##		animation_player.play(last_animation)
##		print("Player is not moving.")
#		pass
#	else:
#		make_noise(1)
##		print("Player is moving.")
#		if player_direction_degrees >= 0 and player_direction_degrees <=45:
##			print("player angle in degrees is: ", player_direction_degrees)
##			animation_player.play("idle_right")
##			last_animation = "idle_right"
#
#			laser_eyes_left.position.x = 17.5
#			laser_eyes_left.position.y = -8
#
#			laser_eyes_right.position.x = 17.5
#			laser_eyes_right.position.y = -6
#
#		if player_direction_degrees / 45 == 1:
##			print("player angle in degrees is: ", player_direction_degrees)
##			animation_player.play("idle_right_down")
##			last_animation = "idle_right_down"
#
#			laser_eyes_left.position.x = 12.5
#			laser_eyes_left.position.y = -1
#
#			laser_eyes_right.position.x = 9.85
#			laser_eyes_right.position.y = -0.09
#
#		if player_direction_degrees / 45 == 2:
##			print("player angle in degrees is: ", player_direction_degrees)
##			animation_player.play("idle_down")
##			last_animation = "idle_down"
#
#			laser_eyes_left.position.x = 1
#			laser_eyes_left.position.y = 7.5
#
#			laser_eyes_right.position.x = -2.1
#			laser_eyes_right.position.y = 7.5
#
#		if player_direction_degrees / 45 == 3:
##			print("player angle in degrees is: ", player_direction_degrees)
##			animation_player.play("idle_left_down")
##			last_animation = "idle_left_down"
#
#			laser_eyes_left.position.x = -10.7
#			laser_eyes_left.position.y = -1
#
#			laser_eyes_right.position.x = -13.25
#			laser_eyes_right.position.y = -1.5
#
#		if player_direction_degrees / 45 == 4:
##			print("player angle in degrees is: ", player_direction_degrees)
##			animation_player.play("idle_left")
##			last_animation = "idle_left"
#
#			laser_eyes_left.position.x = -17
#			laser_eyes_left.position.y = -6
#
#			laser_eyes_right.position.x = -17
#			laser_eyes_right.position.y = -8
#
#		if player_direction_degrees / 45 == 5:
##			print("player angle in degrees is: ", player_direction_degrees)
##			animation_player.play("idle_left_up")
##			last_animation = "idle_left_up"
#
#			laser_eyes_left.position.x = -12
#			laser_eyes_left.position.y = -11.5
#
#			laser_eyes_right.position.x = -10
#			laser_eyes_right.position.y = -13.5
#
#		if player_direction_degrees / 45 == 6:
##			print("player angle in degrees is: ", player_direction_degrees)
##			animation_player.play("idle_up")
##			last_animation = "idle_up"
#
#			laser_eyes_left.position.x = -2
#			laser_eyes_left.position.y = -15.5
#
#			laser_eyes_right.position.x = 1
#			laser_eyes_right.position.y = -15.5
#
#		if player_direction_degrees / 45 == 7:
##			print("player angle in degrees is: ", player_direction_degrees)
##			animation_player.play("idle_right_up")
##			last_animation = "idle_right_up"
#
#			laser_eyes_left.position.x = 9.5
#			laser_eyes_left.position.y = -14
#
#			laser_eyes_right.position.x = 12
#			laser_eyes_right.position.y = -12

#	last_direction_index = player_direction_degrees / 45
#	set_directional_animations(player_direction_degrees)


func make_noise(intensity: int):
	noise_timer += 1
	if noise_timer == 10:
		GlobalSignals.emit_signal("made_noise", intensity, self.global_position, "cat", height_layer)
		noise_timer = 0


# I know this looks like a gibbon wrote it. I'm too tired to fix. It works.
func laser_eyes() -> void:
#	make_noise(8)
#	GlobalSignals.emit_signal("made_noise", self.global_position)
	if energy > 0:
		if energy == 1:
#			print("before energy adjustment energy is (should be 1): ", energy)
			energy = clamp(energy -1, 0, 100)
			GlobalSignals.emit_signal("player_energy_changed", energy)
#			print("after energy adjustment energy is (should be 0): ", energy)
			return
		elif energy == 2:
#			print("before energy adjustment energy is (should be 2): ", energy)
			energy = clamp(energy -2, 0, 100)
			GlobalSignals.emit_signal("player_energy_changed", energy)
#			print("after energy adjustment energy is (should be 1): ", energy)
			return
			
		energy = clamp(energy -2, 0, 100)
		GlobalSignals.emit_signal("player_energy_changed", energy)
#		print("after energy adjustment energy is (should be above 2 here): ", energy)
	
		laser_eyes_left.clear_points()
		laser_eyes_right.clear_points()
		
		laser_eyes_left.add_point(Vector2.ZERO)
		laser_eyes_right.add_point(Vector2.ZERO)
		
		laser_eyes_left.add_point(laser_eyes_left.get_local_mouse_position())
		laser_eyes_right.add_point(laser_eyes_right.get_local_mouse_position())
		
		left_ray.cast_to = left_ray.get_local_mouse_position() 
		right_ray.cast_to = right_ray.get_local_mouse_position() 
		
		left_ray.position = laser_eyes_left.position
		right_ray.position = laser_eyes_right.position
#		left_laser.to_local(left_ray.get_collision_point())
		
		if left_ray.is_colliding() == true:
#			If the player hits an asteroid, a signal goes to the asteroid so it can update
#			its integrity.
			if left_ray.get_collider().type == "asteroid":
				GlobalSignals.emit_signal("player_hit_asteroid", left_ray.get_collider().name, 10)
			
#			laser_eyes_left.set_point_position(1, to_local(left_ray.get_collision_point()))
			laser_eyes_left.set_point_position(1, laser_eyes_left.to_local(left_ray.get_collision_point()))
			
		if right_ray.is_colliding() == true:
#			collision_placeholder.visible = true
#			collision_placeholder.position = laser_eyes_right.get_point_position(1)
#			print("Right ray is hitting ", right_ray.get_collider().name)
#			laser_eyes_right.set_point_position(1, to_local(right_ray.get_collision_point()))
#			collision_placeholder.position = laser_eyes_right.get_point_position(1)
			laser_eyes_right.set_point_position(1, laser_eyes_right.to_local(right_ray.get_collision_point()))
#			
#		if right_ray.is_colliding() == true:
##			print("Right ray is hitting ", right_ray.get_collider().name)
#			laser_eyes_right.set_point_position(1, right_ray.get_collision_point())
			
#			print("Player is at: ", self.position)
#			print("Right ray is ending at: ", right_ray.get_collision_point())
#			print("Right laser is: ", laser_eyes_right.points)
##			print("Right ray length: ", right_ray.)
		
#		print("Left eye has ", laser_eyes_left.points, " points.")
#		print("Right eye has ", laser_eyes_right.points, " points.")
	
		laser_eyes_left.visible = true
		laser_eyes_right.visible = true


#func set_camera_transform(camera_path: Transform2D):
#	camera_transform.remote_path = camera_path
##	player_camera.x = global_position.x
##	player_camera.y = global_position.y


func set_energy(new_energy: int):
	pass

func update_energy() -> void:
	pass
#	energy = clamp(energy + change, 0, max_energy)
#	if no_movement_input() == true:
#		energy = clamp(energy + (base_energy_regen_rate * 2), 0, max_energy)
##		print("Gaining energy at double the normal rate.")
#		if energy == 99:
#			energy = 100
#	elif no_movement_input() == false:
#		energy = clamp(energy + base_energy_regen_rate, 0, 100)
##		print("Gaining energy at normal rate.")
#	GlobalSignals.emit_signal("player_energy_changed", energy)


#func no_movement_input() -> bool:
#	if not Input.is_action_pressed("up") and not Input.is_action_pressed("down") and not Input.is_action_pressed("left") and not Input.is_action_pressed("right"):
#		return true
#	else:
#		return false


func rotate_head(location: Vector2):
#	light.rotation = lerp_angle(rotation, global_position.direction_to(location).angle(), 0.1)
#	light.look_at(get_global_mouse_position())
	pass


func handle_hit():
	health -= 20
	GlobalSignals.emit_signal("player_health_changed", health)
	if health <= 0:
		die()


func die():
	emit_signal("died")
	queue_free()


func save():
	var save_dict = {
	"filename" : get_filename(),
	"parent" : get_parent().get_path(),
	"pos_x" : position.x, # Vector2 is not supported by JSON
	"pos_y" : position.y,
	"current_health" : health
	}
	
	return save_dict
		
