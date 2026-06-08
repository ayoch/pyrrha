extends Node2D

# Overlay that renders threat lines/markers on top of every other minimap
# sprite (Earth, Moon, Station, asteroid markers). Lives as the last child of
# Mini_Map so its _draw runs after all sibling sprites have rendered.
#
# Mini_Map.gd pre-clips threat lines to the minimap circle and flags the
# single most-imminent threat with "is_most_imminent" so its marker can blink.

var threats: Array = []
var line_color: Color = Color(1.0, 0.2, 0.2, 0.9)
var line_width: float = 1.5
var marker_radius: float = 7.0
var blink_hz: float = 2.5

var _blink_phase: float = 0.0


func _process(delta: float) -> void:
	if _has_imminent():
		_blink_phase += delta
		queue_redraw()


func _draw() -> void:
	# Alpha multiplier for the most-imminent marker: oscillates 0..1 at blink_hz.
	var pulse: float = (sin(_blink_phase * TAU * blink_hz) + 1.0) * 0.5
	for t in threats:
		if t.has_line:
			draw_line(t.p1, t.p2, line_color, line_width, true)
		if t.has_marker:
			var c: Color = line_color
			if t.get("is_most_imminent", false):
				c.a *= pulse
			draw_arc(t.marker, marker_radius, 0.0, TAU, 24, c, line_width, true)


func _has_imminent() -> bool:
	for t in threats:
		if t.get("is_most_imminent", false):
			return true
	return false
