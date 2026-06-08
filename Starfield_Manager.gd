extends Node2D

const TEXTURE := preload("res://2000x2000pxStarfield_2_LessStars.png")
const ROTATIONS := [0, 90, 180, 270]

var spacing: int = 2000

var _active_tiles: Dictionary = {}      # Vector2i(cx, cy) -> Sprite2D
var _last_update_pos: Vector2 = Vector2(-999999.0, -999999.0)


func _ready() -> void:
	GlobalSignals.connect("broadcast_player_position", Callable(self, "_on_received_player_position"))


func _on_received_player_position(position: Vector2) -> void:
	# Only rebuild the tile set when the player crosses into a new grid cell
	# or moves more than half a cell from the last update point.
	if position.distance_to(_last_update_pos) < spacing * 0.5:
		return
	_last_update_pos = position
	_update_tiles(position)


func _update_tiles(player_pos: Vector2) -> void:
	var vis_radius: float = _visibility_radius()
	var cell_r: int = ceili(vis_radius / float(spacing)) + 1
	var pcx: int = int(floor(player_pos.x / float(spacing)))
	var pcy: int = int(floor(player_pos.y / float(spacing)))

	var needed: Dictionary = {}
	for cx: int in range(pcx - cell_r, pcx + cell_r + 1):
		for cy: int in range(pcy - cell_r, pcy + cell_r + 1):
			var world_pos := Vector2(cx * spacing, cy * spacing)
			if world_pos.distance_to(player_pos) <= vis_radius:
				needed[Vector2i(cx, cy)] = true

	# Free tiles that scrolled out of range.
	for key: Vector2i in _active_tiles.keys():
		if not needed.has(key):
			_active_tiles[key].queue_free()
			_active_tiles.erase(key)

	# Create tiles for newly visible cells.
	for key: Vector2i in needed:
		if not _active_tiles.has(key):
			var tile := _make_tile(key.x, key.y)
			add_child(tile)
			_active_tiles[key] = tile


func _make_tile(cx: int, cy: int) -> Sprite2D:
	var tile := Sprite2D.new()
	tile.texture = TEXTURE
	tile.rotation_degrees = ROTATIONS[_cell_hash(cx, cy) % 4]
	tile.global_position = Vector2(cx * spacing, cy * spacing)
	return tile


func _cell_hash(cx: int, cy: int) -> int:
	return abs(cx * 2654435761 + cy * 2246822519) % 1000000007


func _visibility_radius() -> float:
	var cam: Camera2D = get_viewport().get_camera_2d()
	var z: float = cam.zoom.x if cam != null else 1.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return (vp.length() * 0.5 / z) + spacing * 2.0
