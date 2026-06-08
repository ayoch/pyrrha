extends Node

# ==============================================================================
# AsteroidManager
# ------------------------------------------------------------------------------
# Responsibilities:
#   1. Spawn waves of whole asteroids in a ring around the origin.
#   2. Fragment dying asteroids into smaller debris by consulting a per-species
#      "break recipe" cached at startup.
#   3. Recycle dead asteroids through a single bounded pool to avoid runtime
#      allocation pressure during heavy combat.
#   4. Advance stage timer; spawn boss formations (Pack_Six / Pack_Twelve) at
#      stage transitions.
#
# Architecture notes:
#   - One pool, one cap. Asteroids that return when the pool is full are
#     queue_free'd. No threading required: textures load once at _ready, and
#     pool warm-up at startup amortizes instantiate() cost.
#   - There is no "Break" sub-tree concept. A fragmentation is just N reset()
#     calls on pooled asteroids, set up with the correct texture and physics
#     properties from the cached recipe.
# ==============================================================================

const ASTEROID_SCENE: PackedScene = preload("res://actors/Player/Asteroid.tscn")
const PACK_SIX: PackedScene = preload("res://Pack_Six.tscn")
const PACK_TWELVE: PackedScene = preload("res://Pack_Twelve.tscn")
const DUST_SCENE: PackedScene = preload("res://actors/Player/DustCloud.tscn")

# Species → "whole" (unbroken) texture.
const WHOLE_TEXTURES := {
	"C11": preload("res://asteroids/Chondrite/C1/C1whole.png"),
	"S11": preload("res://asteroids/Stony/S1/S1whole.png"),
}

# Species → directory of fragment images. Scanned once at startup; missing
# species fall back to C1 art.
const BREAK_DIRS := {
	"C11": "res://asteroids/Chondrite/C1/Break1/",
	"C21": "res://asteroids/Chondrite/C1/Break1/",
	"S11": "res://asteroids/Stony/S1/Break1/",
	"S21": "res://asteroids/Stony/S1/Break1/",
	"M11": "res://asteroids/Chondrite/C1/Break1/",
	"M21": "res://asteroids/Chondrite/C1/Break1/",
}

# Asteroid.size convention.
const SIZE_WHOLE := 4
const SIZE_LARGE := 3
const SIZE_MEDIUM := 2
const SIZE_SMALL := 1

# Fixed visual scale per size category. Asteroids only ever spawn at one of
# these scales so the precomputed silhouette polygons stay correct.
const SIZE_SCALES := {
	SIZE_WHOLE:  0.75,
	SIZE_LARGE:  0.50,
	SIZE_MEDIUM: 0.35,
	SIZE_SMALL:  0.20,
}

# How many fragments each recipe entry produces — rolled per entry per break,
# so even repeated breaks of the same species look different.
const FRAGMENT_MULTIPLIER_MIN := 2
const FRAGMENT_MULTIPLIER_MAX := 8

# Silhouette extraction settings.
const SILHOUETTE_ALPHA_THRESHOLD := 0.5   # pixels with alpha >= this are "solid"
const SILHOUETTE_EPSILON := 2.0           # polygon simplification (pixels)

# Physics collision layers (1-indexed in editor; bitmasks at runtime).
#   layer 1 (=1) : player
#   layer 2 (=2) : whole asteroids
#   layer 3 (=4) : fragments
# Both wholes and fragments collide only with the player (mask=1).
# Whole-on-whole was removed: O(n²) pairs in clumps, no gameplay response.
# Mining/defense ray masks use 6 (wholes + fragments).
const LAYER_PLAYER := 1
const LAYER_WHOLE := 2
const LAYER_FRAGMENT := 4
# Whole rocks only collide with the player — not with each other.
# Whole-on-whole collision is O(n²) in clump size and has no gameplay response code.
const MASK_WHOLE := LAYER_PLAYER                     # 1
const MASK_FRAGMENT := LAYER_PLAYER                  # 1

# Hard cap on fragments spawned per asteroid break. Each recipe can have many
# entries × up to 8 fragments each; a dense clump breaking simultaneously
# would otherwise produce hundreds of nodes at once.
const MAX_FRAGMENTS_PER_BREAK := 12

# Fragment collision polygon vertex count (cheap convex octagon).
const FRAGMENT_HULL_SIDES := 8

# Pool warm-up sizes. Pools grow on demand (no fixed cap) and shrink toward
# the recent high-water mark when oversized — see _trim_pool().
const POOL_WARMUP := 200
const DUST_POOL_WARMUP := 100

# Spread tree-mutation work across frames so a big fragmentation burst doesn't
# hitch. Each frame's _drain_spawn_queue adds at most this many.
const MAX_SPAWNS_PER_FRAME := 6

# Pool trimming policy: how often to shed an excess entry, and how far above
# the recent peak usage a pool may sit before trimming kicks in.
const POOL_TRIM_INTERVAL_SEC := 1.0
const POOL_SLACK_FACTOR := 1.5      # tolerate this many * recent-peak idle
const HIGH_WATER_DECAY_PER_SEC := 0.05   # fraction; peak relaxes downward

