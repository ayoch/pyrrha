extends CanvasLayer

# Full-screen station shop. Opens via GlobalSignals.open_station_shop;
# closing emits GlobalSignals.station_shop_departed.
#
# Upgrades are permanent for the run. Death resets everything (GlobalSignals.reset_progress).
# Repair restores hull to maximum for a credit cost.

const REPAIR_COST := 75

const UPGRADE_DATA := {
	"hull": {
		"name": "Hull Plating",
		"desc": "Reinforced panels raise maximum integrity.",
		"tiers": [
			{"cost": 100, "label": "+25 max integrity"},
			{"cost": 200, "label": "+25 max integrity"},
			{"cost": 350, "label": "+25 max integrity"},
		],
	},
	"shields": {
		"name": "Shield Capacitor",
		"desc": "Upgraded emitters raise maximum shield strength.",
		"tiers": [
			{"cost": 150, "label": "+25 max shield"},
			{"cost": 250, "label": "+25 max shield"},
			{"cost": 400, "label": "+25 max shield"},
		],
	},
	"energy": {
		"name": "Fusion Plant",
		"desc": "Higher-output reactor raises energy capacity and regen.",
		"tiers": [
			{"cost": 150, "label": "+25 max energy, +15 regen/s"},
			{"cost": 250, "label": "+25 max energy, +15 regen/s"},
			{"cost": 400, "label": "+25 max energy, +15 regen/s"},
		],
	},
	"engines": {
		"name": "Engine Upgrade",
		"desc": "Improved thrusters raise forward acceleration.",
		"tiers": [
			{"cost": 175, "label": "+300 thrust"},
			{"cost": 300, "label": "+300 thrust"},
			{"cost": 500, "label": "+300 thrust"},
		],
	},
	"capacitors": {
		"name": "Capacitor Bank",
		"desc": "High-density cells store more energy without changing recharge rate.",
		"tiers": [
			{"cost": 125, "label": "+50 max energy"},
			{"cost": 225, "label": "+50 max energy"},
			{"cost": 350, "label": "+50 max energy"},
		],
	},
}

var _credits_label: Label
var _repair_btn: Button
var _buy_btns: Dictionary = {}     # key -> Button
var _level_labels: Dictionary = {} # key -> Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	GlobalSignals.open_station_shop.connect(_on_open)
	GlobalSignals.credits_changed.connect(_refresh_credits)


func _on_open() -> void:
	_refresh_all()
	visible = true
	get_tree().paused = true


func _on_depart() -> void:
	visible = false
	get_tree().paused = false
	var player: Player = _get_player()
	if player != null:
		player.velocity = Vector2.ZERO
	GlobalSignals.emit_signal("station_shop_departed")


# ----------------------------------------------------------------------
# Purchases
# ----------------------------------------------------------------------

func _on_repair_pressed() -> void:
	var player: Player = _get_player()
	if player == null or GlobalSignals.credits < REPAIR_COST:
		return
	GlobalSignals.spend_credits(REPAIR_COST)
	player.health = player.max_health
	GlobalSignals.emit_signal("player_health_changed", player.health)
	_refresh_all()


func _on_buy_pressed(key: String) -> void:
	var level_var: String = "upgrade_" + key
	var current_level: int = GlobalSignals.get(level_var)
	var tiers: Array = UPGRADE_DATA[key].tiers
	if current_level >= tiers.size():
		return
	var cost: int = tiers[current_level].cost
	if GlobalSignals.credits < cost:
		return
	GlobalSignals.spend_credits(cost)
	GlobalSignals.set(level_var, current_level + 1)
	_apply_upgrade(key, current_level)
	_refresh_all()


func _apply_upgrade(key: String, tier_index: int) -> void:
	var player: Player = _get_player()
	if player == null:
		return
	match key:
		"hull":
			player.max_health += 25
		"shields":
			player.max_shield += 25
		"energy":
			player.max_energy += 25
			player.energy_regen_per_sec += 15
		"engines":
			player.thrust_forward += 300
		"capacitors":
			player.max_energy += 50


