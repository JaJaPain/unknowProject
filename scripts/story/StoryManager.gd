extends Node

# StoryManager — narrative director stub.
# Beat evaluation, arc generation, and nudge logic are implemented in Phase 1–4
# per story_manager_impl.md. This file owns the deferred beat scheduler (Tool 10)
# and the event hooks GameRoot calls into.

# ── DEV: StoryQuestManager smoke-test ────────────────────────────────────────
# Set _SQ_DEBUG = true to fire a hardcoded "kill 3 Reavers" story quest on the
# player's FIRST kill. Lets you verify the full quest pipeline (HUD, objective
# tracking, reward delivery) without needing a real beat source.
#
# HOW TO DISABLE: flip _SQ_DEBUG back to false and save. No other changes needed.
# HOW TO FIND:    grep _SQ_DEBUG in scripts/story/StoryManager.gd
# DO NOT SHIP with _SQ_DEBUG = true.
const _SQ_DEBUG := true
var _sq_debug_fired := false   # guard: only fires once per session

# ── Deferred beat schedule ────────────────────────────────────────────────────
# Each entry: {type, beat_id, threshold, current}
# type: "kills" | "dock" | "delay_min"
var _scheduled_beats: Array = []

# ── Event counters (reset per session, not persisted) ────────────────────────
var _kill_count_session: int = 0
var _dock_count_session: int = 0


func _ready() -> void:
	GlobalState.player_kill.connect(_on_ship_destroyed)


func reset_for_restart() -> void:
	_scheduled_beats.clear()
	_kill_count_session = 0
	_dock_count_session = 0
	_sq_debug_fired = false


# ── Public tool: deferred beat scheduling ────────────────────────────────────

# Fire beat_id after the player gets N more kills in this session.
func schedule_beat_after_kills(beat_id: String, n: int) -> void:
	_scheduled_beats.append({
		"type":      "kills",
		"beat_id":   beat_id,
		"threshold": _kill_count_session + n,
	})


# Fire beat_id on the very next dock (any station).
func schedule_beat_on_next_dock(beat_id: String) -> void:
	_scheduled_beats.append({
		"type":    "dock",
		"beat_id": beat_id,
	})


# Fire beat_id after delay_min in-game minutes have passed (uses real time at 1:1).
func schedule_beat_after_delay_min(beat_id: String, delay_min: float) -> void:
	_scheduled_beats.append({
		"type":      "delay_min",
		"beat_id":   beat_id,
		"fire_at":   Time.get_ticks_msec() + int(delay_min * 60.0 * 1000.0),
	})


# ── GameRoot event hooks ──────────────────────────────────────────────────────

func on_system_arrived(system_id: String) -> void:
	_check_delay_beats()


func on_kill(faction: String) -> void:
	_kill_count_session += 1
	_check_kill_beats()
	if _SQ_DEBUG and not _sq_debug_fired:
		_sq_debug_fired = true
		_fire_debug_story_quest()


func _on_ship_destroyed(faction: String) -> void:
	print("[StoryManager] ship_destroyed signal: %s (session kills: %d)" % [faction, _kill_count_session + 1])
	on_kill(faction)


func on_docked(_station) -> void:
	_dock_count_session += 1
	_check_dock_beats()
	_check_delay_beats()


func on_quest_completed(_quest: Dictionary) -> void:
	_check_delay_beats()


# ── Internal beat evaluation stubs ───────────────────────────────────────────

func _check_kill_beats() -> void:
	var fired: Array = []
	for entry in _scheduled_beats:
		if entry.get("type") != "kills":
			continue
		if _kill_count_session >= int(entry.get("threshold", 0)):
			_fire_beat(str(entry.get("beat_id", "")))
			fired.append(entry)
	for f in fired:
		_scheduled_beats.erase(f)


func _check_dock_beats() -> void:
	var fired: Array = []
	for entry in _scheduled_beats:
		if entry.get("type") != "dock":
			continue
		_fire_beat(str(entry.get("beat_id", "")))
		fired.append(entry)
	for f in fired:
		_scheduled_beats.erase(f)


func _check_delay_beats() -> void:
	var now: int = Time.get_ticks_msec()
	var fired: Array = []
	for entry in _scheduled_beats:
		if entry.get("type") != "delay_min":
			continue
		if now >= int(entry.get("fire_at", 0)):
			_fire_beat(str(entry.get("beat_id", "")))
			fired.append(entry)
	for f in fired:
		_scheduled_beats.erase(f)


func _fire_beat(beat_id: String) -> void:
	# Phase 1 stub — just logs. Phase 2+ will look up the beat in StoryRegistry
	# and execute its delivery (kaelen_voice_message, quest_injection, etc.).
	if beat_id.is_empty():
		return
	print("[StoryManager] Beat fired: %s (stub — no delivery yet)" % beat_id)


# ── DEV only — remove guard or flip _SQ_DEBUG when done ──────────────────────
func _fire_debug_story_quest() -> void:
	if not is_instance_valid(StoryQuestManager):
		return
	var quest_def := {
		"id":             "debug_sq_reavers_001",
		"title":          "Clear the Reavers",
		"time_limit_min": 10.0,
		"objective": {
			"type":                 "kill_tagged_ship",
			"target_persistent_id": "debug.reaver.target",
			"display":              "Destroy the Reaver leader",
		},
		"spawns": [
			{
				"type":          "ship",
				"faction":       "reavers",
				"ship_role":     "Combat",
				"persistent_id": "debug.reaver.target",
				"speed":         14.0,
				"behavior":      "patrol",
			}
		],
		"hook": {
			"type":    "kaelen_voice",
			"text":    "New contract just came in. Reavers have been hitting supply lanes nearby — there's a bounty on their leader. Go take care of it.",
			"delay_s": 1.5,
		},
		"on_complete": {
			"credits":       500,
			"chatter_sender": "Kaelen",
			"chatter_line":   "Good work. Credits are in your account.",
			"kaelen_voice":   true,
		},
		"on_fail": {
			"chatter_line": "You ran out of time. The Reaver leader slipped away.",
		},
	}
	StoryQuestManager.begin_quest(quest_def)
	print("[StoryManager] DEBUG: fired story quest debug_sq_reavers_001")
