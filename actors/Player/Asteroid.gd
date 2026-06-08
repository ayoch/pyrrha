extends CharacterBody2D
class_name Asteroid

# A mineable, breakable space rock. Lifecycle is owned by AsteroidManager:
# this script just integrates its own motion, reports damage, and announces
# its own death via the asteroid_died signal. The manager handles pooling,
# fragmentation, and tree mutations.

const TYPE_STRING := "asteroid"

# Read by the player (collision checks) and the manager (fragmentation).
var type := TYPE_STRING
var species: String = "C11"
var size: int = 4                  # 4=whole, 3=large frag, 2=medium, 1=small
var is_fragment: bool = false
var can_break: bool = true
var integrity: int = 100
var asteroid_velocity: Vector2 = Vector2.ZERO
var rotation_rate: float = 0.0
var mass: float = 1.0

# Set by AsteroidManager when this rock first qualifies as an Earth threat.
# The rock continues along its trajectory and dies on reaching impact_point;
# impact_deaths is what gets added to the cumulative casualty score if it
# does so. Cleared on reset.
var impact_point: Vector2 = Vector2.ZERO
var impact_deaths: int = 0
var has_impact_fate: bool = false
# Set by AsteroidManager when this rock's death was an Earth impact; tells
# the death handler to skip dust + fragmentation (the rock is gone, not broken).
var died_to_earth: bool = false
# True for rocks intentionally aimed at Earth by the threat system. Nuisance
# rocks that happen to drift toward Earth do NOT get this flag — it is only set
# by AsteroidManager._spawn_threat_rock so the threat cap counts correctly.
var is_threat: bool = false

# Sleeper (Type 1 — dive): spawns stationary, tinted dark red. Activates when
# the player comes within sleeper_activate_radius; once active, accelerates
# toward the player. Tracked here so _physics_process can drive its behavior
# without manager polling.
var is_sleeper: bool = false
var sleeper_active: bool = false
const SLEEPER_ACTIVATE_RADIUS := 2200.0
const SLEEPER_CHASE_ACCEL := 600.0   # units/sec^2 once activated
const SLEEPER_TINT := Color(0.55, 0.18, 0.18, 1.0)

# Mass proxy by size. Roughly scale² so it tracks volume in our 2D world.
# Read by the player's collision handler for kinetic damage + plow-through.
const MASS_FOR_SIZE := {
	4: 1.0,    # whole
	3: 0.45,   # large frag
	2: 0.22,   # medium
	1: 0.07,   # small
}

# Latched at death to avoid emitting asteroid_died twice while the manager
# is removing us from the tree.
var _dying: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var physics_shape: CollisionPolygon2D = $Physics_Shape
@onready var projectile_shape: CollisionPolygon2D = $Projectile_Shape
@onready var no_physics_timer: Timer = $No_Physics_Timer


func _ready() -> void:
	GlobalSignals.connect("player_hit_asteroid", Callable(self, "_on_player_hit_asteroid"))
	# Grace period is started explicitly by AsteroidManager *after* add_child,
	# so the timer is guaranteed to be in the tree when start() runs.


# Repurpose this asteroid for a new spawn. Called by AsteroidManager when
# pulling from the pool. All state needed for the new life — including the
# silhouette polygon and visual scale — is set here so nothing leaks from the
# previous use.
#
# IMPORTANT: this can run on pool members that haven't entered the tree yet,
# so we cannot rely on @onready bindings being resolved. _ensure_node_refs()
# binds them directly via get_node so reset() works pre-tree.
func reset(p_species: String, p_size: int, p_is_fragment: bool,
		   p_texture: Texture2D, p_polygon: PackedVector2Array,
		   p_sprite_scale: float, p_position: Vector2,
		   p_velocity: Vector2, p_rotation_rate: float,
		   p_integrity: int) -> void:
	_ensure_node_refs()
	species = p_species
	size = p_size
	is_fragment = p_is_fragment
	can_break = not p_is_fragment       # only whole rocks fragment further
	mass = MASS_FOR_SIZE.get(p_size, 1.0)
	impact_point = Vector2.ZERO
	impact_deaths = 0
	has_impact_fate = false
	died_to_earth = false
	is_threat = false
	is_sleeper = false
	sleeper_active = false
	modulate = Color.WHITE   # reset tint in case last cycle was a sleeper
	# Collision layout: fragments only collide with the player; whole rocks
	# Whole rocks and fragments both collide only with the player.
	# Whole-on-whole collision is O(n²) in clump size with no gameplay response.
	if p_is_fragment:
		collision_layer = 4   # LAYER_FRAGMENT
		collision_mask = 1    # player only
	else:
		collision_layer = 2   # LAYER_WHOLE
		collision_mask = 1    # player only
	integrity = p_integrity
	position = p_position
	rotation = 0.0
	asteroid_velocity = p_velocity
	rotation_rate = p_rotation_rate
	velocity = Vector2.ZERO
	_dying = false
	visible = true
	sprite.texture = p_texture
	sprite.scale = Vector2(p_sprite_scale, p_sprite_scale)
	if p_polygon.size() >= 3:
		physics_shape.polygon = p_polygon
		projectile_shape.polygon = p_polygon
	# Disable physics immediately (safe to set property pre-tree); start_grace_period()
	# is called by the manager after add_child to actually start the timer.
	physics_shape.disabled = true


func _ensure_node_refs() -> void:
	if sprite == null:
		sprite = $Sprite2D
		physics_shape = $Physics_Shape
		projectile_shape = $Projectile_Shape
		no_physics_timer = $No_Physics_Timer


func _physics_process(delta: float) -> void:
	if _dying:
		return
	if integrity <= 0:
		_dying = true
		GlobalSignals.emit_signal("asteroid_died", self)
		return
	if is_sleeper:
		_tick_sleeper(delta)
	set_velocity(asteroid_velocity)
	move_and_slide()
	rotation += rotation_rate


func _tick_sleeper(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if not sleeper_active:
		var dist: float = global_position.distance_to(player.global_position)
		if dist <= SLEEPER_ACTIVATE_RADIUS:
			sleeper_active = true
			modulate = Color.WHITE   # drop the tint; ship is no longer sneaking
		return
	# Active sleeper: accelerate toward the player (no max speed cap).
	var dir: Vector2 = (player.global_position - global_position).normalized()
	asteroid_velocity += dir * SLEEPER_CHASE_ACCEL * delta


func _on_player_hit_asteroid(asteroid_name: String, damage: int) -> void:
	if name == asteroid_name:
		integrity -= damage


# Brief delay before physics collision engages, so a fresh fragment doesn't
# instantly re-collide with its siblings or with the parent it just split from.
# Public — called by AsteroidManager after add_child guarantees we're in tree.
func start_grace_period() -> void:
	_ensure_node_refs()
	physics_shape.disabled = true
	no_physics_timer.wait_time = 2.0
	no_physics_timer.start()


func _on_No_Physics_Timer_timeout() -> void:
	physics_shape.disabled = false
	no_physics_timer.stop()