const DUST_POSITION_JITTER := 160.0
const DUST_COUNT_BY_SIZE := {4: 80, 3: 40, 2: 20, 1: 8}

# ----------------------------------------------------------------------
# Stage definitions
# ----------------------------------------------------------------------
# Each stage runs an ACTIVE phase (normal spawns + scheduled threat rocks +
# a climactic boss event) followed by a RESPITE phase (no spawns; the player
# can dock at the station to heal). After the player leaves the station's
# vicinity (post the heal window), the next stage begins. Completing all
# stages triggers a win.

enum Phase { ACTIVE, RESPITE, WON, DEAD }

const STAGES := [
	{"duration": 45.0, "threats": 1, "boss": "fastball",            "base_credits": 200},
	{"duration": 60.0, "threats": 2, "boss": "double_fastball",     "base_credits": 275},
	{"duration": 75.0, "threats": 3, "boss": "clump_6",             "base_credits": 375},
	{"duration": 90.0, "threats": 4, "boss": "clump_plus_fastball", "base_credits": 475},
	{"duration": 90.0, "threats": 5, "boss": "layered_clump",       "base_credits": 600},
	{"duration": 90.0, "threats": 6, "boss": "finale",              "base_credits": 725},
]

# Credits awarded = base_credits * pct, where pct is determined by how many
# people died on Earth during the stage. Find the highest tier whose
# min_deaths <= stage_deaths.
const CREDIT_TIERS := [
	{"min_deaths": 0,           "pct": 1.00},
	{"min_deaths": 1,           "pct": 0.85},
	{"min_deaths": 10_000,      "pct": 0.70},
	{"min_deaths": 100_000,     "pct": 0.50},
	{"min_deaths": 1_000_000,   "pct": 0.25},
]

# Boss patterns: each is a list of {at: seconds_after_boss_start, fn: method_name, args: Array}
const BOSS_PATTERNS := {
	"fastball": [
		{"at": 0.0, "fn": "_spawn_fastball", "args": []},
	],
	"double_fastball": [
		{"at": 0.0, "fn": "_spawn_fastball", "args": []},
		{"at": 0.6, "fn": "_spawn_fastball", "args": []},
	],
	"clump_6": [
		{"at": 0.0, "fn": "_spawn_clump", "args": [6, false]},
	],
	"clump_plus_fastball": [
		{"at": 0.0, "fn": "_spawn_clump", "args": [6, false]},
		{"at": 2.0, "fn": "_spawn_fastball", "args": []},
	],
	"layered_clump": [
		{"at": 0.0, "fn": "_spawn_clump", "args": [6, false]},
		{"at": 3.0, "fn": "_spawn_clump", "args": [12, true]},
	],
	"finale": [
		{"at": 0.0, "fn": "_spawn_clump", "args": [12, true]},
		{"at": 2.0, "fn": "_spawn_fastball", "args": []},
		{"at": 4.0, "fn": "_spawn_fastball", "args": []},
	],
}

# Respite: heal phase + departure to start next stage.
const RESPITE_HEAL_DURATION := 60.0
const STATION_HEAL_RADIUS := 1500.0
const STATION_HEAL_RATE := 25.0           # health AND shield per second

# Threat rock velocity (aimed at Earth). Fastballs go this much faster.
const THREAT_BASE_SPEED := 700.0
const FASTBALL_SPEED_MULT := 2.5
const CLUMP_SPACING := 250.0

@export var maximum_number_asteroids: int = 50
@export var maximum_asteroid_distance: float = 50000.0
@export var break_position_jitter: float = 50.0

@onready var spawn_timer: Timer = $Asteroid_Spawn_Timer
@onready var stage_timer: Timer = $Stage_Timer

# Per species, an Array of fragment specs: [{"size": int, "texture": Texture2D}]
var _break_recipes := {}

# Texture2D → PackedVector2Array. The polygon is centered on the texture's
# midpoint and pre-scaled for that texture's canonical use (whole texture at
# SIZE_WHOLE, fragment texture at the size encoded in its filename). Built once
# at _ready() — see _build_polygon_cache().
var _polygon_for_texture: Dictionary = {}

# Detached pool of inactive asteroids.
var _pool: Array = []

# Asteroids prepared this frame, awaiting add_child next physics tick. Defers
# tree mutation so we never add children while iterating get_children() above.
var _spawn_queue: Array = []

var _stage_index: int = 0   # 0-based; STAGES[_stage_index]
var _phase: int = Phase.ACTIVE
var _phase_elapsed: float = 0.0
var _threat_schedule: Array = []   # remaining {at: float} entries this stage
var _boss_queue: Array = []        # remaining {at, fn, args} this boss
var _boss_started: bool = false
var _boss_queue_empty_at: float = -1.0   # _phase_elapsed when boss queue last drained
const WHOLE_CLEAR_TIMEOUT := 25.0        # fallback: enter respite even if whole rocks remain
var _heal_accum_h: float = 0.0
var _heal_accum_s: float = 0.0
var _has_docked_this_respite: bool = false
var _frequency_counter: int = 0
var _rng := RandomNumberGenerator.new()

