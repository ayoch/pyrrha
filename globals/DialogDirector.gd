extends Node

# ============================================================================
# DIALOG DIRECTOR (autoload)
# Bridges game events -> GlobalSignals.dialog_message, driving two systems:
#
#   REACTIVE — situational, automatic. Picks a random non-repeating variant
#   (shuffle bag) from DialogContent.REACTIVE. Low priority; a stale reactive
#   line is dropped if it can't be shown within REACTIVE_TTL seconds.
#
#   STORY — scripted campaign beats from DialogContent.STORY, released at
#   stage cues (start / boss / respite). High priority, never dropped, plays
#   in order, so a given mission's lines are guaranteed to be said. Story
#   replays on a fresh run (when stage 1 starts).
#
# Priority is how the two systems coexist: story (PRIORITY_STORY) always
# shows before, and can preempt, reactive (PRIORITY_REACTIVE).
# ============================================================================

const PRIORITY_REACTIVE: int = 0
const PRIORITY_STORY: int = 10
const REACTIVE_TTL: float = 5.0          # reactive lines go stale after this

const LOW_HULL_FRAC: float = 0.30        # fire low_hull below this fraction
const LOW_HULL_CLEAR_FRAC: float = 0.45  # re-arm once healed above this

var _bags: Dictionary = {}               # situation -> remaining shuffled indices
var _last_variant: Dictionary = {}       # situation -> last index shown
var _cooldown_until: Dictionary = {}     # situation -> earliest next fire (sec)
var _story_played: Dictionary = {}       # beat key -> true

var _max_hull_seen: float = 0.0
var _low_hull_latched: bool = false
var _shield_down_latched: bool = false


func _ready() -> void:
	GlobalSignals.stage_started.connect(_on_stage_started)
	GlobalSignals.boss_started.connect(_on_boss_started)
	GlobalSignals.respite_started.connect(_on_respite_started)
	GlobalSignals.earth_impact.connect(_on_earth_impact)
	GlobalSignals.threat_inbound.connect(_on_threat_inbound)
	GlobalSignals.player_health_changed.connect(_on_health_changed)
	GlobalSignals.player_shield_changed.connect(_on_shield_changed)
	GlobalSignals.player_exists.connect(_on_player_exists)
	GlobalSignals.game_won.connect(_on_game_won)
	GlobalSignals.player_died.connect(_on_player_died)


# The player doesn't emit health at spawn, so seed the max directly from the
# ship when it appears — keeps the low_hull fraction accurate even after
# hull upgrades raise max_health.
func _on_player_exists() -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null and "max_health" in p:
		_max_hull_seen = float(p.max_health)
	_low_hull_latched = false
	_shield_down_latched = false


# ---------------------------------------------------------------- story
func _on_stage_started(idx: int) -> void:
	if idx == 0:
		_reset_run()   # fresh run: replay story, clear reactive memory
	_release_story(idx, "start")


func _on_boss_started(idx: int, _pattern: String) -> void:
	_release_story(idx, "boss")
	_fire_reactive("boss_incoming")


func _on_respite_started(idx: int) -> void:
	_release_story(idx, "respite")
	_fire_reactive("respite")
	# Health latches reset between stages so warnings can fire again next stage.
	_low_hull_latched = false
	_shield_down_latched = false


func _release_story(stage_idx: int, cue: String) -> void:
	var beats: Array = DialogContent.STORY.get(stage_idx, [])
	for b in beats:
		var beat: Dictionary = b
		if String(beat.get("cue", "start")) != cue:
			continue
		var key: String = "%d:%s:%s" % [stage_idx, cue, String(beat.get("id", beat.get("text", "")))]
		if _story_played.has(key):
			continue
		_story_played[key] = true
		_emit(String(beat.get("speaker", "")), String(beat.get("icon", "")),
			String(beat.get("text", "")), PRIORITY_STORY, -1.0)


# ---------------------------------------------------------------- reactive
func _on_earth_impact(deaths: int, _size: int, _stage_idx: int, _was_threat: bool) -> void:
	if deaths >= 1000000:
		_fire_reactive("impact_catastrophic")
	elif deaths > 0:
		_fire_reactive("impact_minor")


func _on_threat_inbound(_size: int) -> void:
	_fire_reactive("inbound_earth")


func _on_health_changed(health: float) -> void:
	_max_hull_seen = max(_max_hull_seen, health)
	if _max_hull_seen <= 0.0:
		return
	var frac: float = health / _max_hull_seen
	if frac <= LOW_HULL_FRAC and not _low_hull_latched:
		_low_hull_latched = true
		_fire_reactive("low_hull")
	elif frac >= LOW_HULL_CLEAR_FRAC:
		_low_hull_latched = false


func _on_shield_changed(shield: float) -> void:
	if shield <= 0.0 and not _shield_down_latched:
		_shield_down_latched = true
		_fire_reactive("shield_down")
	elif shield > 0.0:
		_shield_down_latched = false


func _on_game_won() -> void:
	_fire_reactive("victory")


func _on_player_died() -> void:
	_fire_reactive("defeat")


func _fire_reactive(situation: String) -> void:
	var entry: Dictionary = DialogContent.REACTIVE.get(situation, {})
	if entry.is_empty():
		return
	var variants: Array = entry.get("variants", [])
	if variants.is_empty():
		return
	var now: float = _now()
	var cooldown: float = float(entry.get("cooldown", 0.0))
	if float(_cooldown_until.get(situation, -1.0e12)) > now:
		return
	_cooldown_until[situation] = now + cooldown
	var idx: int = _pick_from_bag(situation, variants.size())
	_emit(String(entry.get("speaker", "")), String(entry.get("icon", "")),
		String(variants[idx]), PRIORITY_REACTIVE, REACTIVE_TTL)


# Shuffle-bag pick: returns every variant once in random order before any
# repeats, and avoids repeating the previous variant across bag refills.
func _pick_from_bag(situation: String, count: int) -> int:
	if count <= 1:
		return 0
	var bag: Array = _bags.get(situation, [])
	if bag.is_empty():
		for i in count:
			bag.append(i)
		bag.shuffle()
		if bag[0] == int(_last_variant.get(situation, -1)):
			bag.append(bag.pop_front())   # don't immediately repeat last shown
		_bags[situation] = bag
	var idx: int = bag.pop_front()
	_last_variant[situation] = idx
	return idx


# ---------------------------------------------------------------- helpers
func _emit(speaker: String, icon: String, text: String, priority: int, ttl: float) -> void:
	if text == "":
		return
	GlobalSignals.dialog_message.emit(speaker, icon, text, priority, ttl)


func _reset_run() -> void:
	_bags.clear()
	_last_variant.clear()
	_cooldown_until.clear()
	_story_played.clear()
	_max_hull_seen = 0.0
	_low_hull_latched = false
	_shield_down_latched = false


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
