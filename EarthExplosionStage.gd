extends Node2D

# Single SubViewport that holds every active 3D explosion currently happening
# on Earth. One Camera3D, looking straight down (-Z) at a unit sphere centered
# at the origin. The SubViewport's texture composites over Earth via a Sprite2D.
#
# Why a single viewport instead of one per explosion: one render pass for all
# active impacts, automatic z-sorting between them (they're real 3D positions
# on the same sphere), and Earth's curvature comes for free — the same camera
# captures top-down at the pole, side-on at the rim, automatically.
#
# To trigger an impact from elsewhere:
#   get_tree().get_first_node_in_group("earth_explosion_stage")
#     .spawn_explosion(world_position)

const VIEWPORT_RESOLUTION := 512
const ExplosionScene: PackedScene = preload("res://ExplosionPlaceholder.tscn")

@onready var viewport: SubViewport = $SubViewport
@onready var stage_3d: Node3D = $SubViewport/Stage3D
@onready var display: Sprite2D = $Display

var _earth_node: Node = null
var _earth_radius: float = 0.0


func _ready() -> void:
	add_to_group("earth_explosion_stage")
	display.texture = viewport.get_texture()


func _process(_delta: float) -> void:
	if _earth_node == null:
		_earth_node = get_tree().get_first_node_in_group("earth")
	if _earth_node == null:
		return
	_earth_radius = _node_visual_radius(_earth_node)
	global_position = _earth_node.global_position
	if _earth_radius > 0.0:
		# Make the display sprite cover Earth exactly. The SubViewport renders
		# a [-1, +1] square (orthographic size 2.0) into a 512×512 texture,
		# so 1 unit in 3D = 256 viewport pixels. We scale the sprite so 256
		# texture pixels = earth_radius world units.
		display.scale = Vector2.ONE * (2.0 * _earth_radius / float(VIEWPORT_RESOLUTION))


# Spawn a 3D explosion at the 3D point on Earth's surface that corresponds to
# the given 2D world position. World position must be on Earth (within radius);
# otherwise it's silently ignored.
func spawn_explosion(world_pos: Vector2, size_scale: float = 1.0) -> void:
	if _earth_node == null or _earth_radius <= 0.0:
		return
	var offset: Vector2 = world_pos - _earth_node.global_position
	var d: float = offset.length()
	if d > _earth_radius:
		return
	# Map 2D disk position to 3D point on the unit sphere's near hemisphere.
	var x3: float = offset.x / _earth_radius
	var y3: float = offset.y / _earth_radius
	var z3: float = sqrt(max(0.0, 1.0 - x3 * x3 - y3 * y3))
	var radial := Vector3(x3, y3, z3)
	var ex := ExplosionScene.instantiate()
	stage_3d.add_child(ex)
	ex.position = radial
	# Align the explosion's local +Y axis with the outward radial direction so
	# its "up" points away from Earth's center.
	ex.basis = _basis_with_up(radial)
	# Scale end_scale and lifetime by the impactor's relative size.
	ex.end_scale *= size_scale
	ex.start_scale *= size_scale
	ex.lifetime *= lerpf(0.5, 1.0, size_scale)


# Builds an orthonormal basis whose +Y axis points along `up`. Picks any
# reasonable perpendicular for the other axes; sufficient for symmetric
# vertical-plume explosions where roll-about-up doesn't matter visually.
func _basis_with_up(up: Vector3) -> Basis:
	var u: Vector3 = up.normalized()
	var ref: Vector3 = Vector3.UP if abs(u.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var f: Vector3 = ref.cross(u).normalized()
	var r: Vector3 = u.cross(f).normalized()
	return Basis(r, u, f)


func _node_visual_radius(n) -> float:
	if n == null or not (n is Sprite2D) or n.texture == null:
		return 0.0
	return n.texture.get_size().x * 0.5 * abs(n.scale.x)