# Casualty modeling. Earth's own texture is sampled for the land/ocean mask;
# noise adds density variation on land so the same continent isn't uniform.
const MAX_DEATHS_PER_IMPACT := 10_000_000
const SIZE_DEATH_SCALE := {
	4: 1.0,     # whole — dominant; the disaster events
	3: 0.20,    # large frag — meaningful but a fifth of a whole
	2: 0.05,    # medium
	1: 0.005,   # small — barely registers
}
const EARTH_IMPACT_TOLERANCE := 50.0   # world units; impact triggers within this of impact_point
var _earth_image: Image
var _earth_image_scale: float = 1.0   # the Earth sprite's scale at image-capture time
var _density_noise: FastNoiseLite
var _total_deaths: int = 0
var _stage_deaths_start: int = 0   # _total_deaths snapshot at start of each stage
var _asteroids_destroyed: int = 0
var _shop_opened_this_respite: bool = false

# Dust cloud pool. Dust nodes are kept as children of this manager and reused.
var _dust_pool: Array = []

# Adaptive pool sizing: track concurrent in-use count for each pool, decay it
# slowly so transient spikes don't permanently inflate the high-water mark.
var _asteroids_in_use: int = 0
var _dust_in_use: int = 0
var _asteroid_high_water: float = float(POOL_WARMUP)
var _dust_high_water: float = float(DUST_POOL_WARMUP)
var _trim_accum: float = 0.0


func _ready() -> void:
	_rng.randomize()
	GlobalSignals.connect("asteroid_died", Callable(self, "_on_asteroid_died"))
	GlobalSignals.connect("player_died", Callable(self, "_on_player_died"))
	GlobalSignals.station_shop_departed.connect(_on_shop_departed)
	_build_break_recipes()
	_build_polygon_cache()
	_build_population_data()
	_warm_pool(POOL_WARMUP)
	_warm_dust_pool(DUST_POOL_WARMUP)
	_start_spawn_timer()
	_start_stage(0)


func _physics_process(delta: float) -> void:
	_drain_spawn_queue()
	_decay_high_water(delta)
	_trim_accum += delta
	if _trim_accum >= POOL_TRIM_INTERVAL_SEC:
		_trim_accum = 0.0
		_trim_pools()
	_check_earth_impacts()
	_advance_phase(delta)
	_frequency_counter += 1
	if _frequency_counter % 60 == 0:
		_cull_distant_and_report()
	if _frequency_counter >= 60:
		_frequency_counter = 0


# Any asteroid that's penetrated Earth's visual radius this frame "impacts":
# whole rocks trigger an explosion on the EarthExplosionStage; fragments just
# vanish (too small to flash from space). Either way the rock dies.
func _check_earth_impacts() -> void:
	var earth = get_tree().get_first_node_in_group("earth")
	if earth == null:
		return
	var earth_pos: Vector2 = earth.global_position
	var earth_radius: float = _node_visual_radius(earth)
	if earth_radius <= 0.0:
		return
	var stage = get_tree().get_first_node_in_group("earth_explosion_stage")
	for c in get_children():
		if not c.is_in_group("asteroid"):
			continue
		# Assign impact fate the first time a rock qualifies as a threat. The
		# impact point is random along the chord the trajectory cuts through
		# Earth's disk — the rock travels along its course, dying at that point.
		if not c.has_impact_fate:
			if _is_on_collision_course_world(c.global_position, c.asteroid_velocity, earth_pos, earth_radius):
				var ip = _compute_random_impact_point(c.global_position, c.asteroid_velocity, earth_pos, earth_radius)
				if ip != null:
					c.impact_point = ip
					c.impact_deaths = _sample_deaths(ip, c.size)
					c.has_impact_fate = true
		# If fate is assigned, trigger impact when the rock reaches or passes
		# its impact point. We check both proximity (slow rocks) and "have we
		# passed it along the velocity direction" (fast rocks, overshoot).
		if c.has_impact_fate:
			var to_impact: Vector2 = c.impact_point - c.global_position
			var passed: bool = to_impact.length_squared() < EARTH_IMPACT_TOLERANCE * EARTH_IMPACT_TOLERANCE \
				or (c.asteroid_velocity.length_squared() > 0.0 and to_impact.dot(c.asteroid_velocity) <= 0.0)
			if passed:
				_on_earth_impact(c, stage)


const EXPLOSION_SCALE_FOR_SIZE := {
	4: 0.18,   # whole
	3: 0.10,   # large frag
	2: 0.06,   # medium
	1: 0.03,   # small
}

func _on_earth_impact(asteroid, stage) -> void:
	# Snap the rock to its assigned impact point so the explosion and the
	# disappearance both happen exactly there, regardless of frame overshoot.
	asteroid.global_position = asteroid.impact_point
	if asteroid.impact_deaths > 0:
		_total_deaths += asteroid.impact_deaths
		GlobalSignals.emit_signal("total_deaths_changed", _total_deaths)
	if stage != null:
		stage.spawn_explosion(asteroid.impact_point, EXPLOSION_SCALE_FOR_SIZE.get(asteroid.size, 0.3))
	asteroid.died_to_earth = true   # tells _on_asteroid_died to skip dust + fragmentation
	asteroid.integrity = -1         # asteroid will report its own death next physics tick


