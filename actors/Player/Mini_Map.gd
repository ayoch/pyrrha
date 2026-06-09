extends Node2D

const SHIP_TEX: Texture2D = preload("res://assets/ship.png")
const ASTEROID_TEX: Texture2D = preload("res://asteroids/Chondrite/C1/C1lowres.png")
const EARTH_TEX: Texture2D = preload("res://assets/earth.png")
const MOON_TEX: Texture2D = preload("res://assets/moon.png")
const STATION_TEX: Texture2D = preload("res://assets/space_station.png")

@export var detection_radius: float = 20000.0
@export var display_radius_px: float = 130.0  # how big the minimap is in screen px
@export var asteroid_sprite_scale: float = 0.5
@export var update_hz: float = 4.0  # how many times per second the minimap refreshes
@export var background_color: Color = Color(0.85, 0.85, 0.9, 0.35)
@export var border_color: Color = Color(0.95, 0.95, 1.0, 0.6)
@export var border_width: float = 1.5
@export var threat_color: Color = Color(1.0, 0.2, 0.2, 0.9)
@export var threat_marker_radius_px: float = 7.0
@export var threat_line_width: float = 1.5

@onready var player_sprite: Sprite2D = $player
@onready var earth_sprite: Sprite2D = $earth

const ThreatOverlayScript: Script = preload("res://actors/Player/MinimapThreatOverlay.gd")

var _conversion: float
var _asteroid_pool: Array = []
var _accum: float = 0.0
var _moon_sprite: Sprite2D
var _station_sprite: Sprite2D
var _threat_overlay: Node2D
# Threat entries built per-refresh and handed to the overlay for drawing.
# {"has_line": bool, "p1": Vector2, "p2": Vector2, "has_marker": bool, "marker": Vector2}
var _threats: Array = []
var _has_threats: bool = false
var _blink_phase: float = 0.0
# Threat trajectory line extends this far along the velocity vector in each
# direction (in minimap pixels). The line is then clipped to the minimap circle.
@export var threat_line_extent_px: float = 400.0
@export var threat_blink_hz: float = 2.0
@export var threat_blink_color: Color = Color(1.0, 0.15, 0.15, 0.95)


func _ready() -> void:
	_conversion = display_radius_px / detection_radius
	# Existing tscn has many pre-made asteroid Sprite2Ds; reuse them as pool.
	for child in get_children():
		if child == player_sprite or child == earth_sprite:
			continue
		if child is Sprite2D and child.name.begins_with("asteroid"):
			child.visible = false
			child.texture = ASTEROID_TEX
			child.scale = Vector2(asteroid_sprite_scale, asteroid_sprite_scale)
			_asteroid_pool.append(child)
	# Player marker.
	player_sprite.texture = SHIP_TEX
	player_sprite.scale = Vector2(0.05, 0.05)
	player_sprite.visible = false
	# Earth marker (re-skin to new asset).
	earth_sprite.texture = EARTH_TEX
	earth_sprite.scale = Vector2(0.05, 0.05)
	earth_sprite.visible = false
	# Moon sprite added at runtime.
	_moon_sprite = Sprite2D.new()
	_moon_sprite.texture = MOON_TEX
	_moon_sprite.scale = Vector2(0.05, 0.05)
	_moon_sprite.visible = false
	add_child(_moon_sprite)
	# Station sprite added at runtime.
	_station_sprite = Sprite2D.new()
	_station_sprite.texture = STATION_TEX
	_station_sprite.scale = Vector2(0.015, 0.015)
	_station_sprite.visible = false
	add_child(_station_sprite)
	# Threat overlay: added LAST so its _draw runs after every sibling sprite.
	# Lives outside the parent's transform-as-position by also using top_levewwl
	# would lose the local-space drawing; default is correct here.
	_threat_overlay = Node2D.new()
	_threat_overlay.set_script(ThreatOverlayScript)
	_threat_overlay.line_color = threat_color
	_threat_overlay.line_width = threat_line_width
	_threat_overlay.marker_radius = threat_marker_radius_px
	add_child(_threat_overlay)


