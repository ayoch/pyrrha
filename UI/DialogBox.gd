extends CanvasLayer

# Dialog box — bottom of screen. Displays a character portrait, speaker name,
# and message text. Messages are queued; each shows for at least
# GlobalSignals.dialog_dismiss_sec before the next advances.
# If dialog_enabled is false the queue is silently discarded.

const PORTRAIT_SIZE := 80
const MIN_READ_FRACTION := 0.55   # must have shown this fraction of dismiss_sec before advancing

# Map icon_key → portrait texture. Add entries here as characters are created.
# If a key is missing the portrait area is hidden and only text shows.
const PORTRAITS: Dictionary = {
	# "kaowitz": preload("res://UI/portraits/kaowitz.png"),
}

var _queue: Array = []       # Array of {speaker, icon_key, text}
var _age: float = 0.0        # how long current message has been visible
var _visible_msg: bool = false

var _panel: PanelContainer
var _portrait: TextureRect
var _speaker_label: Label
var _text_label: Label


func _ready() -> void:
	layer = 6
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


func _on_dialog_message(speaker: String, icon_key: String, text: String) -> void:
	if not GlobalSignals.dialog_enabled:
		return
	_queue.append({"speaker": speaker, "icon_key": icon_key, "text": text})
	if not _visible_msg:
		_advance()


func _advance() -> void:
	if _queue.is_empty():
		_panel.visible = false
		_visible_msg = false
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
	_age = 0.0


func _process(delta: float) -> void:
	if not _visible_msg:
		return
	_age += delta
	var dismiss_sec: float = GlobalSignals.dialog_dismiss_sec
	# Advance to next queued message once current has had ample read time.
	if _age >= dismiss_sec * MIN_READ_FRACTION and not _queue.is_empty():
		_advance()
		return
	# Auto-dismiss when full time elapses and queue is empty.
	if _age >= dismiss_sec:
		_advance()