func _is_on_collision_course_world(ast_pos: Vector2, ast_vel: Vector2, earth_pos: Vector2, earth_radius: float) -> bool:
	var to_earth: Vector2 = earth_pos - ast_pos
	if to_earth.length() < earth_radius:
		return true
	if ast_vel.length_squared() < 1.0:
		return false
	var dir: Vector2 = ast_vel.normalized()
	var t: float = to_earth.dot(dir)
	if t < 0.0:
		return false
	return (to_earth - dir * t).length() < earth_radius


# Picks a uniformly random point along the trajectory's chord through Earth.
# Returns null if the geometry is degenerate (shouldn't happen post-collision-course check).
func _compute_random_impact_point(ast_pos: Vector2, ast_vel: Vector2, earth_pos: Vector2, earth_radius: float):
	if ast_vel.length_squared() < 1.0:
		return earth_pos   # stationary already-overlapping rock
	var dir: Vector2 = ast_vel.normalized()
	var v: Vector2 = ast_pos - earth_pos
	var b: float = v.dot(dir)
	var disc: float = b * b - (v.dot(v) - earth_radius * earth_radius)
	if disc < 0.0:
		return null
	var sq: float = sqrt(disc)
	var t_in: float = -b - sq
	var t_out: float = -b + sq
	# If the rock is already inside the disk, clamp t_in forward to 0.
	t_in = max(t_in, 0.0)
	if t_out <= t_in:
		return ast_pos
	return ast_pos + dir * _rng.randf_range(t_in, t_out)


# ----------------------------------------------------------------------
# Population / casualty model — uses Earth's own texture for land/ocean mask
# and a 2D noise field for density variation within land.
# ----------------------------------------------------------------------

func _build_population_data() -> void:
	_density_noise = FastNoiseLite.new()
	_density_noise.seed = _rng.randi()
	_density_noise.frequency = 0.012
	var earth = get_tree().get_first_node_in_group("earth")
	if earth != null and earth is Sprite2D and earth.texture != null:
		_earth_image = earth.texture.get_image()
		_earth_image_scale = abs(earth.scale.x)


func _sample_deaths(impact_world_pos: Vector2, size: int) -> int:
	if _earth_image == null:
		return 0
	var earth = get_tree().get_first_node_in_group("earth")
	if earth == null:
		return 0
	# Convert world impact position to a pixel in Earth's texture.
	var offset: Vector2 = impact_world_pos - earth.global_position
	var img_size: Vector2 = Vector2(_earth_image.get_size())
	var px: Vector2 = img_size * 0.5 + offset / _earth_image_scale
	if px.x < 0 or px.x >= img_size.x or px.y < 0 or px.y >= img_size.y:
		return 0
	var color: Color = _earth_image.get_pixel(int(px.x), int(px.y))
	if color.a < 0.1:
		return 0   # transparent — outside Earth's disk
	# Land vs ocean by simple R+G-B heuristic on the planet art.
	var land_factor: float = clamp((color.r + color.g) * 0.5 - color.b, 0.0, 1.0)
	if land_factor < 0.05:
		return 0
	# Noise gives density variation within land — same point always returns the
	# same value, so the world is deterministic.
	var noise_val: float = _density_noise.get_noise_2dv(px) * 0.5 + 0.5
	var size_mult: float = float(SIZE_DEATH_SCALE.get(size, 0.0))
	return int(land_factor * noise_val * MAX_DEATHS_PER_IMPACT * size_mult)


func _node_visual_radius(n) -> float:
	if n == null or not (n is Sprite2D) or n.texture == null:
		return 0.0
	return n.texture.get_size().x * 0.5 * abs(n.scale.x)


# ----------------------------------------------------------------------
# Pool
# ----------------------------------------------------------------------

func _warm_pool(count: int) -> void:
	for i in count:
		_pool.push_back(_make_fresh_asteroid())


func _make_fresh_asteroid() -> Node:
	# reset() sets collision_layer / collision_mask based on whether the rock is
	# being spawned as a whole asteroid or a fragment; nothing to do here.
	return ASTEROID_SCENE.instantiate()


func _take_from_pool() -> Node:
	_asteroids_in_use += 1
	if _asteroids_in_use > _asteroid_high_water:
		_asteroid_high_water = float(_asteroids_in_use)
	if _pool.is_empty():
		return _make_fresh_asteroid()
	return _pool.pop_back()


func _return_to_pool(ast: Node) -> void:
	_asteroids_in_use = max(0, _asteroids_in_use - 1)
	_pool.push_back(ast)


# ----------------------------------------------------------------------
# Wave spawning
# ----------------------------------------------------------------------

func _start_spawn_timer() -> void:
	spawn_timer.wait_time = _rng.randi_range(1, 5)
	spawn_timer.start()


func _on_Asteroid_Spawn_Timer_timeout() -> void:
	# Regular waves only during the ACTIVE phase. Threats + bosses are scheduled
	# separately in _advance_phase.
	if _phase == Phase.ACTIVE:
		var room := maximum_number_asteroids - _count_active_asteroids()
		if room > 0:
			var wave_size: int = min(_rng.randi_range(1, 16), room)
			for i in wave_size:
				_queue_whole_asteroid(_random_species())
	_start_spawn_timer()