func _draw() -> void:
	# Light backdrop circle so dark markers/space are easier to read.
	draw_circle(Vector2.ZERO, display_radius_px, background_color)
	# Border pulses red while at least one rock is on a collision course.
	var color: Color = border_color
	var width: float = border_width
	if _has_threats:
		var pulse: float = (sin(_blink_phase * TAU * threat_blink_hz) + 1.0) * 0.5
		color = border_color.lerp(threat_blink_color, pulse)
		width = border_width + 2.0 * pulse
	draw_arc(Vector2.ZERO, display_radius_px, 0.0, TAU, 64, color, width, true)


func _process(delta: float) -> void:
	if _has_threats:
		_blink_phase += delta
		queue_redraw()


func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < 1.0 / update_hz:
		return
	_accum = 0.0
	_refresh()


func _refresh() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var player_pos: Vector2 = player.global_position

	player_sprite.global_position = global_position
	# Source ship art is drawn pointing up; main scene rotates Sprite2D +90° CW
	# to align with Pyrrha's +X-forward convention. Mirror that shift here.
	player_sprite.rotation = player.rotation + PI / 2
	player_sprite.visible = true

	_place_with_edge_pin(earth_sprite, _world_node_pos("earth"), player_pos)
	_place(_moon_sprite, _world_node_pos("moon"), player_pos)
	_place(_station_sprite, _world_node_pos("station"), player_pos)

	# Asteroid markers — reuse pool, hide unused. Skip fragments (post-break debris).
	# Threat detection runs over ALL whole asteroids regardless of distance, so
	# the trajectory line can render even when the rock itself is outside the
	# minimap. The asteroid marker itself is still gated by detection_radius.
	_threats.clear()
	var earth = get_tree().get_first_node_in_group("earth")
	var earth_pos: Variant = earth.global_position if earth != null else null
	# Earth's threat radius is its actual rendered radius — derived from its
	# texture + scale so it stays correct if either changes in the editor.
	var earth_radius: float = _node_visual_radius(earth)
	var idx := 0
	for ast in get_tree().get_nodes_in_group("asteroid"):
		if "is_fragment" in ast and ast.is_fragment:
			continue
		if "is_off_radar" in ast and ast.is_off_radar:
			continue
		var local_pos: Vector2 = (ast.global_position - player_pos) * _conversion
		var marker_in_range: bool = ast.global_position.distance_to(player_pos) <= detection_radius

		# Place visual marker only if within range and pool has room.
		if marker_in_range and idx < _asteroid_pool.size():
			var marker: Sprite2D = _asteroid_pool[idx]
			marker.global_position = local_pos + global_position
			marker.rotation = ast.rotation
			marker.visible = true
			idx += 1

		# Threat check — independent of detection_radius.
		if earth_pos != null and earth_radius > 0.0 and "asteroid_velocity" in ast:
			if _is_on_collision_course(ast.global_position, ast.asteroid_velocity, earth_pos, earth_radius):
				var dir: Vector2 = ast.asteroid_velocity.normalized()
				var p1: Vector2 = local_pos - dir * threat_line_extent_px
				var p2: Vector2 = local_pos + dir * threat_line_extent_px
				var clipped: Array = _clip_segment_to_circle(p1, p2, display_radius_px)
				var marker_in_minimap: bool = local_pos.length() <= display_radius_px
				if not clipped.is_empty() or marker_in_minimap:
					_threats.append({
						"has_line": not clipped.is_empty(),
						"p1": Vector2.ZERO if clipped.is_empty() else clipped[0],
						"p2": Vector2.ZERO if clipped.is_empty() else clipped[1],
						"has_marker": marker_in_minimap,
						"marker": local_pos,
						"time": _time_to_impact(ast.global_position, ast.asteroid_velocity, earth_pos, earth_radius),
					})
	for i in range(idx, _asteroid_pool.size()):
		_asteroid_pool[i].visible = false
	# Sort smallest time first, then flag the most imminent so the overlay can
	# style it distinctly. Drawing order is also smallest-last so the highlight
	# renders on top.
	_threats.sort_custom(func(a, b): return a.time > b.time)
	if not _threats.is_empty():
		_threats[-1]["is_most_imminent"] = true
	_has_threats = not _threats.is_empty()
	_threat_overlay.threats = _threats
	_threat_overlay.queue_redraw()
	queue_redraw()


