extends CanvasLayer

# Dialog box — bottom of screen. Displays a character portrait, speaker name,
# and message text. Driven entirely by GlobalSignals.dialog_message, which the
# DialogDirector emits. This node is a dumb view + queue; all "what to say and
# when" logic lives in DialogDirector / DialogContent.
#
# Queue rules:
#  - Messages carry a priority. Higher priority shows first and can preempt a
#    lower-priority message that is currently on screen (story > reactive).
#  - Messages carry a ttl (seconds). A queued message that can't be shown within
#    its ttl is dropped as stale. Story lines pass ttl < 0 (never expire), so
#    they are guaranteed to play.
#  - dialog_enabled (the player's toggle) suppresses reactive chatter but never
#    suppresses story (priority >= STORY_PRIORITY_MIN).

const PORTRAIT_SIZE := 80
const STORY_PRIORITY_MIN := 10   # at/above this, a line is "story": always shown

# Map icon_key → portrait texture. Add entries here as characters are created.
# If a key is missing the portrait area is hidden and only text shows.
const PORTRAITS: Dictionary = {
	# "kaowitz": preload("res://UI/portraits/kaowitz.png"),
}

var _queue: Array = []        # Array of {speaker, icon_key, text, priority, expire_at, seq}
var _seq: int = 0             # monotonic, for stable ordering within a priority
var _age: float = 0.0         # how long the current message has been visible
var _visible_msg: bool = false
var _current_priority: int = -1

var _panel: PanelContainer
var _portrait: TextureRect
var _speaker_label: Label
var _text_label: Label


func _ready() -> void:
	layer = 6
	# Run even while the tree is paused (e.g. respite / station) so station
	# chatter and story beats keep advancing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false
	GlobalSignals.dialog_message.connect(_on_dialog_message)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left   = 0.0
	_panel.anchor_right  = 1.0
	_panel.anchor_top    = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size = Vector2(0, 100)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.layout_mode = 2
	margin.add_theme_constant_override("margin_left",   12)
	margin.add_theme_constant_override("margin_right",  12)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.layout_mode = 2
	hbox.add_theme_constant_override("separation", 14)
	margin.add_child(hbox)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	hbox.add_child(_portrait)

	var vbox := VBoxContainer.new()
	vbox.layout_mode = 2
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 15)
	_speaker_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_speaker_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_speaker_label.add_theme_constant_override("outline_size", 4)
	vbox.add_child(_speaker_label)

	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 18)
	_text_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_text_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_text_label.add_theme_constant_override("outline_size", 5)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_text_label)


func _on_dialog_message(speaker: String, icon_key: String, text: String, priority: int, ttl: float) -> void:
	# The enable toggle silences reactive chatter but never story.
	if not GlobalSignals.dialog_enabled and priority < STORY_PRIORITY_MIN:
		return
	var expire_at: float = -1.0
	if ttl >= 0.0:
		expire_at = _now() + ttl
	_queue.append({
		"speaker": speaker, "icon_key": icon_key, "text": text,
		"priority": priority, "expire_at": expire_at, "seq": _seq,
	})
	_seq += 1
	_sort_queue()
	if not _visible_msg:
		_advance()
	elif priority > _current_priority:
		# A more important line just arrived — preempt the current one.
		_advance()


func _sort_queue() -> void:
	_queue.sort_custom(func(a, b):
		if a.priority != b.priority:
			return a.priority > b.priority
		return a.seq < b.seq)


func _advance() -> void:
	_drop_expired()
	if _queue.is_empty():
		_panel.visible = false
		_visible_msg = false
		_current_priority = -1
		return
	var msg: Dictionary = _queue.pop_front()
	_speaker_label.text = msg.speaker
	_text_label.text = msg.text
	var portrait_tex: Texture2D = PORTRAITS.get(msg.icon_key, null)
	if portrait_tex != null:
		_portrait.texture = portrait_tex
		_portrait.visible = true
	else:
		_portrait.visible = false
	_panel.visible = true
	_visible_msg = true
	_current_priority = msg.priority
	_age = 0.0


func _drop_expired() -> void:
	var now: float = _now()
	var kept: Array = []
	for m in _queue:
		var entry: Dictionary = m
		if entry.expire_at >= 0.0 and now > entry.expire_at:
			continue   # stale — drop it
		kept.append(entry)
	_queue = kept


func _process(delta: float) -> void:
	if not _visible_msg:
		return
	_age += delta
	if _age >= GlobalSignals.dialog_dismiss_sec:
		_advance()


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