func _queue_whole_asteroid(species: String) -> void:
	var rock := _take_from_pool()
	var tex: Texture2D = _whole_texture(species)
	var dir := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var pos: Vector2 = dir * _rng.randi_range(15000, 20000)
	var vel := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(1, 1000)
	var rot_rate := _rng.randf_range(-0.2, 0.2)
	rock.reset(species, SIZE_WHOLE, false, tex, _polygon_for_texture.get(tex, PackedVector2Array()),
			   SIZE_SCALES[SIZE_WHOLE], pos, vel, rot_rate, 100)
	_spawn_queue.append(rock)


# Roll species using the original game's distribution: 75% C, 17% S, 8% M.
func _random_species() -> String:
	var roll := _rng.randf_range(0.0, 1.0)
	if roll <= 0.75:
		return "C11"
	if roll <= 0.92:
		return "S11"
	return "M11"


func _whole_texture(species: String) -> Texture2D:
	return WHOLE_TEXTURES.get(species, WHOLE_TEXTURES["C11"])


# ----------------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------------

func _drain_spawn_queue() -> void:
	var budget: int = MAX_SPAWNS_PER_FRAME
	while budget > 0 and not _spawn_queue.is_empty():
		var rock = _spawn_queue.pop_front()
		add_child(rock)
		rock.start_grace_period()
		budget -= 1


func _on_asteroid_died(asteroid) -> void:
	# Earth impacts: rock is consumed by the planet; no dust, no fragments.
	# The impact explosion is already triggered in _on_earth_impact.
	if not asteroid.died_to_earth:
		_asteroids_destroyed += 1
		var vel: Vector2 = asteroid.asteroid_velocity if "asteroid_velocity" in asteroid else Vector2.ZERO
		_spawn_dust(asteroid.global_position, asteroid.size, vel)
		if asteroid.can_break:
			_fragment(asteroid)
	if asteroid.get_parent() == self:
		remove_child(asteroid)
	_return_to_pool(asteroid)


func _fragment(parent_rock) -> void:
	var recipe: Array = _break_recipes.get(parent_rock.species, [])
	var total_spawned: int = 0
	for spec in recipe:
		if total_spawned >= MAX_FRAGMENTS_PER_BREAK:
			break
		var size: int = spec.size
		var poly: PackedVector2Array = _polygon_for_texture.get(spec.texture, PackedVector2Array())
		var sprite_scale: float = SIZE_SCALES.get(size, 0.25)
		var count: int = _rng.randi_range(FRAGMENT_MULTIPLIER_MIN, FRAGMENT_MULTIPLIER_MAX)
		count = min(count, MAX_FRAGMENTS_PER_BREAK - total_spawned)
		for k in count:
			var frag := _take_from_pool()
			var pos: Vector2 = parent_rock.position + Vector2(
				_rng.randf_range(-break_position_jitter, break_position_jitter),
				_rng.randf_range(-break_position_jitter, break_position_jitter))
			var vj: float = _velocity_jitter(size)
			var vel: Vector2 = parent_rock.asteroid_velocity + Vector2(
				_rng.randf_range(-vj, vj),
				_rng.randf_range(-vj, vj))
			var rot_rate: float = parent_rock.rotation_rate + _rng.randf_range(-_rotation_jitter(size), _rotation_jitter(size))
			frag.reset(parent_rock.species, size, true, spec.texture, poly, sprite_scale,
					   pos, vel, rot_rate, _integrity_for_size(size))
			_spawn_queue.append(frag)
			total_spawned += 1


# ----------------------------------------------------------------------
# Dust cloud pool
# ----------------------------------------------------------------------

func _warm_dust_pool(count: int) -> void:
	for i in count:
		_dust_pool.push_back(_make_fresh_dust())


func _make_fresh_dust() -> Node:
	var d := DUST_SCENE.instantiate()
	add_child(d)
	return d


func _spawn_dust(at_pos: Vector2, parent_size: int, parent_velocity: Vector2) -> void:
	var count: int = DUST_COUNT_BY_SIZE.get(parent_size, 1)
	for i in count:
		var d = _dust_pool.pop_back() if not _dust_pool.is_empty() else _make_fresh_dust()
		_dust_in_use += 1
		if _dust_in_use > _dust_high_water:
			_dust_high_water = float(_dust_in_use)
		var jitter := Vector2(
			_rng.randf_range(-DUST_POSITION_JITTER, DUST_POSITION_JITTER),
			_rng.randf_range(-DUST_POSITION_JITTER, DUST_POSITION_JITTER))
		d.emit(at_pos + jitter, parent_velocity, Callable(self, "_return_dust"))


func _return_dust(d) -> void:
	_dust_in_use = max(0, _dust_in_use - 1)
	_dust_pool.push_back(d)


# ----------------------------------------------------------------------
# Adaptive pool sizing
# ----------------------------------------------------------------------
# High-water mark of concurrent in-use entries, with slow exponential decay so
# a one-time spike doesn't keep the pool inflated forever. Pools may grow
# unboundedly on demand; trimming runs once per second and removes a single
# excess idle entry per pool when the idle count exceeds high-water * slack.

