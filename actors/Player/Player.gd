extends CharacterBody2D
class_name Player

signal died

# --- Movement ---
# Main thrusters are deliberately much stronger than retro / side thrusters.
# Big course changes mean turning the ship around (which costs time at turn_rate)
# and burning forward; the weaker reverse/strafe lets you fine-tune your vector
# without giving up your facing, at the price of much slower acceleration.
@export var turn_rate: float = 2.0           # radians/sec; ship turns toward mouse at this max rate
@export var thrust_forward: float = 1500.0   # accel units/sec^2 (main engines)
@export var thrust_reverse: float = 200.0    # retros: ~1/7 main
@export var thrust_strafe: float = 200.0     # side thrusters: ~1/7 main
# No max speed cap — going fast is a risk/reward tradeoff (collisions hurt more).

# --- Stop mode ---
@export var stop_facing_tolerance: float = 0.1
@export var stop_speed_threshold: float = 5.0

# --- Mining laser ---
@export var mining_cone_degrees: float = 200.0
@export var mining_damage_per_tick: int = 10
# Energy: any active draw stops regeneration. Both rates are per-second.
@export var mining_energy_drain_per_sec: float = 120.0
@export var thrust_energy_drain_per_sec: float = 20.0
@export var energy_regen_per_sec: float = 80.0

# --- Shield ---
@export var max_shield: int = 100
@export var shield_regen_per_sec: float = 15.0
@export var shield_damage_per_impact_speed: float = 0.1  # shield damage = relative_speed * this
@export var ripple_pool_size: int = 8

# --- Collision response ---
# Physics model: kinetic energy ~ v², so damage does too. Bounces only happen
# at gentle taps; above the soft-bounce threshold the ship plows through, the
# asteroid is pulverized, and the ship eats dmg = (closing_speed / scale)².
# Reference points at the defaults (scale=100, max_h+sh = 200):
#   500 m/s  → 25 dmg (chip)
#   1000 m/s → 100 dmg (depletes shield)
#   1500 m/s → 225 dmg (lethal from full)
#   2000 m/s → 400 dmg (annihilation)
@export var soft_bounce_speed: float = 50.0
@export var hull_damage_scale: float = 100.0
# Asteroids with mass below this don't slow you down on impact — you plow
# through them. (WHOLE=1.0, LARGE=0.45, MEDIUM=0.22, SMALL=0.07)
@export var plow_through_mass_threshold: float = 0.3

# --- Camera zoom ---
@export var zoom_step: float = 0.01
@export var zoom_min: float = 0.1
@export var zoom_max: float = 100.0

var type := "player"
var health: int = 100
var max_health: int = 100
var energy: int = 100
var max_energy: int = 100
var shield: int = 100
var _energy_accum: float = 0.0
var _shield_accum: float = 0.0
var frequency_counter := 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var mining_beam_left: Line2D = $MiningBeamLeft
@onready var mining_beam_right: Line2D = $MiningBeamRight
@onready var mining_ray_left: RayCast2D = $MiningRayLeft
@onready var mining_ray_right: RayCast2D = $MiningRayRight
@onready var turret_barrel_left: Sprite2D = $TurretLeft/Barrel
@onready var turret_barrel_right: Sprite2D = $TurretRight/Barrel

## Muzzle in the barrel sprite's local space: top-center of the art, 420 px
## above the socket pivot. barrel.to_global() applies the barrel's rotation and
## 0.25 scale, giving the real-world muzzle the beams should fire from.
const BARREL_TIP_LOCAL: Vector2 = Vector2(0, -420)
@onready var prograde_indicator = $Prograde_Indicator
@onready var retrograde_indicator = $Retrograde_Indicator
@onready var thrust_indicator = $Thrust_Indicator
@onready var planet_indicator = $Planet_Indicator
@onready var thruster_flame: AnimatedSprite2D = $ThrusterFlame
# Rear-mounted main forward thrusters (fire on W or rotation).
@onready var fwd_flame_left: AnimatedSprite2D = $ForwardThrusterFlameLeft
@onready var fwd_flame_right: AnimatedSprite2D = $ForwardThrusterFlameRight
# Front-mounted retros (fire on S or rotation).
@onready var retro_flame_left: AnimatedSprite2D = $RetroThrusterFlameLeft
@onready var retro_flame_right: AnimatedSprite2D = $RetroThrusterFlameRight
# Side-mounted thrusters (fire on strafe).
@onready var thruster_flame_left: AnimatedSprite2D = $ThrusterFlameLeft
@onready var thruster_flame_left2: AnimatedSprite2D = $ThrusterFlameLeft2
@onready var thruster_flame_right: AnimatedSprite2D = $ThrusterFlameRight
@onready var thruster_flame_right2: AnimatedSprite2D = $ThrusterFlameRight2

