class_name QuietMomentDirector
extends Node

# Fires optional fixed-cast quiet moments.
#
# Contract: these are OPTIONAL. Nobody waits on them, nothing blocks on them,
# and silence is always a valid outcome. A candidate that fails screening is
# retried; if the retries run out the character simply says nothing.
#
# Design rationale and the research behind every rule:
# skills/skill_llm_character_dialogue.md

signal quiet_moment_ready(speaker: String, beat_id: String, line: String)
signal quiet_moment_silent(beat_id: String, reasons: Array)

const Beats := preload("res://scripts/story/QuietMomentBeats.gd")
const Selector := preload("res://scripts/story/QuietMomentSelector.gd")
const AnatomySlip := preload("res://scripts/story/NovaAnatomySlip.gd")

const MAX_ATTEMPTS := 5
# Quiet moments compete with lounge chatter and mission dialogue. This mirrors
# the cooldown ShipBehaviorObserver already uses for semantic events.
const GLOBAL_COOLDOWN_SECONDS := 180.0

var _selectors: Dictionary = {}
var _anatomy := AnatomySlip.new()
var _rng := RandomNumberGenerator.new()
var _last_fired_msec: int = -1
var _in_flight: bool = false


func _ready() -> void:
	_rng.randomize()


func _selector_for(speaker: String):   # -> QuietMomentSelector
	if not _selectors.has(speaker):
		_selectors[speaker] = Selector.new()
	return _selectors[speaker]


# Returns false when the beat is declined before any model call: cooldown,
# probability roll, an already-running request, or an unknown beat.
func try_fire(beat_id: String, options: Dictionary = {}) -> bool:
	if _in_flight:
		return false
	var beat := Beats.beat(beat_id)
	if beat.is_empty():
		push_warning("[QuietMoment] unknown beat: %s" % beat_id)
		return false

	var now := Time.get_ticks_msec()
	var ignore_cooldown := bool(options.get("ignore_cooldown", false))
	if not ignore_cooldown and _last_fired_msec >= 0:
		if now - _last_fired_msec < int(GLOBAL_COOLDOWN_SECONDS * 1000.0):
			return false

	# A good line on too frequent a trigger still wears out. Boost fires far
	# more often than it deserves a comment, so its beat carries p=0.25.
	var probability := float(beat.get("fire_probability", 1.0))
	if probability < 1.0 and _rng.randf() > probability:
		return false

	var llm := get_node_or_null("/root/LLMInterface")
	if llm == null or not bool(llm.get("small_model_verified")):
		return false

	_in_flight = true
	_request(beat_id, beat, 1)
	return true


func _request(beat_id: String, beat: Dictionary, attempt: int) -> void:
	var built := Beats.build_request(beat_id, _rng)
	if not bool(built.get("ok", false)):
		_give_up(beat_id, ["build_failed:%s" % built.get("reason", "?")])
		return

	var llm := get_node_or_null("/root/LLMInterface")
	if llm == null:
		_give_up(beat_id, ["llm_unavailable"])
		return

	llm.call("request_quiet_moment", str(built.get("prompt", "")),
		func(result: Dictionary) -> void:
			_on_response(beat_id, beat, built, attempt, result)
	)


func _on_response(beat_id: String, beat: Dictionary, built: Dictionary,
		attempt: int, result: Dictionary) -> void:
	var failures: Array = []
	var line := ""

	if not bool(result.get("ok", false)):
		failures = ["transport:%s" % result.get("reason", "?")]
	else:
		line = _parse_line(str(result.get("inner_text", "")))
		if line.is_empty():
			failures = ["inner_line_missing"]
		else:
			failures = _screen(beat_id, built, line)

	if failures.is_empty():
		_accept(beat_id, built, line)
		return

	if attempt < MAX_ATTEMPTS:
		_request(beat_id, beat, attempt + 1)
		return
	_give_up(beat_id, failures)


func _screen(beat_id: String, built: Dictionary, line: String) -> Array:
	var speaker := str(built.get("speaker", ""))
	var selector = _selector_for(speaker)
	return selector.reasons(line, {
		"speaker": speaker,
		"packet": str(built.get("packet", "")),
		"lead_in": str(built.get("lead_in", "")),
		"brief": str(built.get("brief", "")),
		"word_cap": int(built.get("word_cap", 28)),
		"demos": built.get("demos", []),
		"third_parties": built.get("third_parties", []),
	})


func _accept(beat_id: String, built: Dictionary, line: String) -> void:
	var speaker := str(built.get("speaker", ""))
	var selector = _selector_for(speaker)
	selector.accept(line)

	var spoken := line
	if speaker == "nova":
		spoken = _anatomy.apply(line, _rng)
		if spoken != line:
			# recency must track what was actually said, not the raw candidate
			selector.replace_last_line(spoken)

	var lead_in := str(built.get("lead_in", ""))
	if not lead_in.is_empty():
		var separator := " "
		if not ".!?".contains(lead_in.strip_edges().right(1)):
			separator = ". "
		spoken = "%s%s%s" % [lead_in.strip_edges(), separator, spoken]

	_in_flight = false
	_last_fired_msec = Time.get_ticks_msec()
	quiet_moment_ready.emit(speaker, beat_id, spoken)


func _give_up(beat_id: String, reasons: Array) -> void:
	_in_flight = false
	# Project rule: a fallback is a failure to drive to root cause, not normal
	# operation. Every silence is recorded with WHY.
	var diagnostics := get_node_or_null("/root/GenerationDiagnostics")
	if diagnostics != null:
		diagnostics.call("record_event", "quiet_moment", "silent", "quiet_moment_director",
			{"beat_id": beat_id, "reasons": reasons})
	quiet_moment_silent.emit(beat_id, reasons)


static func _parse_line(inner_text: String) -> String:
	var parser := JSON.new()
	if parser.parse(inner_text) != OK:
		return ""
	var data: Variant = parser.get_data()
	if not data is Dictionary:
		return ""
	return str((data as Dictionary).get("line", "")).strip_edges().strip_edges(true, true)


# --- persistence -----------------------------------------------------------

func to_save_dict() -> Dictionary:
	var selectors := {}
	for speaker in _selectors:
		selectors[speaker] = _selectors[speaker].to_save_dict()
	return {"selectors": selectors, "anatomy": _anatomy.to_save_dict()}


func load_from_dict(data: Dictionary) -> void:
	_selectors.clear()
	var stored: Dictionary = data.get("selectors", {})
	for speaker in stored:
		var selector = Selector.new()
		selector.load_from_dict(stored[speaker])
		_selectors[str(speaker)] = selector
	_anatomy.load_from_dict(data.get("anatomy", {}))


# A new campaign must not inherit the previous one's position in every
# rotation cycle, or its first hour sounds like a continuation.
func reset_for_new_campaign() -> void:
	_selectors.clear()
	_anatomy.reset()
	Beats.reset_rotation()
	_last_fired_msec = -1