func _decay_high_water(delta: float) -> void:
	var decay: float = 1.0 - HIGH_WATER_DECAY_PER_SEC * delta
	_asteroid_high_water = max(float(_asteroids_in_use), _asteroid_high_water * decay)
	_dust_high_water = max(float(_dust_in_use), _dust_high_water * decay)


func _trim_pools() -> void:
	_trim_pool(_pool, _asteroid_high_water, false)
	_trim_pool(_dust_pool, _dust_high_water, true)


func _trim_pool(pool: Array, high_water: float, free_node: bool) -> void:
	var cap: int = int(ceil(high_water * POOL_SLACK_FACTOR))
	if pool.size() <= cap:
		return
	var excess: Node = pool.pop_back()
	if free_node:
		excess.queue_free()
	else:
		excess.queue_free()


func _velocity_jitter(size: int) -> float:
	match size:
		SIZE_LARGE:  return 100.0
		SIZE_MEDIUM: return 200.0
		_:           return 300.0


func _rotation_jitter(size: int) -> float:
	match size:
		SIZE_LARGE:  return 0.05
		SIZE_MEDIUM: return 0.10
		_:           return 0.20


func _integrity_for_size(size: int) -> int:
	match size:
		SIZE_LARGE:  return 50
		SIZE_MEDIUM: return 40
		_:           return 20


# ----------------------------------------------------------------------
# Bookkeeping
# ----------------------------------------------------------------------

func _count_active_asteroids() -> int:
	var n := 0
	for c in get_children():
		if c.is_in_group("asteroid"):
			n += 1
	return n


func _count_whole_earth_threats() -> int:
	var n := 0
	for c in get_children():
		if c.is_in_group("asteroid") and "has_impact_fate" in c and c.has_impact_fate and c.size == SIZE_WHOLE:
			n += 1
	return n


func _cull_distant_and_report() -> void:
	var active := 0
	for c in get_children():
		if not c.is_in_group("asteroid"):
			continue
		if c.global_position.length() > maximum_asteroid_distance:
			remove_child(c)
			_return_to_pool(c)
		else:
			active += 1
	GlobalSignals.emit_signal("set_debug_display", "active: %d  pool: %d" % [active, _pool.size()])


# ----------------------------------------------------------------------
# Break recipe loading (once, at startup)
# ----------------------------------------------------------------------

func _build_break_recipes() -> void:
	for species in BREAK_DIRS:
		_break_recipes[species] = _scan_recipe(BREAK_DIRS[species])


func _scan_recipe(dir_path: String) -> Array:
	var recipe: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("AsteroidManager: missing fragment dir: %s" % dir_path)
		return recipe
	dir.list_dir_begin()
	while true:
		var fname := dir.get_next()
		if fname == "":
			break
		if fname.begins_with(".") or fname.ends_with(".import"):
			continue
		recipe.append({
			"size": _parse_size_from_filename(fname),
			"texture": load(dir_path + fname),
		})
	dir.list_dir_end()
	return recipe


func _parse_size_from_filename(fname: String) -> int:
	if "large" in fname:  return SIZE_LARGE
	if "medium" in fname: return SIZE_MEDIUM
	return SIZE_SMALL


# ----------------------------------------------------------------------
# Silhouette polygons (built once at startup)
# ----------------------------------------------------------------------
# For each unique texture used by asteroids (both whole-rock images and every
# fragment image referenced by a break recipe), trace the sprite's alpha
# silhouette into a polygon, scale it to the canonical size that texture will
# always be rendered at, and cache it. Reset() applies the cached polygon
# verbatim — no per-spawn computation.

func _build_polygon_cache() -> void:
	# Whole asteroids get accurate silhouette polygons (they're highly visible
	# and few in number).
	for species in WHOLE_TEXTURES:
		var tex: Texture2D = WHOLE_TEXTURES[species]
		if not _polygon_for_texture.has(tex):
			_polygon_for_texture[tex] = _silhouette_polygon(tex, SIZE_SCALES[SIZE_WHOLE])
	# Fragments get a cheap N-vertex bounding octagon (convex = no decomposition,
	# crucial when scores of fragments exist at once).
	for species in _break_recipes:
		for spec in _break_recipes[species]:
			var tex: Texture2D = spec.texture
			if not _polygon_for_texture.has(tex):
				_polygon_for_texture[tex] = _bounding_circle_polygon(tex,
					SIZE_SCALES.get(spec.size, 0.25), FRAGMENT_HULL_SIDES)


# Trace the opaque region of a texture into a single polygon, simplified by
# SILHOUETTE_EPSILON, centered on the texture midpoint, then pre-scaled to the
# given sprite scale so vertices are in the asteroid's local coords.
# Picks the largest connected region if the alpha produces multiple polygons.
func _silhouette_polygon(tex: Texture2D, sprite_scale: float) -> PackedVector2Array:
	if tex == null:
		return PackedVector2Array()
	var img: Image = tex.get_image()
	if img == null:
		push_warning("AsteroidManager: texture has no image; using empty polygon")
		return PackedVector2Array()
	var bm := BitMap.new()
	bm.create_from_image_alpha(img, SILHOUETTE_ALPHA_THRESHOLD)
	var rect := Rect2i(Vector2i.ZERO, img.get_size())
	var polys: Array = bm.opaque_to_polygons(rect, SILHOUETTE_EPSILON)
	if polys.is_empty():
		return PackedVector2Array()
	var best: PackedVector2Array = polys[0]
	var best_area: float = _polygon_area(best)
	for p in polys:
		var a: float = _polygon_area(p)
		if a > best_area:
			best = p
			best_area = a
	var center: Vector2 = Vector2(img.get_size()) * 0.5
	var out := PackedVector2Array()
	for v in best:
		out.append((v - center) * sprite_scale)
	return out