# Within this many radians of the target heading, no rotation-thrusters fire.
const TURN_TOLERANCE := 0.05
@onready var shield_hull: CollisionShape2D = $ShieldHull
@onready var hull_box: CollisionPolygon2D = $CollisionBox
@onready var ripple_root: Node2D = $RippleRoot
@onready var player_camera: Camera2D = get_node("/root/Main/PlayerCamera")

var _ripple_free: Array = []
var _ripple_scene: PackedScene = preload("res://actors/Player/ShieldRipple.tscn")
var _shock_free: Array = []
var _shock_scene: PackedScene = preload("res://actors/Player/ShockBurst.tscn")
@export var shock_pool_size: int = 24
@export var laser_spark_chance: float = 0.25

var earth_location := Vector2.ZERO  # updated each frame from the Earth node if it exists
var _defense_turret: Node = null


func _ready() -> void:
	add_to_group("player")
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mining_beam_left.material = add_mat
	mining_beam_right.material = add_mat
	var beam_curve := Curve.new()
	beam_curve.add_point(Vector2(0.0, 1.0),  0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	beam_curve.add_point(Vector2(0.75, 0.02), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	beam_curve.add_point(Vector2(1.0, 0.45),  0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	mining_beam_left.width_curve = beam_curve
	mining_beam_right.width_curve = beam_curve
	for flame: AnimatedSprite2D in [
		thruster_flame, fwd_flame_left, fwd_flame_right,
		retro_flame_left, retro_flame_right,
		thruster_flame_left, thruster_flame_left2,
		thruster_flame_right, thruster_flame_right2,
	]:
		flame.material = add_mat
		flame.modulate = Color(1.9, 1.5, 1.0, 1.0)   # warm, additive boost
	# Beams: thicker + brighter on top of the additive blend material.
	mining_beam_left.width = 8.0
	mining_beam_right.width = 8.0
	mining_beam_left.modulate = Color(2.4, 2.4, 2.4, 1.0)
	mining_beam_right.modulate = Color(2.4, 2.4, 2.4, 1.0)
	mining_beam_left.visible = false
	mining_beam_right.visible = false
	thruster_flame.visible = false
	# Collision layers: player on layer 1; collides with whole asteroids (2) and
	# fragments (3). Mining rays look for whole+fragment (mask 6).
	collision_layer = 1
	collision_mask = 6
	mining_ray_left.collision_mask = 6
	mining_ray_right.collision_mask = 6
	for i in ripple_pool_size:
		var r: Node2D = _ripple_scene.instantiate()
		ripple_root.add_child(r)
		_ripple_free.push_back(r)
	for i in shock_pool_size:
		var s: Node2D = _shock_scene.instantiate()
		ripple_root.add_child(s)   # shares the top-level root with ripples
		_shock_free.push_back(s)
	_update_collision_shapes()
	_defense_turret = find_child("DefenseLaserTurret", false, false)
	GlobalSignals.emit_signal("player_exists")


# Shield circle is the physical collision while shield is up; ship hull takes
# over when shield is depleted. Deferred to avoid mutating during physics step.
func _update_collision_shapes() -> void:
	var shield_up: bool = shield > 0
	shield_hull.set_deferred("disabled", not shield_up)
	hull_box.set_deferred("disabled", shield_up)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("turret_toggle") and _defense_turret != null:
		_defense_turret.toggle()
		GlobalSignals.emit_signal("turret_state_changed", _defense_turret.enabled)


func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("stop"):
		_all_thrusters_off()
		_handle_stop_mode(delta)
	else:
		_handle_turning(delta)
		_handle_thrust(delta)
	_aim_turrets()
	_handle_mining_laser(delta)
	_handle_energy(delta)
	_push_energy_to_turret()
	_regenerate_shield(delta)
	_handle_zoom()
	_handle_nav_cycle()
	_update_indicators()
	_update_collision_shapes()

	var pre_move_vel := velocity
	move_and_slide()
	_resolve_slide_collisions(pre_move_vel)

	player_camera.global_position = global_position
	GlobalSignals.emit_signal("update_speed", velocity.length())

	frequency_counter += 1
	if frequency_counter % 30 == 0:
		GlobalSignals.emit_signal("broadcast_player_position", global_position)
	if frequency_counter >= 60:
		frequency_counter = 0


# ----------------------------------------------------------------------
# Movement
# ----------------------------------------------------------------------

func _handle_turning(delta: float) -> void:
	if GlobalSignals.control_mode == GlobalSignals.ControlMode.MOUSE_TURN:
		var angle_to_mouse: float = get_angle_to(get_global_mouse_position())
		var step: float = turn_rate * delta
		if abs(angle_to_mouse) <= step:
			rotation += angle_to_mouse
		else:
			rotation += sign(angle_to_mouse) * step
	else:
		# KEYBOARD_TURN: A/D rotate the ship at the same fixed rate.
		if Input.is_action_pressed("left"):
			rotation -= turn_rate * delta
		if Input.is_action_pressed("right"):
			rotation += turn_rate * delta


func _handle_thrust(delta: float) -> void:
	var energy_frac: float = float(energy) / float(max_energy)
	var forward := Vector2.RIGHT.rotated(rotation)
	var thrusting_forward := Input.is_action_pressed("forward")
	var thrusting_back := Input.is_action_pressed("back")
	if thrusting_forward:
		velocity += forward * thrust_forward * energy_frac * delta
	if thrusting_back:
		velocity -= forward * thrust_reverse * energy_frac * delta

	var strafe_left := false
	var strafe_right := false
	if GlobalSignals.control_mode == GlobalSignals.ControlMode.MOUSE_TURN:
		# A/D strafe (turning is done by the mouse).
		var ship_right := -forward.orthogonal()
		strafe_right = Input.is_action_pressed("right")
		strafe_left = Input.is_action_pressed("left")
		if strafe_right:
			velocity += ship_right * thrust_strafe * energy_frac * delta
		if strafe_left:
			velocity -= ship_right * thrust_strafe * energy_frac * delta
	# In KEYBOARD_TURN mode, A/D rotate (handled in _handle_turning); no strafe.

	_update_thrusters(thrusting_forward, thrusting_back, strafe_left, strafe_right)


# Per-thruster firing rules (OR-combined across inputs):
#   W   -> ForwardThrusterFlameLeft + ForwardThrusterFlameRight
#   S   -> RetroThrusterFlameLeft + RetroThrusterFlameRight
#   A   -> ThrusterFlameRight + ThrusterFlameRight2   (right-side flames push ship left)
#   D   -> ThrusterFlameLeft  + ThrusterFlameLeft2    (left-side flames push ship right)
#   Turn CW  -> ForwardThrusterFlameLeft + RetroThrusterFlameRight (rotation couple)
#   Turn CCW -> ForwardThrusterFlameRight + RetroThrusterFlameLeft
func _update_thrusters(fwd: bool, back: bool, sleft: bool, sright: bool) -> void:
	var turn_cw: bool = false
	var turn_ccw: bool = false
	if GlobalSignals.control_mode == GlobalSignals.ControlMode.MOUSE_TURN:
		var angle: float = get_angle_to(get_global_mouse_position())
		turn_cw = angle > TURN_TOLERANCE
		turn_ccw = angle < -TURN_TOLERANCE
	else:
		# KEYBOARD_TURN: A/D directly indicate rotation intent.
		turn_cw = Input.is_action_pressed("right")
		turn_ccw = Input.is_action_pressed("left")
	_set_flame(fwd_flame_left,        fwd or turn_cw)
	_set_flame(fwd_flame_right,       fwd or turn_ccw)
	_set_flame(retro_flame_left,      back or turn_ccw)
	_set_flame(retro_flame_right,     back or turn_cw)
	_set_flame(thruster_flame_left,   sright)
	_set_flame(thruster_flame_left2,  sright)
	_set_flame(thruster_flame_right,  sleft)
	_set_flame(thruster_flame_right2, sleft)


# Toggle visibility + animation playback + per-frame brightness flicker.
func _set_flame(node: AnimatedSprite2D, on: bool) -> void:
	if on:
		node.visible = true
		if not node.is_playing():
			node.play("burn")
		var b: float = randf_range(1.0, 1.6)
		node.modulate = Color(b, b * 0.75, b * 0.4, 1.0)
	else:
		if node.is_playing():
			node.stop()
		node.visible = false


func _all_thrusters_off() -> void:
	_set_flame(fwd_flame_left,        false)
	_set_flame(fwd_flame_right,       false)
	_set_flame(retro_flame_left,      false)
	_set_flame(retro_flame_right,     false)
	_set_flame(thruster_flame_left,   false)
	_set_flame(thruster_flame_left2,  false)
	_set_flame(thruster_flame_right,  false)
	_set_flame(thruster_flame_right2, false)


func _handle_stop_mode(delta: float) -> void:
	var speed := velocity.length()
	if speed <= stop_speed_threshold:
		velocity = Vector2.ZERO
		return
	# Two ways to brake:
	#   A) face prograde, burn retros (weak; no spin if already pointed there)
	#   B) face retrograde, burn mains (strong; costs a spin)
	# Pick whichever total time is shorter: rotation_time + burn_time.
	var vel_angle: float = velocity.angle()
	var prograde_angle: float = vel_angle
	var retrograde_angle: float = wrapf(vel_angle + PI, -PI, PI)
	var rot_to_pro: float = abs(wrapf(prograde_angle - rotation, -PI, PI))
	var rot_to_retro: float = abs(wrapf(retrograde_angle - rotation, -PI, PI))
	var t_retros: float = rot_to_pro / turn_rate + speed / thrust_reverse
	var t_mains: float = rot_to_retro / turn_rate + speed / thrust_forward
	var use_mains: bool = t_mains < t_retros
	var target_angle: float = retrograde_angle if use_mains else prograde_angle
	var thrust_force: float = thrust_forward if use_mains else thrust_reverse

	# Rotate toward chosen target.
	var delta_angle: float = wrapf(target_angle - rotation, -PI, PI)
	var step: float = turn_rate * delta
	if abs(delta_angle) <= step:
		rotation = target_angle
	else:
		rotation += sign(delta_angle) * step
	var burning: bool = abs(delta_angle) <= stop_facing_tolerance
	if burning:
		# Net braking force is always anti-velocity; which thruster set we fire
		# determines magnitude and visual.
		var burn: Vector2 = -velocity.normalized() * thrust_force * delta
		if burn.length() >= speed:
			velocity = Vector2.ZERO
		else:
			velocity += burn

	# Light the active thruster set.
	_set_flame(fwd_flame_left,    use_mains and burning)
	_set_flame(fwd_flame_right,   use_mains and burning)
	_set_flame(retro_flame_left,  (not use_mains) and burning)
	_set_flame(retro_flame_right, (not use_mains) and burning)


# ----------------------------------------------------------------------
# Mining laser
# ----------------------------------------------------------------------

func _handle_mining_laser(_delta: float) -> void:
	mining_beam_left.clear_points()
	mining_beam_right.clear_points()
	mining_beam_left.visible = false
	mining_beam_right.visible = false
	if not Input.is_action_pressed("shoot"):
		return
	var half_cone: float = deg_to_rad(mining_cone_degrees * 0.5)
	if abs(get_angle_to(get_global_mouse_position())) > half_cone:
		return
	_fire_beam(mining_beam_left, mining_ray_left)
	_fire_beam(mining_beam_right, mining_ray_right)


# Mining turrets visibly track the aim point (mouse), clamped to the same cone
# the beams fire within. Each barrel's art points "up", so the +90° cant rests
# it along ship-forward; angle-to-target (in the mount's local frame) + PI/2
# aims it, with per-mount convergence on the target.
func _aim_turrets() -> void:
	var target: Vector2 = get_global_mouse_position()
	var half_cone: float = deg_to_rad(mining_cone_degrees * 0.5)
	_aim_barrel(turret_barrel_left, mining_beam_left, mining_ray_left, target, half_cone)
	_aim_barrel(turret_barrel_right, mining_beam_right, mining_ray_right, target, half_cone)


# Rotates the barrel to the aim point (clamped to the cone), then anchors the
# beam and raycast origins to the barrel muzzle so the beam fires from the tip.
func _aim_barrel(
	barrel: Sprite2D, beam: Line2D, ray: RayCast2D, target: Vector2, half_cone: float
) -> void:
	var local_target: Vector2 = barrel.get_parent().to_local(target)
	var angle: float = clampf(local_target.angle(), -half_cone, half_cone)
	barrel.rotation = angle + PI / 2.0
	var muzzle: Vector2 = barrel.to_global(BARREL_TIP_LOCAL)
	beam.global_position = muzzle
	ray.global_position = muzzle


# Unified energy budget. Any active drain stops regen for that frame; idle
# frames refill. Mining drains heavily, thrust drains modestly.
# Defense laser drain is read from the turret child node each frame.
func _handle_energy(delta: float) -> void:
	var laser_firing: bool = Input.is_action_pressed("shoot") \
		and abs(get_angle_to(get_global_mouse_position())) <= deg_to_rad(mining_cone_degrees * 0.5)
	var thrusting: bool = (
		Input.is_action_pressed("forward")
		or Input.is_action_pressed("back")
		or Input.is_action_pressed("left")
		or Input.is_action_pressed("right")
		or Input.is_action_pressed("stop")
	)
	var rotating: bool = false
	if GlobalSignals.control_mode == GlobalSignals.ControlMode.MOUSE_TURN \
			and not Input.is_action_pressed("stop"):
		var angle: float = get_angle_to(get_global_mouse_position())
		rotating = abs(angle) > TURN_TOLERANCE
	var defense_firing: bool = false
	if _defense_turret != null and _defense_turret.has_method("is_firing"):
		defense_firing = _defense_turret.is_firing()
	var rate: float = 0.0
	if laser_firing:
		rate -= mining_energy_drain_per_sec
	if thrusting:
		rate -= thrust_energy_drain_per_sec
	if rotating:
		rate -= thrust_energy_drain_per_sec * 0.4
	if defense_firing:
		rate -= thrust_energy_drain_per_sec * 0.75
	if rate == 0.0 and energy < max_energy:
		rate = energy_regen_per_sec
	if rate == 0.0:
		return
	_energy_accum += rate * delta
	var whole: int = int(_energy_accum)
	if whole != 0:
		var prev: int = energy
		energy = clamp(energy + whole, 0, max_energy)
		_energy_accum -= whole
		if energy != prev:
			GlobalSignals.emit_signal("player_energy_changed", energy)


func _fire_beam(beam: Line2D, ray: RayCast2D) -> void:
	var energy_frac: float = float(energy) / float(max_energy)
	ray.target_position = ray.get_local_mouse_position()
	ray.force_raycast_update()
	var endpoint: Vector2 = beam.get_local_mouse_position()
	if ray.is_colliding():
		var collider = ray.get_collider()
		var hit_point: Vector2 = ray.get_collision_point()
		if collider and "type" in collider and collider.type == "asteroid":
			var dist: float = ray.global_position.distance_to(hit_point)
			var range_falloff: float = clamp(1.0 - dist / 2000.0, 0.3, 1.0)
			var dmg: int = max(1, int(mining_damage_per_tick * energy_frac * range_falloff))
			GlobalSignals.emit_signal("player_hit_asteroid", collider.name, dmg)
			if randf() < laser_spark_chance:
				_spawn_shock(hit_point)
		endpoint = beam.to_local(hit_point)
	# Three points: origin → focus/hit (pinch) → tail (spreads back open).
	# The width curve maps t=0→full, t=0.75→pinch, t=1→partial splay.
	beam.add_point(Vector2.ZERO)
	beam.add_point(endpoint)
	beam.add_point(endpoint * (4.0 / 3.0))
	var alpha: float = lerpf(0.25, 1.0, energy_frac)
	beam.modulate = Color(1.0, 1.0, 1.0, alpha)
	beam.visible = true


# ----------------------------------------------------------------------
# Shield + impact
# ----------------------------------------------------------------------

func _regenerate_shield(delta: float) -> void:
	if shield >= max_shield:
		return
	_shield_accum += shield_regen_per_sec * delta
	var whole: int = int(_shield_accum)
	if whole > 0:
		shield = clamp(shield + whole, 0, max_shield)
		_shield_accum -= whole
		GlobalSignals.emit_signal("player_shield_changed", shield)


func _apply_shield_hit(rel_speed: float, at_pos: Vector2, normal: Vector2) -> void:
	var dmg: int = max(1, int(rel_speed * shield_damage_per_impact_speed))
	shield = clamp(shield - dmg, 0, max_shield)
	_shield_accum = 0.0
	GlobalSignals.emit_signal("player_shield_changed", shield)
	_spawn_ripple(at_pos, normal)


func _spawn_ripple(at_pos: Vector2, normal: Vector2) -> void:
	if _ripple_free.is_empty():
		return
	var r = _ripple_free.pop_back()
	r.emit(at_pos, normal, Callable(self, "_return_ripple"))


func _return_ripple(r) -> void:
	_ripple_free.push_back(r)


func _spawn_shock(at_pos: Vector2) -> void:
	if _shock_free.is_empty():
		return
	var s = _shock_free.pop_back()
	s.emit(at_pos, Callable(self, "_return_shock"))


func _return_shock(s) -> void:
	_shock_free.push_back(s)


# ----------------------------------------------------------------------
# Slide collision resolution (ship vs asteroid bodies)
# ----------------------------------------------------------------------

func _resolve_slide_collisions(pre_move_vel: Vector2) -> void:
	# Tally impact mass to decide how much of the velocity move_and_slide
	# cancelled should be restored (because the cancellation came from massless
	# fragments we should plow through).
	var total_impact_mass: float = 0.0
	var plow_impact_mass: float = 0.0

	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other == null or not ("type" in other) or other.type != "asteroid":
			continue
		var normal: Vector2 = c.get_normal()
		var contact: Vector2 = c.get_position()
		var rel_vel: Vector2 = pre_move_vel - other.asteroid_velocity
		var closing: float = abs(rel_vel.dot(normal))
		var impactor_mass: float = float(other.mass) if "mass" in other else 1.0

		# Gentle bump: bounce, zero damage, asteroid survives. Doesn't count
		# toward plow-through tallying (we deliberately bounced).
		if closing < soft_bounce_speed:
			velocity = velocity.bounce(normal)
			other.asteroid_velocity = other.asteroid_velocity.bounce(-normal)
			if shield > 0:
				_spawn_ripple(contact, normal)
			continue

		# Small fragments (size 1) have a chance to deflect off an active shield
		# instead of being pulverized — shield takes a small hit, rock bounces away.
		if shield > 0 and "size" in other and other.size == 1 and randf() < 0.6:
			velocity = velocity.bounce(normal)
			other.asteroid_velocity = other.asteroid_velocity.bounce(-normal) * randf_range(0.8, 1.2)
			_apply_shield_hit(closing, contact, normal)
			_spawn_ripple(contact, normal)
			continue

		# Shock burst at the contact point — quick visual cue that something hit you.
		_spawn_shock(contact)

		# Kinetic damage scaled by impactor mass. Shield absorbs first, overflow
		# eats hull. Asteroid is pulverized regardless.
		var raw_dmg: float = pow(closing / hull_damage_scale, 2.0) * impactor_mass
		var dmg_remaining: float = raw_dmg
		if shield > 0:
			var absorbed: float = min(float(shield), dmg_remaining)
			shield = clamp(shield - int(ceil(absorbed)), 0, max_shield)
			_shield_accum = 0.0
			GlobalSignals.emit_signal("player_shield_changed", shield)
			_spawn_ripple(contact, normal)
			dmg_remaining -= absorbed
		if dmg_remaining > 0:
			health = clamp(health - int(ceil(dmg_remaining)), 0, max_health)
			GlobalSignals.emit_signal("player_health_changed", health)
			if health <= 0:
				var info: String = _killer_report(other, closing, raw_dmg)
				print(info)
				GlobalSignals.last_killer_info = info
				die()
				return
		# Pulverize the asteroid — any rock's integrity is dwarfed by impact KE.
		GlobalSignals.emit_signal("player_hit_asteroid", other.name, 99999)

		total_impact_mass += impactor_mass
		if impactor_mass < plow_through_mass_threshold:
			plow_impact_mass += impactor_mass

	# Restore the share of velocity that was lost to plow-through-class hits.
	if total_impact_mass > 0.0001:
		var plow_fraction: float = plow_impact_mass / total_impact_mass
		var velocity_lost: Vector2 = pre_move_vel - velocity
		velocity += velocity_lost * plow_fraction


# ----------------------------------------------------------------------
# Misc UI
# ----------------------------------------------------------------------

func _push_energy_to_turret() -> void:
	if _defense_turret != null:
		_defense_turret.energy_fraction = float(energy) / float(max_energy)


func _handle_zoom() -> void:
	if Input.is_action_pressed("zoom in"):
		player_camera.zoom.x = clamp(player_camera.zoom.x + zoom_step, zoom_min, zoom_max)
		player_camera.zoom.y = clamp(player_camera.zoom.y + zoom_step, zoom_min, zoom_max)
	if Input.is_action_pressed("zoom out"):
		player_camera.zoom.x = clamp(player_camera.zoom.x - zoom_step, zoom_min, zoom_max)
		player_camera.zoom.y = clamp(player_camera.zoom.y - zoom_step, zoom_min, zoom_max)


# 4-state cycle: off → thrust → planet → both → off
func _handle_nav_cycle() -> void:
	if not Input.is_action_just_pressed("Nav"):
		return
	var t: bool = thrust_indicator.visible
	var p: bool = planet_indicator.visible
	if not t and not p:
		thrust_indicator.visible = true
	elif t and not p:
		thrust_indicator.visible = false
		planet_indicator.visible = true
	elif not t and p:
		thrust_indicator.visible = true
	else:
		thrust_indicator.visible = false
		planet_indicator.visible = false


func _update_indicators() -> void:
	if velocity.length_squared() > 0.0:
		thrust_indicator.rotation = velocity.angle() - rotation + PI / 2
	var earth = get_tree().get_first_node_in_group("earth")
	if earth != null:
		earth_location = earth.global_position
	var to_earth: float = (earth_location - global_position).angle() - rotation
	planet_indicator.position = Vector2(cos(to_earth), sin(to_earth)) * 160.0
	planet_indicator.rotation = to_earth + PI / 2


# ----------------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------------

func die() -> void:
	died.emit()
	GlobalSignals.emit_signal("player_died")
	queue_free()


# Diagnostic dump about whatever rock just killed us. Stored on GlobalSignals
# so DeathScreen can show it; printed so it lands in the editor log too.
func _killer_report(other, closing: float, raw_dmg: float) -> String:
	var lines: PackedStringArray = []
	lines.append("--- KILLED BY ---")
	lines.append("name=%s  species=%s  size=%s  mass=%.2f  is_threat=%s" % [
		other.name,
		(other.species if "species" in other else "?"),
		(str(other.size) if "size" in other else "?"),
		(other.mass if "mass" in other else 0.0),
		(str(other.is_threat) if "is_threat" in other else "?")
	])
	var sprite_visible: String = "?"
	var tex_path: String = "(no sprite child)"
	if other.has_node("Sprite2D"):
		var sp: Sprite2D = other.get_node("Sprite2D")
		sprite_visible = str(sp.visible)
		tex_path = "(null)" if sp.texture == null else sp.texture.resource_path
	lines.append("root.visible=%s  sprite.visible=%s  texture=%s" % [
		str(other.visible), sprite_visible, tex_path
	])
	lines.append("modulate=%s  z_index=%d  scale=%s" % [
		str(other.modulate), other.z_index, str(other.scale)
	])
	lines.append("pos=(%.0f, %.0f)" % [other.global_position.x, other.global_position.y])
	if "asteroid_velocity" in other:
		var v: Vector2 = other.asteroid_velocity
		lines.append("velocity=%.0f m/s @ %.0f°" % [v.length(), rad_to_deg(v.angle())])
	lines.append("collision_layer=%d  collision_mask=%d" % [other.collision_layer, other.collision_mask])
	if "has_impact_fate" in other:
		lines.append("has_impact_fate=%s  died_to_earth=%s" % [
			str(other.has_impact_fate), str(other.died_to_earth)
		])
	lines.append("impact: closing=%.0f m/s  raw_dmg=%.1f" % [closing, raw_dmg])
	return "\n".join(lines)


func save() -> Dictionary:
	return {
		"filename": get_scene_file_path(),
		"parent": get_parent().get_path(),
		"pos_x": position.x,
		"pos_y": position.y,
		"current_health": health,
	}
