extends CanvasLayer


onready var health_bar = $MarginContainer/Rows/BottomRow/VBoxContainer/HealthSection/HealthBar
onready var health_tween = $MarginContainer/Rows/BottomRow/VBoxContainer/HealthSection/HealthTween
onready var shield_bar = $MarginContainer/Rows/BottomRow/VBoxContainer/ShieldSection/ShieldBar
onready var shield_tween = $MarginContainer/Rows/BottomRow/VBoxContainer/ShieldSection/ShieldTween
onready var energy_bar = $MarginContainer/Rows/BottomRow/VBoxContainer/EnergySection/EnergyBar
onready var energy_tween = $MarginContainer/Rows/BottomRow/VBoxContainer/EnergySection/EnergyTween

onready var debug_display = $MarginContainer/Rows/TopRow/HBoxContainer/VBoxContainer/Debug_Display
onready var debug_display2 = $MarginContainer/Rows/TopRow/HBoxContainer/VBoxContainer/Debug_Display2

var player: Player

func _ready():
	GlobalSignals.connect("add_to_debug_display", self, "add_to_debug_display")
	GlobalSignals.connect("set_debug_display", self, "set_debug_display")
	GlobalSignals.connect("add_to_debug2_display", self, "add_to_debug2_display")
	GlobalSignals.connect("set_debug2_display", self, "set_debug2_display")


func set_player(player: Player):
	self.player = player

	set_new_health_value(player.health)
	GlobalSignals.connect("player_health_changed", self, "set_new_health_value")
	
	set_new_energy_value(player.energy)
	GlobalSignals.connect("player_energy_changed", self, "set_new_energy_value")

#	set_weapon(player.weapon_manager.get_current_weapon())
#	player.weapon_manager.connect("weapon_changed", self, "set_weapon")


#func set_weapon(weapon: Weapon):
##	set_current_ammo(weapon.current_ammo)
##	set_max_ammo(weapon.max_ammo)
#	if not weapon.is_connected("weapon_ammo_changed", self, "set_current_ammo"):
#		weapon.connect("weapon_ammo_changed", self, "set_current_ammo")


func set_new_health_value(new_health: int):
	var original_color = Color("#5c1c1c")
	var highlight_color = Color("#ff7e7e")

	var bar_style = health_bar.get("custom_styles/fg")
	health_tween.interpolate_property(health_bar, "value", health_bar.value, new_health, 0.4,Tween.TRANS_LINEAR, Tween.EASE_IN)
	health_tween.interpolate_property(bar_style, "bg_color", original_color, highlight_color, 0.2, Tween.TRANS_LINEAR, Tween.EASE_IN)
	health_tween.interpolate_property(bar_style, "bg_color", highlight_color, original_color, 0.2, Tween.TRANS_LINEAR, Tween.EASE_OUT, 0.2)
	health_tween.start()


func set_new_shield_value(new_shield: int):
	var original_color = Color("#588fe8")
	var highlight_color = Color("#ff7e7e")

	var bar_style = health_bar.get("custom_styles/fg")
	shield_tween.interpolate_property(shield_bar, "value", health_bar.value, new_shield, 0.4,Tween.TRANS_LINEAR, Tween.EASE_IN)
	shield_tween.interpolate_property(bar_style, "bg_color", original_color, highlight_color, 0.2, Tween.TRANS_LINEAR, Tween.EASE_IN)
	shield_tween.interpolate_property(bar_style, "bg_color", highlight_color, original_color, 0.2, Tween.TRANS_LINEAR, Tween.EASE_OUT, 0.2)
	shield_tween.start()


func set_new_energy_value(new_energy: int):
	var original_color = Color("#b38a32")
	var highlight_color = Color("#f27e0f")

	var bar_style = energy_bar.get("custom_styles/fg")
	energy_tween.interpolate_property(energy_bar, "value", energy_bar.value, new_energy, 0.2,Tween.TRANS_LINEAR, Tween.EASE_IN)
	energy_tween.interpolate_property(bar_style, "bg_color", original_color, highlight_color, 0.1, Tween.TRANS_LINEAR, Tween.EASE_IN)
	energy_tween.interpolate_property(bar_style, "bg_color", highlight_color, original_color, 0.1, Tween.TRANS_LINEAR, Tween.EASE_OUT, 0.1)
	energy_tween.start()


func add_to_debug_display(message):
	debug_display.text += message
	
	
func set_debug_display(message):
	debug_display.text = message


func add_to_debug2_display(message):
	debug_display2.text += message
	
	
func set_debug2_display(message):
	debug_display2.text = message