# Approximates the texture's silhouette with a regular N-gon bounding circle.
# Convex (so the physics server skips decomposition) and minimal vertices.
func _bounding_circle_polygon(tex: Texture2D, sprite_scale: float, sides: int) -> PackedVector2Array:
	if tex == null:
		return PackedVector2Array()
	# Use the silhouette's farthest vertex from center as the bounding radius,
	# so the octagon hugs the actual sprite rather than the texture rect.
	var sil: PackedVector2Array = _silhouette_polygon(tex, sprite_scale)
	if sil.is_empty():
		return PackedVector2Array()
	var r: float = 0.0
	for v in sil:
		r = max(r, v.length())
	var out := PackedVector2Array()
	for i in sides:
		var a: float = float(i) / float(sides) * TAU
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


# Shoelace formula. Returns absolute area in pixels squared.
func _polygon_area(poly: PackedVector2Array) -> float:
	var n: int = poly.size()
	if n < 3:
		return 0.0
	var s := 0.0
	for i in n:
		var p1: Vector2 = poly[i]
		var p2: Vector2 = poly[(i + 1) % n]
		s += p1.x * p2.y - p2.x * p1.y
	return abs(s) * 0.5


# ----------------------------------------------------------------------
# Stage phases + boss execution
# ----------------------------------------------------------------------

func _start_stage(idx: int) -> void:
	_stage_index = idx
	_phase = Phase.ACTIVE
	_phase_elapsed = 0.0
	_boss_queue = []
	_boss_started = false
	_boss_queue_empty_at = -1.0
	_shop_opened_this_respite = false
	_stage_deaths_start = _total_deaths
	var s: Dictionary = STAGES[idx]
	# Spread threat spawns evenly through the stage duration (after a small
	# warm-in so the first one doesn't land instantly).
	_threat_schedule.clear()
	for i in s.threats:
		var t: float = (float(i) + 0.5) / float(s.threats + 1) * s.duration
		_threat_schedule.append({"at": t})
	GlobalSignals.emit_signal("status_message",
		"Stage %d of %d — survive!" % [idx + 1, STAGES.size()])


func _advance_phase(delta: float) -> void:
	match _phase:
		Phase.ACTIVE:
			_phase_elapsed += delta
			_tick_threats()
			_tick_boss(delta)
		Phase.RESPITE:
			_phase_elapsed += delta
			_tick_respite(delta)
		Phase.WON, Phase.DEAD:
			pass


func _on_player_died() -> void:
	_phase = Phase.DEAD
	spawn_timer.stop()
	GlobalSignals.run_stage_reached = _stage_index + 1
	GlobalSignals.run_earth_casualties = _total_deaths
	GlobalSignals.run_asteroids_destroyed = _asteroids_destroyed
	GlobalSignals.reset_progress()


func _on_shop_departed() -> void:
	_has_docked_this_respite = true


func _tick_threats() -> void:
	while not _threat_schedule.is_empty() and _threat_schedule[0].at <= _phase_elapsed:
		_threat_schedule.pop_front()
		_spawn_threat_rock()
	# When stage duration elapses, hand off to the boss (if not already started).
	if not _boss_started and _phase_elapsed >= STAGES[_stage_index].duration:
		_boss_started = true
		_boss_queue = []
		for ev in BOSS_PATTERNS.get(STAGES[_stage_index].boss, []):
			# Copy so we can mutate the queue without touching the const.
			_boss_queue.append({"at": _phase_elapsed + ev.at, "fn": ev.fn, "args": ev.args})
		GlobalSignals.emit_signal("status_message",
			"BOSS: %s incoming" % STAGES[_stage_index].boss.capitalize().replace("_", " "))


func _tick_boss(_delta: float) -> void:
	if not _boss_started:
		return
	while not _boss_queue.is_empty() and _boss_queue[0].at <= _phase_elapsed:
		var ev = _boss_queue.pop_front()
		callv(ev.fn, ev.args)
	if not _boss_queue.is_empty():
		return
	# All boss events fired. Record when that happened.
	if _boss_queue_empty_at < 0.0:
		_boss_queue_empty_at = _phase_elapsed
	# Wait until whole rocks are cleared — either destroyed/impacted or past a
	# timeout. This prevents the dock prompt from appearing while threat rocks
	# are still in flight.
	var elapsed_since_clear: float = _phase_elapsed - _boss_queue_empty_at
	var wholes_gone: bool = _count_whole_earth_threats() == 0
	if wholes_gone or elapsed_since_clear >= WHOLE_CLEAR_TIMEOUT:
		_begin_respite()


