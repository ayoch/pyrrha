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
# Chance a fragment from a threat rock gets deflected off its Earth-course by
# the breakup — those fragments become harmless nuisance debris.
const FRAGMENT_DEFLECT_CHANCE := 0.4

# Per-type physical properties keyed by first character of species code (C/S/M).
# integrity_mult : toughness relative to baseline 100
# mass_mult      : density — affects kinetic damage to player and impact deaths
# death_mult     : lethality on Earth impact (denser = more penetrating)
# frag_max       : upper bound on FRAGMENT_MULTIPLIER_MAX for this type
const SPECIES_PROPS := {
	"C": {"integrity_mult": 0.6, "mass_mult": 0.8, "death_mult": 0.7, "frag_max": 20},
	"S": {"integrity_mult": 1.0, "mass_mult": 1.0, "death_mult": 1.0, "frag_max": 8},
	"M": {"integrity_mult": 1.6, "mass_mult": 1.5, "death_mult": 1.5, "frag_max": 4},
}

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
	# 1  — intro; one scheduled threat, simple fastball boss
	{"duration": 45.0,  "threats":  3, "boss": "fastball",            "base_credits": 150, "max_threats": 2, "sleeper_chance": 0.00, "sleeper2_chance": 0.00, "blocker_chance": 0.00, "off_radar_chance": 0.00},
	# 2  — settle in; same shape, nothing new
	{"duration": 50.0,  "threats":  3, "boss": "fastball",            "base_credits": 175, "max_threats": 2, "sleeper_chance": 0.00, "sleeper2_chance": 0.00, "blocker_chance": 0.00, "off_radar_chance": 0.00},
	# 3  — threats: 4; boss: double_fastball
	{"duration": 50.0,  "threats":  4, "boss": "double_fastball",     "base_credits": 200, "max_threats": 2, "sleeper_chance": 0.00, "sleeper2_chance": 0.00, "blocker_chance": 0.00, "off_radar_chance": 0.00},
	# 4  — new: off-radar rocks (don't show on minimap)
	{"duration": 55.0,  "threats":  4, "boss": "double_fastball",     "base_credits": 220, "max_threats": 2, "sleeper_chance": 0.00, "sleeper2_chance": 0.00, "blocker_chance": 0.00, "off_radar_chance": 0.03},
	# 5  — max_threats: 3 (first multi-rock volley)
	{"duration": 55.0,  "threats":  5, "boss": "double_fastball",     "base_credits": 240, "max_threats": 3, "sleeper_chance": 0.00, "sleeper2_chance": 0.00, "blocker_chance": 0.00, "off_radar_chance": 0.04},
	# 6  — threats: 5
	{"duration": 60.0,  "threats":  5, "boss": "double_fastball",     "base_credits": 260, "max_threats": 3, "sleeper_chance": 0.00, "sleeper2_chance": 0.00, "blocker_chance": 0.00, "off_radar_chance": 0.05},
	# 7  — new: clump boss (random formation: cluster / line / semicircle)
	{"duration": 60.0,  "threats":  6, "boss": "clump_4",             "base_credits": 280, "max_threats": 3, "sleeper_chance": 0.00, "sleeper2_chance": 0.00, "blocker_chance": 0.00, "off_radar_chance": 0.06},
	# 8  — new: blocker rocks (interpose between player and threats)
	{"duration": 65.0,  "threats":  6, "boss": "clump_4",             "base_credits": 300, "max_threats": 3, "sleeper_chance": 0.00, "sleeper2_chance": 0.00, "blocker_chance": 0.05, "off_radar_chance": 0.06},
	# 9  — threats: 7
	{"duration": 65.0,  "threats":  7, "boss": "clump_4",             "base_credits": 325, "max_threats": 3, "sleeper_chance": 0.00, "sleeper2_chance": 0.00, "blocker_chance": 0.06, "off_radar_chance": 0.07},
	# 10 — max_threats: 4
	{"duration": 70.0,  "threats":  7, "boss": "clump_4",             "base_credits": 350, "max_threats": 4, "sleeper_chance": 0.00, "sleeper2_chance": 0.00, "blocker_chance": 0.07, "off_radar_chance": 0.07},
	# 11 — new: Type-1 sleeper rocks (dormant; wake and chase the player)
	{"duration": 70.0,  "threats":  8, "boss": "clump_4_plus_fastball","base_credits": 375, "max_threats": 4, "sleeper_chance": 0.25, "sleeper2_chance": 0.00, "blocker_chance": 0.07, "off_radar_chance": 0.08},
	# 12 — threats: 8
	{"duration": 75.0,  "threats":  8, "boss": "clump_4",             "base_credits": 400, "max_threats": 4, "sleeper_chance": 0.35, "sleeper2_chance": 0.00, "blocker_chance": 0.08, "off_radar_chance": 0.08},
	# 13 — boss steps up to clump + trailing fastball
	{"duration": 75.0,  "threats":  9, "boss": "clump_4_plus_fastball","base_credits": 425, "max_threats": 4, "sleeper_chance": 0.45, "sleeper2_chance": 0.00, "blocker_chance": 0.09, "off_radar_chance": 0.09},
	# 14 — max_threats: 5
	{"duration": 80.0,  "threats":  9, "boss": "clump_4_plus_fastball","base_credits": 450, "max_threats": 5, "sleeper_chance": 0.50, "sleeper2_chance": 0.00, "blocker_chance": 0.09, "off_radar_chance": 0.09},
	# 15 — new: split-volley boss (simultaneous volleys from opposite sides)
	{"duration": 80.0,  "threats": 10, "boss": "split_volley",        "base_credits": 475, "max_threats": 5, "sleeper_chance": 0.55, "sleeper2_chance": 0.00, "blocker_chance": 0.10, "off_radar_chance": 0.10},
	# 16 — new: Type-2 sleeper rocks (fuse timer; wake and aim at Earth)
	{"duration": 85.0,  "threats": 10, "boss": "split_volley",        "base_credits": 500, "max_threats": 5, "sleeper_chance": 0.60, "sleeper2_chance": 0.03, "blocker_chance": 0.10, "off_radar_chance": 0.10},
	# 17 — max_threats: 6
	{"duration": 85.0,  "threats": 11, "boss": "split_volley",        "base_credits": 525, "max_threats": 6, "sleeper_chance": 0.65, "sleeper2_chance": 0.04, "blocker_chance": 0.11, "off_radar_chance": 0.11},
	# 18 — new: clump-6 boss; threats: 11
	{"duration": 90.0,  "threats": 11, "boss": "clump_6",             "base_credits": 550, "max_threats": 6, "sleeper_chance": 0.70, "sleeper2_chance": 0.05, "blocker_chance": 0.11, "off_radar_chance": 0.11},
	# 19 — alternating between heavy bosses
	{"duration": 90.0,  "threats": 12, "boss": "split_volley",        "base_credits": 575, "max_threats": 6, "sleeper_chance": 0.70, "sleeper2_chance": 0.06, "blocker_chance": 0.12, "off_radar_chance": 0.12},
	# 20 — new: finale boss (clump-6 + fastball); threats: 12
	{"duration": 90.0,  "threats": 12, "boss": "finale",              "base_credits": 600, "max_threats": 6, "sleeper_chance": 0.75, "sleeper2_chance": 0.07, "blocker_chance": 0.12, "off_radar_chance": 0.12},
	# 21 — max_threats: 7
	{"duration": 95.0,  "threats": 12, "boss": "clump_6",             "base_credits": 625, "max_threats": 7, "sleeper_chance": 0.75, "sleeper2_chance": 0.07, "blocker_chance": 0.13, "off_radar_chance": 0.12},
	# 22 — threats: 13
	{"duration": 95.0,  "threats": 13, "boss": "split_volley",        "base_credits": 650, "max_threats": 7, "sleeper_chance": 0.80, "sleeper2_chance": 0.08, "blocker_chance": 0.13, "off_radar_chance": 0.13},
	# 23 — sustained pressure
	{"duration": 100.0, "threats": 13, "boss": "finale",              "base_credits": 675, "max_threats": 7, "sleeper_chance": 0.80, "sleeper2_chance": 0.09, "blocker_chance": 0.14, "off_radar_chance": 0.13},
	# 24 — threats: 14
	{"duration": 100.0, "threats": 14, "boss": "clump_6",             "base_credits": 700, "max_threats": 7, "sleeper_chance": 0.80, "sleeper2_chance": 0.09, "blocker_chance": 0.14, "off_radar_chance": 0.14},
	# 25 — max_threats: 8
	{"duration": 100.0, "threats": 14, "boss": "finale",              "base_credits": 725, "max_threats": 8, "sleeper_chance": 0.85, "sleeper2_chance": 0.10, "blocker_chance": 0.15, "off_radar_chance": 0.14},
	# 26 — threats: 14
	{"duration": 105.0, "threats": 14, "boss": "split_volley",        "base_credits": 750, "max_threats": 8, "sleeper_chance": 0.85, "sleeper2_chance": 0.11, "blocker_chance": 0.15, "off_radar_chance": 0.14},
	# 27 — high, sustained pressure
	{"duration": 105.0, "threats": 15, "boss": "finale",              "base_credits": 775, "max_threats": 8, "sleeper_chance": 0.85, "sleeper2_chance": 0.12, "blocker_chance": 0.15, "off_radar_chance": 0.15},
	# 28 — threats: 15
	{"duration": 110.0, "threats": 15, "boss": "clump_6",             "base_credits": 800, "max_threats": 8, "sleeper_chance": 0.90, "sleeper2_chance": 0.12, "blocker_chance": 0.15, "off_radar_chance": 0.15},
	# 29 — threats: 16; max_threats: 9
	{"duration": 110.0, "threats": 16, "boss": "split_volley",        "base_credits": 825, "max_threats": 9, "sleeper_chance": 0.90, "sleeper2_chance": 0.12, "blocker_chance": 0.15, "off_radar_chance": 0.15},
	# 30 — final stage
	{"duration": 120.0, "threats": 16, "boss": "finale",              "base_credits": 900, "max_threats": 9, "sleeper_chance": 0.90, "sleeper2_chance": 0.12, "blocker_chance": 0.15, "off_radar_chance": 0.15},
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
	"clump_4": [
		{"at": 0.0, "fn": "_spawn_random_clump", "args": [4]},
	],
	"clump_4_plus_fastball": [
		{"at": 0.0, "fn": "_spawn_random_clump", "args": [4]},
		{"at": 2.0, "fn": "_spawn_fastball", "args": []},
	],
	"clump_6": [
		{"at": 0.0, "fn": "_spawn_random_clump", "args": [6]},
	],
	"split_volley": [
		{"at": 0.0, "fn": "_spawn_split_volley", "args": [3]},
	],
	"finale": [
		{"at": 0.0, "fn": "_spawn_random_clump", "args": [6]},
		{"at": 2.0, "fn": "_spawn_fastball", "args": []},
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
# Threat rocks waiting for a slot under the stage's max_threats cap. Each entry
# is a Dictionary {velocity_mult, position_override, size}.
var _threat_backlog: Array = []
# Sleeper spawn schedule for the current stage. Each entry is just {at: float}.
var _sleeper_schedule: Array = []
const WHOLE_CLEAR_TIMEOUT := 25.0        # fallback: enter respite even if whole rocks remain
var _heal_accum_h: float = 0.0
var _heal_accum_s: float = 0.0
var _has_docked_this_respite: bool = false

# Casualty log — every Earth impact gets a row. Cap to keep memory bounded.
# CasualtyReport reads from this via group lookup.
const CASUALTY_LOG_CAP := 500
var _casualty_log: Array = []
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
# Floor deaths per size — even an ocean impact causes tsunamis, pressure waves,
# flooding. Also the fallback when Earth's texture image can't be sampled.
const MIN_DEATHS_FOR_SIZE := {
	4: 50_000,
	3: 5_000,
	2: 2_500,
	1: 0,
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
	add_to_group("asteroid_manager")
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
		# A rock on a collision course WILL hit Earth — the same test the minimap
		# uses to paint it red, so "shown as a threat" and "can hit Earth" are one
		# and the same. Only deflected/harmless fragments pass through; nuisance
		# wholes are steered clear of Earth at spawn (see _queue_whole_asteroid),
		# so the threat count stays exactly what the threat system deliberately aims.
		if "is_fragment" in c and c.is_fragment and not c.is_threat:
			continue
		# Assign impact fate the first time a rock qualifies as a threat. The
		# impact point is random along the chord the trajectory cuts through
		# Earth's disk — the rock travels along its course, dying at that point.
		if not c.has_impact_fate:
			if _is_on_collision_course_world(c.global_position, c.asteroid_velocity, earth_pos, earth_radius):
				var ip = _compute_random_impact_point(c.global_position, c.asteroid_velocity, earth_pos, earth_radius)
				if ip != null:
					c.impact_point = ip
					c.impact_deaths = _sample_deaths(ip, c.size, c.species)
					c.has_impact_fate = true
					GlobalSignals.threat_inbound.emit(c.size)
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
	GlobalSignals.earth_impact.emit(asteroid.impact_deaths, asteroid.size, _stage_index,
		("is_threat" in asteroid and asteroid.is_threat))
	# Log every impact (even 0-death ocean strikes) so the casualty report
	# shows the full picture of what's hitting Earth.
	_casualty_log.append({
		"time_ms": Time.get_ticks_msec(),
		"size": asteroid.size,
		"pos": asteroid.impact_point,
		"deaths": asteroid.impact_deaths,
		"is_threat": ("is_threat" in asteroid and asteroid.is_threat),
		"is_sleeper": ("is_sleeper" in asteroid and asteroid.is_sleeper),
		"species": (asteroid.species if "species" in asteroid else "?"),
		"stage": _stage_index + 1,
	})
	if _casualty_log.size() > CASUALTY_LOG_CAP:
		_casualty_log.pop_front()
	if stage != null:
		stage.spawn_explosion(asteroid.impact_point, EXPLOSION_SCALE_FOR_SIZE.get(asteroid.size, 0.3))
	asteroid.died_to_earth = true   # tells _on_asteroid_died to skip dust + fragmentation
	asteroid.integrity = -1         # asteroid will report its own death next physics tick


# Extra clearance beyond Earth's angular radius for nuisance headings.
const NUISANCE_EARTH_MARGIN_DEG := 8.0


# Nudge a heading so it sits at least (Earth's angular radius + margin) off the
# bearing to Earth — a rock launched along the result cannot be on a collision
# course. Keeps nuisance spawns from ever becoming real threats.
func _heading_clear_of_earth(dir: Vector2, from_pos: Vector2, earth_pos: Vector2, earth_radius: float) -> Vector2:
	var to_earth: Vector2 = earth_pos - from_pos
	var dist: float = to_earth.length()
	if dist <= earth_radius:
		return dir
	var bearing: float = to_earth.angle()
	var half: float = asin(clampf(earth_radius / dist, 0.0, 1.0)) + deg_to_rad(NUISANCE_EARTH_MARGIN_DEG)
	var delta: float = wrapf(dir.angle() - bearing, -PI, PI)
	if absf(delta) >= half:
		return dir
	var side: float = 1.0 if delta >= 0.0 else -1.0
	return Vector2.from_angle(bearing + side * half)


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


func _sample_deaths(impact_world_pos: Vector2, size: int, species: String = "S11") -> int:
	var min_deaths: int = MIN_DEATHS_FOR_SIZE.get(size, 0)
	if _earth_image == null:
		return min_deaths
	var earth = get_tree().get_first_node_in_group("earth")
	if earth == null:
		return min_deaths
	# Convert world impact position to a pixel in Earth's texture.
	var offset: Vector2 = impact_world_pos - earth.global_position
	var img_size: Vector2 = Vector2(_earth_image.get_size())
	var px: Vector2 = img_size * 0.5 + offset / _earth_image_scale
	if px.x < 0 or px.x >= img_size.x or px.y < 0 or px.y >= img_size.y:
		return min_deaths
	var color: Color = _earth_image.get_pixel(int(px.x), int(px.y))
	if color.a < 0.1:
		return min_deaths   # outside Earth's disk
	# Land vs ocean heuristic. Ocean still kills (tsunamis) but far fewer.
	var land_factor: float = clamp((color.r + color.g) * 0.5 - color.b, 0.0, 1.0)
	if land_factor < 0.05:
		return min_deaths
	# Noise gives density variation within land.
	var noise_val: float = _density_noise.get_noise_2dv(px) * 0.5 + 0.5
	var size_mult: float = float(SIZE_DEATH_SCALE.get(size, 0.0))
	var death_mult: float = float(_props(species).death_mult)
	var jitter: float = _rng.randf_range(0.65, 1.45)
	return max(int(land_factor * noise_val * MAX_DEATHS_PER_IMPACT * size_mult * death_mult * jitter), min_deaths)


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
	# Regular waves only during the ACTIVE phase BEFORE the boss starts. Once
	# the boss is firing, no new nuisance rocks — otherwise random spawns can
	# keep rolling onto Earth-collision trajectories and the clear-wait phase
	# never ends.
	if _phase == Phase.ACTIVE and not _boss_started:
		var room := maximum_number_asteroids - _count_active_asteroids()
		if room > 0:
			var wave_size: int = min(_rng.randi_range(1, 16), room)
			for i in wave_size:
				_queue_whole_asteroid(_random_species())
		var s: Dictionary = STAGES[_stage_index]
		if _rng.randf() < s.get("sleeper2_chance", 0.0):
			_spawn_sleeper_type2()
		if _rng.randf() < s.get("blocker_chance", 0.0):
			_spawn_blocker()
		if _rng.randf() < s.get("off_radar_chance", 0.0):
			_queue_off_radar_asteroid(_random_species())
	_start_spawn_timer()


func _queue_whole_asteroid(species: String) -> void:
	var rock := _take_from_pool()
	var tex: Texture2D = _whole_texture(species)
	var dir := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var pos: Vector2 = dir * _rng.randi_range(15000, 20000)
	# Nuisance rocks must never be on an Earth-collision course: under the unified
	# threat model any rock that is on one WILL hit Earth. Steer the heading
	# deterministically clear of Earth's disk (with margin) so the threat count
	# stays exactly what the threat system deliberately aims at the planet.
	var vel_dir := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var earth: Node = get_tree().get_first_node_in_group("earth")
	if earth != null:
		var earth_pos: Vector2 = (earth as Node2D).global_position
		var earth_r: float = _node_visual_radius(earth)
		if earth_r > 0.0:
			vel_dir = _heading_clear_of_earth(vel_dir, pos, earth_pos, earth_r)
	var vel := vel_dir * _rng.randf_range(1, 1000)
	var rot_rate := _rng.randf_range(-0.2, 0.2)
	var props: Dictionary = _props(species)
	rock.reset(species, SIZE_WHOLE, false, tex, _polygon_for_texture.get(tex, PackedVector2Array()),
			   SIZE_SCALES[SIZE_WHOLE], pos, vel, rot_rate, int(100 * props.integrity_mult))
	rock.mass *= props.mass_mult
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


func _props(species: String) -> Dictionary:
	return SPECIES_PROPS.get(species.left(1), SPECIES_PROPS["S"])


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
	var props: Dictionary = _props(parent_rock.species)
	var total_spawned: int = 0
	var frag_cap: int = props.frag_max
	for spec in recipe:
		if total_spawned >= frag_cap:
			break
		var size: int = spec.size
		var poly: PackedVector2Array = _polygon_for_texture.get(spec.texture, PackedVector2Array())
		var sprite_scale: float = SIZE_SCALES.get(size, 0.25)
		var count: int = _rng.randi_range(FRAGMENT_MULTIPLIER_MIN, props.frag_max)
		count = min(count, frag_cap - total_spawned)
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
					   pos, vel, rot_rate, int(_integrity_for_size(size) * props.integrity_mult))
			frag.mass *= props.mass_mult
			frag.is_threat = parent_rock.is_threat and _rng.randf() >= FRAGMENT_DEFLECT_CHANCE
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
	# Rarely, a whole rock leaves one large ghost wisp that drifts away slowly.
	if parent_size == SIZE_WHOLE and _rng.randf() < 0.20:
		var g = _dust_pool.pop_back() if not _dust_pool.is_empty() else _make_fresh_dust()
		_dust_in_use += 1
		if _dust_in_use > _dust_high_water:
			_dust_high_water = float(_dust_in_use)
		g.emit_ghost(at_pos, Callable(self, "_return_dust"))


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


func _count_earth_threats() -> int:
	var n: int = 0
	for c in get_children():
		if c.is_in_group("asteroid") and c.is_threat:
			n += 1
	return n


func _any_rocks_threatening_earth() -> bool:
	# ANY rock currently on a collision course with Earth counts — not just
	# `is_threat` ones. Nuisance rocks (random spawns that happen to be aimed
	# at Earth) still need to be dealt with before respite can begin.
	for c in get_children():
		if not c.is_in_group("asteroid"):
			continue
		if "has_impact_fate" in c and c.has_impact_fate:
			return true
	return false


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
	_threat_backlog.clear()
	_shop_opened_this_respite = false
	_stage_deaths_start = _total_deaths
	var s: Dictionary = STAGES[idx]
	# Spread threat spawns evenly through the stage duration (after a small
	# warm-in so the first one doesn't land instantly).
	_threat_schedule.clear()
	for i in s.threats:
		var t: float = (float(i) + 0.5) / float(s.threats + 1) * s.duration
		_threat_schedule.append({"at": t})
	# Sleepers: stage 1 always gets one (so the player encounters them at least
	# once for diagnostic/learning). Later stages use sleeper_chance to roll one
	# at a random point in the stage.
	_sleeper_schedule.clear()
	if idx == 0:
		_sleeper_schedule.append({"at": 5.0})
	elif s.get("sleeper_chance", 0.0) > 0.0 and _rng.randf() < s.sleeper_chance:
		_sleeper_schedule.append({"at": _rng.randf_range(0.2, 0.7) * s.duration})
	GlobalSignals.emit_signal("status_message",
		"Stage %d of %d — survive!" % [idx + 1, STAGES.size()])
	GlobalSignals.stage_started.emit(idx)


func _advance_phase(delta: float) -> void:
	match _phase:
		Phase.ACTIVE:
			_phase_elapsed += delta
			_tick_threats()
			_drain_threat_backlog()
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
		_threat_backlog.append({"velocity_mult": 1.0, "position_override": null, "size": SIZE_WHOLE})
	while not _sleeper_schedule.is_empty() and _sleeper_schedule[0].at <= _phase_elapsed:
		_sleeper_schedule.pop_front()
		_spawn_sleeper()
	# When stage duration elapses, hand off to the boss (if not already started).
	if not _boss_started and _phase_elapsed >= STAGES[_stage_index].duration:
		_boss_started = true
		_boss_queue = []
		for ev in BOSS_PATTERNS.get(STAGES[_stage_index].boss, []):
			# Copy so we can mutate the queue without touching the const.
			_boss_queue.append({"at": _phase_elapsed + ev.at, "fn": ev.fn, "args": ev.args})
		GlobalSignals.emit_signal("status_message",
			"BOSS: %s incoming" % STAGES[_stage_index].boss.capitalize().replace("_", " "))
		GlobalSignals.boss_started.emit(_stage_index, STAGES[_stage_index].boss)


func _tick_boss(_delta: float) -> void:
	if not _boss_started:
		return
	while not _boss_queue.is_empty() and _boss_queue[0].at <= _phase_elapsed:
		var ev = _boss_queue.pop_front()
		callv(ev.fn, ev.args)
	if not _boss_queue.is_empty():
		return
	# All boss events fired. Don't start the clear timer until both the threat
	# backlog and spawn queue have drained — otherwise checking threats on the
	# same frame they're queued would see an empty field and trigger respite.
	if not _threat_backlog.is_empty() or not _spawn_queue.is_empty():
		return
	if _boss_queue_empty_at < 0.0:
		_boss_queue_empty_at = _phase_elapsed
	# Strict: do not enter respite until every rock with a collision fate is
	# off the board. No fallback timeout — the user explicitly wants the
	# stage-end message to wait until there are genuinely no incoming threats.
	if not _any_rocks_threatening_earth():
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
	GlobalSignals.respite_started.emit(_stage_index)


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
	var props: Dictionary = _props(species)
	rock.reset(species, size, false, tex,
			   _polygon_for_texture.get(tex, PackedVector2Array()),
			   SIZE_SCALES[size], spawn_pos, vel,
			   _rng.randf_range(-0.2, 0.2), int(100 * props.integrity_mult))
	rock.mass *= props.mass_mult
	rock.is_threat = true
	_spawn_queue.append(rock)


func _spawn_fastball() -> void:
	_threat_backlog.append({"velocity_mult": FASTBALL_SPEED_MULT, "position_override": null, "size": SIZE_WHOLE})


# Type 1 sleeper: stationary, tinted red. Spawns just outside the player's
# activation radius so they can see it sneak up. When the player closes within
# SLEEPER_ACTIVATE_RADIUS (set in Asteroid.gd), it wakes and chases.
func _spawn_sleeper() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var rock := _take_from_pool()
	var species := _random_species()
	var tex: Texture2D = _whole_texture(species)
	# Place ~2800 units from the player — just outside the wake radius so it's
	# visible but doesn't trigger immediately.
	var angle: float = _rng.randf() * TAU
	var spawn_pos: Vector2 = player.global_position + Vector2(cos(angle), sin(angle)) * 2800.0
	rock.reset(species, SIZE_WHOLE, false, tex,
			   _polygon_for_texture.get(tex, PackedVector2Array()),
			   SIZE_SCALES[SIZE_WHOLE], spawn_pos, Vector2.ZERO,
			   _rng.randf_range(-0.1, 0.1), 100)
	rock.is_sleeper = true
	rock.modulate = Asteroid.SLEEPER_TINT
	_spawn_queue.append(rock)


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
		_threat_backlog.append({"velocity_mult": 1.0 if big else 0.8, "position_override": cluster_center + offset, "size": SIZE_WHOLE})


func _spawn_random_clump(count: int) -> void:
	match _rng.randi() % 3:
		0: _spawn_clump(count, count > 4)
		1: _spawn_line(count)
		2: _spawn_semicircle(count)


func _spawn_split_volley(count_per_side: int) -> void:
	var earth: Node = get_tree().get_first_node_in_group("earth")
	if earth == null:
		return
	var earth_pos: Vector2 = earth.global_position
	var dir: Vector2 = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var dist: float = _rng.randf_range(15000, 18000)
	for side in [1, -1]:
		var center: Vector2 = earth_pos + dir * dist * side
		for i in count_per_side:
			var offset: Vector2 = Vector2(
				_rng.randf_range(-CLUMP_SPACING, CLUMP_SPACING),
				_rng.randf_range(-CLUMP_SPACING, CLUMP_SPACING))
			_threat_backlog.append({"velocity_mult": 1.0, "position_override": center + offset, "size": SIZE_WHOLE})


# Rocks spaced evenly along a line perpendicular to the Earth-facing direction,
# so they arrive as a wall rather than a cluster.
func _spawn_line(count: int) -> void:
	var earth: Node = get_tree().get_first_node_in_group("earth")
	if earth == null:
		return
	var earth_pos: Vector2 = earth.global_position
	var dir: Vector2 = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var cluster_center: Vector2 = earth_pos + dir * _rng.randf_range(15000, 18000)
	var perp: Vector2 = dir.rotated(PI * 0.5)
	for i in count:
		var t: float = (float(i) - float(count - 1) * 0.5) * CLUMP_SPACING
		_threat_backlog.append({"velocity_mult": 0.9, "position_override": cluster_center + perp * t, "size": SIZE_WHOLE})


# Rocks arranged on a semicircular arc whose convex (outer) edge points toward
# Earth — the arc bows at Earth like a cupped hand. All rocks aim straight in.
func _spawn_semicircle(count: int) -> void:
	var earth: Node = get_tree().get_first_node_in_group("earth")
	if earth == null:
		return
	var earth_pos: Vector2 = earth.global_position
	var dir: Vector2 = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var cluster_center: Vector2 = earth_pos + dir * _rng.randf_range(15000, 18000)
	var to_earth: Vector2 = (earth_pos - cluster_center).normalized()
	var arc_radius: float = CLUMP_SPACING * max(count - 1, 1) / PI
	for i in count:
		var frac: float = float(i) / float(max(count - 1, 1))
		var angle: float = lerp(-PI * 0.5, PI * 0.5, frac)
		var offset: Vector2 = to_earth.rotated(angle) * arc_radius
		_threat_backlog.append({"velocity_mult": 0.9, "position_override": cluster_center + offset, "size": SIZE_WHOLE})


func _spawn_sleeper_type2() -> void:
	var rock := _take_from_pool()
	var species: String = _random_species()
	var tex: Texture2D = _whole_texture(species)
	var dir := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var pos: Vector2 = dir * _rng.randi_range(10000, 16000)
	var vel: Vector2 = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(10, 80)
	var props: Dictionary = _props(species)
	rock.reset(species, SIZE_WHOLE, false, tex,
			   _polygon_for_texture.get(tex, PackedVector2Array()),
			   SIZE_SCALES[SIZE_WHOLE], pos, vel,
			   _rng.randf_range(-0.1, 0.1), int(100 * props.integrity_mult))
	rock.mass *= props.mass_mult
	rock.is_sleeper = true
	rock.sleeper_target_earth = true
	rock.sleeper_fuse = _rng.randf_range(30.0, 90.0)
	_spawn_queue.append(rock)


func _spawn_blocker() -> void:
	var rock := _take_from_pool()
	var species: String = _random_species()
	var tex: Texture2D = _whole_texture(species)
	var dir := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var pos: Vector2 = dir * _rng.randi_range(8000, 14000)
	var vel: Vector2 = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(10, 60)
	var props: Dictionary = _props(species)
	rock.reset(species, SIZE_WHOLE, false, tex,
			   _polygon_for_texture.get(tex, PackedVector2Array()),
			   SIZE_SCALES[SIZE_WHOLE], pos, vel,
			   _rng.randf_range(-0.1, 0.1), int(100 * props.integrity_mult))
	rock.mass *= props.mass_mult
	rock.is_blocker = true
	_spawn_queue.append(rock)


func _queue_off_radar_asteroid(species: String) -> void:
	var rock := _take_from_pool()
	var tex: Texture2D = _whole_texture(species)
	var dir := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var pos: Vector2 = dir * _rng.randi_range(15000, 20000)
	var vel_dir := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var earth: Node = get_tree().get_first_node_in_group("earth")
	if earth != null:
		var earth_pos: Vector2 = (earth as Node2D).global_position
		var earth_r: float = _node_visual_radius(earth)
		if earth_r > 0.0:
			for _i in 10:
				if not _is_on_collision_course_world(pos, vel_dir, earth_pos, earth_r):
					break
				vel_dir = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var vel: Vector2 = vel_dir * _rng.randf_range(1, 1000)
	var props: Dictionary = _props(species)
	rock.reset(species, SIZE_WHOLE, false, tex,
			   _polygon_for_texture.get(tex, PackedVector2Array()),
			   SIZE_SCALES[SIZE_WHOLE], pos, vel,
			   _rng.randf_range(-0.2, 0.2), int(100 * props.integrity_mult))
	rock.mass *= props.mass_mult
	rock.is_off_radar = true
	_spawn_queue.append(rock)


# Fire a full volley from the backlog, but only when the field is clear.
# Holds until all live threat rocks are gone, then dumps up to max_threats at once.
func _drain_threat_backlog() -> void:
	if _threat_backlog.is_empty():
		return
	if _count_earth_threats() > 0:
		return
	var cap: int = STAGES[_stage_index].max_threats
	var to_fire: int = min(_threat_backlog.size(), cap)
	for i in to_fire:
		var entry: Dictionary = _threat_backlog.pop_front()
		_spawn_threat_rock(entry.velocity_mult, entry.position_override, entry.size)


# Vestigial: old timer connection in the .tscn still routes here. No-op now.
func _on_Stage_Timer_timeout() -> void:
	pass