func _get_player() -> Player:
	var node: Node = get_tree().get_first_node_in_group("player")
	if node is Player:
		return node as Player
	return null


# ----------------------------------------------------------------------
# UI refresh
# ----------------------------------------------------------------------

func _refresh_credits(amount: int) -> void:
	if _credits_label != null:
		_credits_label.text = "%d credits" % amount


func _refresh_all() -> void:
	_refresh_credits(GlobalSignals.credits)
	var player: Player = _get_player()
	var hull_full: bool = player != null and player.health >= player.max_health
	_repair_btn.disabled = GlobalSignals.credits < REPAIR_COST or hull_full
	_repair_btn.text = "Repair  (%d cr)" % REPAIR_COST if not hull_full else "Hull intact"
	for key: String in UPGRADE_DATA:
		var level_var: String = "upgrade_" + key
		var level: int = GlobalSignals.get(level_var)
		var tiers: Array = UPGRADE_DATA[key].tiers
		var maxed: bool = level >= tiers.size()
		var lbl: Label = _level_labels[key]
		lbl.text = "Level %d / %d" % [level, tiers.size()]
		var btn: Button = _buy_btns[key]
		if maxed:
			btn.text = "Maxed"
			btn.disabled = true
		else:
			var cost: int = tiers[level].cost
			var next_label: String = tiers[level].label
			btn.text = "%s  (%d cr)" % [next_label, cost]
			btn.disabled = GlobalSignals.credits < cost


# ----------------------------------------------------------------------
# UI construction
# ----------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.10, 0.97)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var outer := MarginContainer.new()
	outer.anchor_right = 1.0
	outer.anchor_bottom = 1.0
	for side: String in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 48)
	add_child(outer)

	var root := VBoxContainer.new()
	root.layout_mode = 2
	root.add_theme_constant_override("separation", 22)
	outer.add_child(root)

	# Header
	var title := Label.new()
	title.text = "STATION — REPAIRS & UPGRADES"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_credits_label = Label.new()
	_credits_label.add_theme_font_size_override("font_size", 20)
	_credits_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_credits_label)

	root.add_child(HSeparator.new())

	# Repair row
	var repair_row := HBoxContainer.new()
	repair_row.add_theme_constant_override("separation", 16)
	root.add_child(repair_row)

	var repair_lbl := Label.new()
	repair_lbl.text = "Hull Repair — restore integrity to maximum."
	repair_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repair_lbl.add_theme_font_size_override("font_size", 17)
	repair_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	repair_row.add_child(repair_lbl)

	_repair_btn = Button.new()
	_repair_btn.custom_minimum_size = Vector2(220, 0)
	_repair_btn.pressed.connect(_on_repair_pressed)
	repair_row.add_child(_repair_btn)

	root.add_child(HSeparator.new())

	# Upgrade cards
	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 16)
	root.add_child(cards)

	for key: String in ["hull", "shields", "energy", "capacitors", "engines"]:
		cards.add_child(_make_card(key))

	root.add_child(HSeparator.new())

	# Depart button
	var depart := Button.new()
	depart.text = "Depart"
	depart.custom_minimum_size = Vector2(200, 48)
	depart.add_theme_font_size_override("font_size", 20)
	depart.pressed.connect(_on_depart)
	var center := CenterContainer.new()
	center.add_child(depart)
	root.add_child(center)


func _make_card(key: String) -> PanelContainer:
	var data: Dictionary = UPGRADE_DATA[key]
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.layout_mode = 2
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.layout_mode = 2
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = data.name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = data.desc
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_lbl)

	vbox.add_child(HSeparator.new())

	var level_lbl := Label.new()
	level_lbl.add_theme_font_size_override("font_size", 15)
	level_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_labels[key] = level_lbl
	vbox.add_child(level_lbl)

	# Spacer to push buy button to the bottom
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var buy_btn := Button.new()
	buy_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buy_btn.pressed.connect(_on_buy_pressed.bind(key))
	_buy_btns[key] = buy_btn
	vbox.add_child(buy_btn)

	return card