func _boss_total_duration() -> float:
	var total := 0.0
	for ev in BOSS_PATTERNS.get(STAGES[_stage_index].boss, []):
		total = max(total, float(ev.at))
	return total


func _begin_respite() -> void:
	var stage_deaths: int = _total_deaths - _stage_deaths_start
	GlobalSignals.award_credits(_calculate_stage_credits(stage_deaths))
	if _stage_index + 1 >= STAGES.size():
		_phase = Phase.WON
		GlobalSignals.emit_signal("game_won")
		GlobalSignals.emit_signal("status_message", "Victory. Earth survived.")
		return
	_phase = Phase.RESPITE
	_phase_elapsed = 0.0
	_heal_accum_h = 0.0
	_heal_accum_s = 0.0
	_has_docked_this_respite = false
	_shop_opened_this_respite = false
	GlobalSignals.emit_signal("status_message", "Dock at the station for repairs and a rest.")


func _calculate_stage_credits(stage_deaths: int) -> int:
	var base: int = STAGES[_stage_index].base_credits
	var pct: float = 1.0
	for tier in CREDIT_TIERS:
		if stage_deaths >= tier.min_deaths:
			pct = tier.pct
	return int(base * pct)


func _tick_respite(_delta: float) -> void:
	var station = get_tree().get_first_node_in_group("station")
	var player = get_tree().get_first_node_in_group("player")
	if station == null or player == null:
		return
	var dist: float = player.global_position.distance_to(station.global_position)
	var near_station: bool = dist <= STATION_HEAL_RADIUS
	# Open the shop the first time the player reaches the station.
	if near_station and not _shop_opened_this_respite:
		_shop_opened_this_respite = true
		GlobalSignals.emit_signal("open_station_shop")
	# After the player has departed the shop and flown away, advance the stage.
	if _has_docked_this_respite and not near_station:
		_start_stage(_stage_index + 1)
		return
	if not _has_docked_this_respite:
		GlobalSignals.emit_signal("status_message", "Dock at the station for repairs and a rest.")
	else:
		GlobalSignals.emit_signal("status_message", "Leave when you're ready.")


func _heal_player(player, delta: float) -> void:
	_heal_accum_h += STATION_HEAL_RATE * delta
	_heal_accum_s += STATION_HEAL_RATE * delta
	var add_h: int = int(_heal_accum_h)
	var add_s: int = int(_heal_accum_s)
	if add_h > 0:
		var prev: int = player.health
		player.health = clamp(player.health + add_h, 0, player.max_health)
		_heal_accum_h -= add_h
		if player.health != prev:
			GlobalSignals.emit_signal("player_health_changed", player.health)
	if add_s > 0:
		var prev_s: int = player.shield
		player.shield = clamp(player.shield + add_s, 0, player.max_shield)
		_heal_accum_s -= add_s
		if player.shield != prev_s:
			GlobalSignals.emit_signal("player_shield_changed", player.shield)


# ----------------------------------------------------------------------
# Threat + boss spawn primitives
# ----------------------------------------------------------------------

func _spawn_threat_rock(velocity_mult: float = 1.0, position_override: Variant = null, size: int = SIZE_WHOLE) -> void:
	var earth = get_tree().get_first_node_in_group("earth")
	if earth == null:
		return
	var earth_pos: Vector2 = earth.global_position
	var dir: Vector2 = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var spawn_pos: Vector2 = earth_pos + dir * _rng.randf_range(15000, 20000)
	if position_override != null:
		spawn_pos = position_override
	# Aim straight at Earth with a small angular jitter so trajectories aren't
	# all dead-perpendicular (looks too on-rails).
	var to_earth: Vector2 = (earth_pos - spawn_pos).normalized()
	var jitter: float = _rng.randf_range(-0.1, 0.1)
	var vel: Vector2 = to_earth.rotated(jitter) * THREAT_BASE_SPEED * velocity_mult
	var rock := _take_from_pool()
	var species := _random_species()
	var tex: Texture2D = _whole_texture(species)
	rock.reset(species, size, false, tex,
			   _polygon_for_texture.get(tex, PackedVector2Array()),
			   SIZE_SCALES[size], spawn_pos, vel,
			   _rng.randf_range(-0.2, 0.2), 100)
	_spawn_queue.append(rock)


func _spawn_fastball() -> void:
	_spawn_threat_rock(FASTBALL_SPEED_MULT)


func _spawn_clump(count: int, big: bool) -> void:
	var earth = get_tree().get_first_node_in_group("earth")
	if earth == null:
		return
	var earth_pos: Vector2 = earth.global_position
	var dir: Vector2 = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var cluster_center: Vector2 = earth_pos + dir * _rng.randf_range(15000, 18000)
	for i in count:
		var offset: Vector2 = Vector2(
			_rng.randf_range(-CLUMP_SPACING, CLUMP_SPACING),
			_rng.randf_range(-CLUMP_SPACING, CLUMP_SPACING))
		_spawn_threat_rock(1.0 if big else 0.8, cluster_center + offset, SIZE_WHOLE)


# Vestigial: old timer connection in the .tscn still routes here. No-op now.
func _on_Stage_Timer_timeout() -> void:
	pass
