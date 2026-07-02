extends Node

# NOTE: no class_name — this script is registered as the "Nova" autoload
# singleton (see project.godot). Call Nova.warn_targeted() etc. from anywhere.

# N.O.V.A. — Network Optimized Virtual Agent. The player's onboard ship AI and
# the game's second storytelling agent after Kaelen (see docs/todo.md). This is
# the core service spine: expression model, severity gating, portrait-frame math,
# and a speak() router. Triggers (combat targeting, nav events, idle timer),
# the portrait UI, and her TTS voice profile plug into this later — none are
# wired yet. Pure helpers here are unit-tested; go-live needs autoload/instance
# registration + those trigger hookups.

# Her portrait is a 3x3 emotion sheet; frames are indexed left→right, top→bottom.
const PORTRAIT_PATH := "res://assets/Portraits/ShipAI.png"
const FRAME_COLS := 3
const FRAME_ROWS := 3

# Expression names mapped to the 3x3 sheet in grid order (0..8).
const EXPRESSIONS := [
	"neutral",   # 0
	"smile",     # 1
	"serious",   # 2
	"thoughtful",# 3
	"calm",      # 4
	"alert",     # 5
	"worried",   # 6
	"wondering", # 7
	"downcast",  # 8
]

# Delivery severity. Higher = more urgent; a higher-severity line pre-empts a
# lower one so threat warnings always beat idle chatter/jokes.
enum Severity { IDLE = 0, NAV = 1, COMBAT = 2, THREAT = 3 }


# Maps an expression name to its 0-based frame index on the sheet. Unknown names
# fall back to neutral (0).
static func frame_index_for(expression: String) -> int:
	var idx := EXPRESSIONS.find(expression.strip_edges().to_lower())
	return idx if idx >= 0 else 0


# The sub-rect of a full-sheet texture for one frame index, given the whole
# texture's pixel size. Clamps the index into range.
static func region_for_frame(index: int, tex_width: float, tex_height: float) -> Rect2:
	var count := FRAME_COLS * FRAME_ROWS
	var i := clampi(index, 0, count - 1)
	var fw := tex_width / float(FRAME_COLS)
	var fh := tex_height / float(FRAME_ROWS)
	var col := i % FRAME_COLS
	var row := i / FRAME_COLS
	return Rect2(col * fw, row * fh, fw, fh)


# The expression that best fits an event kind. Keeps the trigger sites free of
# expression bookkeeping — they name the event, this picks the face.
static func expression_for_event(event_kind: String) -> String:
	match event_kind.strip_edges().to_lower():
		"targeted", "threat", "ambush":
			return "alert"
		"outmatched", "too_powerful", "danger":
			return "worried"
		"nav", "reroute", "arrival":
			return "thoughtful"
		"idle", "banter", "companion":
			return "calm"
		"joke", "greeting":
			return "smile"
		"story", "mystery":
			return "wondering"
		"loss", "setback":
			return "downcast"
		_:
			return "neutral"


# True if a line at `incoming` severity should interrupt one already showing at
# `current` severity. Equal severity does not interrupt (first-come stays).
static func should_preempt(incoming: int, current: int) -> bool:
	return incoming > current


# ── Runtime (autoload) ────────────────────────────────────────────────────────

const NOVA_SENDER := "N.O.V.A."
const NOVA_COLOR := Color(0.45, 0.75, 1.0)
# Min seconds between targeted warnings so multiple hostiles / repeated locks
# don't spam the line.
const TARGETED_WARN_COOLDOWN_MS := 12000

var _in_combat := false
var _last_targeted_warn_ms := -100000


func _ready() -> void:
	# Track combat state so warnings can suppress themselves during a fight.
	if is_instance_valid(CombatManager):
		if CombatManager.has_signal("combat_started"):
			CombatManager.combat_started.connect(func(_e): _in_combat = true)
		if CombatManager.has_signal("combat_ended"):
			CombatManager.combat_ended.connect(func(_won): _in_combat = false)


# True only when N.O.V.A. should speak an in-flight line: the player exists, is
# alive, is NOT docked, and is NOT in combat. Threat/idle triggers gate on this.
func can_speak_in_flight() -> bool:
	if _in_combat:
		return false
	var p = GlobalState.player
	if p == null or not is_instance_valid(p):
		return false
	if bool(p.get("destroyed")) or bool(p.get("is_docked")):
		return false
	return true


# Routes one N.O.V.A. line to the player. For now via the chatter feed; TTS with
# her own voice profile is a follow-up. expression is advisory (portrait UI TBD).
func speak(text: String, _severity: int = Severity.IDLE, _expression: String = "neutral") -> void:
	var line := text.strip_edges()
	if line.is_empty():
		return
	if is_instance_valid(GlobalState) and GlobalState.has_method("emit_chatter"):
		GlobalState.emit_chatter(NOVA_SENDER, line, NOVA_COLOR)


# "Captain, we have been targeted by an enemy vessel." Fires only in free flight
# (not docked, not in combat) and no more than once per cooldown window, so
# multiple hostiles acquiring a lock don't stack the warning. Safe to call often.
func warn_targeted() -> void:
	if not can_speak_in_flight():
		return
	var now := Time.get_ticks_msec()
	if now - _last_targeted_warn_ms < TARGETED_WARN_COOLDOWN_MS:
		return
	_last_targeted_warn_ms = now
	speak(
		"Captain, we have been targeted by an enemy vessel.",
		Severity.THREAT,
		expression_for_event("targeted")
	)