# Seconds until the asteroid's leading edge reaches Earth's surface, assuming
# straight-line motion and no further acceleration. Returns INF if the rock
# is moving away from Earth (or stationary); 0 if it already overlaps.
func _time_to_impact(ast_pos: Vector2, ast_vel: Vector2, earth_pos: Vector2, earth_radius: float) -> float:
	var to_earth: Vector2 = earth_pos - ast_pos
	var dist: float = to_earth.length()
	if dist <= earth_radius:
		return 0.0
	if ast_vel.length_squared() < 0.001:
		return INF
	var closing: float = ast_vel.dot(to_earth.normalized())
	if closing <= 0.0:
		return INF
	return (dist - earth_radius) / closing


# Intersect segment [p1, p2] with the circle centered at origin with the given
# radius. Returns the visible portion as [pa, pb] (both in local minimap coords),
# or [] if the segment lies entirely outside the circle.
func _clip_segment_to_circle(p1: Vector2, p2: Vector2, r: float) -> Array:
	var d: Vector2 = p2 - p1
	var a: float = d.dot(d)
	if a < 0.0001:
		if p1.length() <= r:
			return [p1, p2]
		return []
	var b: float = 2.0 * p1.dot(d)
	var c: float = p1.dot(p1) - r * r
	var disc: float = b * b - 4.0 * a * c
	if disc < 0.0:
		return []
	var sq: float = sqrt(disc)
	var t1: float = (-b - sq) / (2.0 * a)
	var t2: float = (-b + sq) / (2.0 * a)
	if t2 < 0.0 or t1 > 1.0:
		return []
	t1 = max(t1, 0.0)
	t2 = min(t2, 1.0)
	return [p1 + d * t1, p1 + d * t2]


# True if the asteroid is either currently inside Earth's actual visual
# radius OR its straight-line forward trajectory will pass through that radius.
func _is_on_collision_course(ast_pos: Vector2, ast_vel: Vector2, earth_pos: Vector2, radius: float) -> bool:
	var to_earth: Vector2 = earth_pos - ast_pos
	if to_earth.length() < radius:
		return true
	if ast_vel.length_squared() < 1.0:
		return false
	var dir: Vector2 = ast_vel.normalized()
	var t: float = to_earth.dot(dir)
	if t < 0.0:
		return false
	var closest_miss: float = (to_earth - dir * t).length()
	return closest_miss < radius


# Visual radius of a Sprite2D in world units, derived from texture size and
# the node's scale. Assumes a roughly circular sprite (planet, moon).
func _node_visual_radius(n) -> float:
	if n == null or not (n is Sprite2D) or n.texture == null:
		return 0.0
	var tex_size: Vector2 = n.texture.get_size()
	return tex_size.x * 0.5 * abs(n.scale.x)


func _world_node_pos(group: String) -> Variant:
	var n = get_tree().get_first_node_in_group(group)
	if n == null:
		return null
	return n.global_position


func _place(sprite: Sprite2D, pos, player_pos: Vector2) -> void:
	if pos == null:
		sprite.visible = false
		return
	var rel: Vector2 = pos - player_pos
	if rel.length() > detection_radius:
		sprite.visible = false
		return
	sprite.global_position = rel * _conversion + global_position
	sprite.visible = true


# Like _place, but when the target is beyond detection_radius, instead of
# hiding it we pin a smaller marker to the minimap's edge in the target's
# direction. Used for Earth so the player can always navigate back.
const EDGE_PIN_SCALE := Vector2(0.03, 0.03)
const NORMAL_SCALE := Vector2(0.05, 0.05)

func _place_with_edge_pin(sprite: Sprite2D, pos, player_pos: Vector2) -> void:
	if pos == null:
		sprite.visible = false
		return
	var rel: Vector2 = pos - player_pos
	if rel.length() <= detection_radius:
		sprite.scale = NORMAL_SCALE
		sprite.global_position = rel * _conversion + global_position
	else:
		sprite.scale = EDGE_PIN_SCALE
		sprite.global_position = rel.normalized() * display_radius_px + global_position
	sprite.visible = true
