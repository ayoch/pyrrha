class_name DialogContent
extends RefCounted

# ============================================================================
# DIALOG CONTENT — all writeable lines live here. This is the file to edit.
# DialogDirector reads these tables and decides what to play and when.
# Nothing here is final; everything is placeholder text to be rewritten.
# ============================================================================
#
# Two systems:
#
#   REACTIVE — automatic responses to game situations. Each situation holds
#   several variants; the Director plays a random one and won't repeat a
#   variant until the whole set has been used (shuffle bag). Add as many
#   variants as you like; 3–4 reads well.
#       situation_id: {
#           speaker:  display name,
#           icon:     portrait key (see DialogBox.PORTRAITS),
#           cooldown: seconds before this situation can fire again (anti-spam),
#           variants: [ "line a", "line b", ... ],
#       }
#
#   STORY — scripted, must-play lines that tell the campaign. Keyed by stage
#   index (0-based: stage 1 == 0). Each beat has a `cue` saying when in the
#   stage it fires. Story lines are high priority, never dropped, and play in
#   listed order. They replay on a fresh run (when stage 1 starts).
#       stage_index: [
#           { id, cue, speaker, icon, text, at },
#           ...
#       ]
#   Valid cues: "start" (stage begins), "boss" (boss incoming),
#               "respite" (stage cleared / dock).
#   Optional `at`: seconds of active play AFTER the cue fires, to dole beats out
#   across a stage instead of dumping them all at once. Omit / 0 == fire now.
#   Counts down only while playing (paused/station time doesn't burn it). If the
#   stage is cleared before a timed beat fires, it plays at the dock (never lost).
#   e.g. { "id": "midstage", "cue": "start", "at": 45.0, ... } -> ~45s into the stage.

# ----------------------------------------------------------------------------
# REACTIVE
# ----------------------------------------------------------------------------
const REACTIVE: Dictionary = {
	"inbound_earth": {
		"speaker": "Kaowitz", "icon": "kaowitz", "cooldown": 12.0,
		"variants": [
			"We've got a rock bound for Earth; burn it down before it lands.",
			"Collision course confirmed. That one's aimed at home.",
			"Inbound! Don't let it reach the surface.",
			"Threat trajectory through Earth. Intercept it.",
		],
	},
	"impact_minor": {
		"speaker": "Kaowitz", "icon": "kaowitz", "cooldown": 8.0,
		"variants": [
			"Impact. We took that one.",
			"One got through. Mark it down.",
			"Surface strike. Could've been worse.",
		],
	},
	"impact_catastrophic": {
		"speaker": "Kaowitz", "icon": "kaowitz", "cooldown": 6.0,
		"variants": [
			"That was a city. Pull it together.",
			"Catastrophic strike. That...could be millions.",
			"We just took a big hit. Don't let it happen again.",
		],
	},
	"shield_down": {
		"speaker": "Kaowitz", "icon": "kaowitz", "cooldown": 10.0,
		"variants": [
			"Shield's gone. You're bare metal now.",
			"No more shield. Be very careful.",
			"Shield collapsed. Get clear and let it recharge.",
		],
	},
	"low_hull": {
		"speaker": "Kaowitz", "icon": "kaowitz", "cooldown": 10.0,
		"variants": [
			"Hull's failing. One more bad hit and you're done.",
			"You're falling apart out there. Disengage.",
			"Critical damage. You can't help if you're dead.",
		],
	},
	"boss_incoming": {
		"speaker": "Kaowitz", "icon": "kaowitz", "cooldown": 0.0,
		"variants": [
			"We've got a big one coming. Hold the line.",
			"Mass contact inbound. Prioritize.",
			"Brace. The wave's about to break.",
		],
	},
	"respite": {
		"speaker": "Kaowitz", "icon": "kaowitz", "cooldown": 0.0,
		"variants": [
			"Skies are clear. Dock and catch your breath.",
			"That's the last of them. Get to the station while you can.",
			"Quiet for now. Repair, resupply, regroup.",
		],
	},
	"victory": {
		"speaker": "Kaowitz", "icon": "kaowitz", "cooldown": 0.0,
		"variants": [
			"Earth's still here. You did that.",
			"It's over. We held.",
		],
	},
	"defeat": {
		"speaker": "Kaowitz", "icon": "kaowitz", "cooldown": 0.0,
		"variants": [
			"Ship's gone. Earth's on its own now.",
			"That's the end of the line. I'm sorry.",
		],
	},
}

# ----------------------------------------------------------------------------
# STORY (placeholder beats — rewrite freely)
# ----------------------------------------------------------------------------
const STORY: Dictionary = {
	0: [
		{ "id": "intro_1", "cue": "start", "speaker": "Kaowitz", "icon": "kaowitz",
		  "text": "Miner 729, we've got a new mission for you. A rock's earthbound, probably the result of a collision the scopes didn't catch." },
		{ "id": "intro_2", "cue": "start", "speaker": "Kaowitz", "icon": "kaowitz",
		  "text": "It's a chondrite. We don't normally see them this far in. Light it up." },
		{ "id": "first_boss", "cue": "boss", "speaker": "Kaowitz", "icon": "kaowitz",
		  "text": "First real wave. Whatever's pushing these at us, this is just it clearing its throat." },
	],
	19: [
		{ "id": "finale_open", "cue": "start", "speaker": "Kaowitz", "icon": "kaowitz",
		  "text": "This is the one we've been counting down to. If we hold here, Earth makes it." },
		{ "id": "finale_boss", "cue": "boss", "speaker": "Kaowitz", "icon": "kaowitz",
		  "text": "Everything it has, all at once. Stay alive and keep firing." },
	],
}
