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
# per-beat, so a two-mode beat never repeats its announcement back to back
var _last_base_line: Dictionary = {}
var _in_flight: bool = false
var _outcome_serial := 0
## Every quiet-moment attempt, one JSON line each, for Claude to review the
## small model's word-salad calls after a playtest (Abe, 2026-10-07):
## tools/story_sim/quiet_moment_log.py prints it. "" turns it off (tests,
## smoke tests). Kept under LOG_MAX_BYTES by dropping the older half.
static var log_path := "user://quiet_moment_log.jsonl"
const LOG_MAX_BYTES := 2000000
## How the last sense check was decided: "model", "unavailable" or "override".
var _last_check := ""


## Optional outcome speech shares the existing request slot, cooldown and screen.
## Caller rechecks gameplay eligibility and reports actual text presentation.
func try_outcome(memory: Dictionary, state_id: String, still_valid: Callable, deliver: Callable, finished: Callable) -> bool:
	if _in_flight or (_last_fired_msec >= 0 and Time.get_ticks_msec() - _last_fired_msec < int(GLOBAL_COOLDOWN_SECONDS * 1000.0)):
		return false
	var speaker := str(memory.get("speaker_id", ""))
	var soul := FixedCastSoulRegistry.public_prompt_projection(speaker, state_id, "quiet_moment")
	var projected := OutcomeReactionProjector.project({"outcome_tag": memory.get("outcome_tag", "")})
	if not _outcome_model_available() or not bool(soul.get("ok", false)) or not bool(projected.get("ok", false)):
		return false
	var fact := str(projected["consequence"]["summary"])
	var brief := "React briefly to this completed investigation using only the supplied public fact."
	if memory.get("phase", "") == "callback":
		brief = "Briefly refer back to this earlier investigation using only the supplied public fact."
	var built := {"speaker": speaker, "packet": fact, "brief": brief, "word_cap": 28,
		"lead_in": "", "demos": [], "third_parties": []}
	built["prompt"] = JSON.stringify(soul) + "\n" + brief + "\nPublic fact: " + fact \
		+ "\nCertainty: " + str(projected["consequence"]["certainty"]) \
		+ '\nUse at most 28 words. Return only {"line":"..."}.'
	_in_flight = true
	_outcome_serial += 1
	_request_outcome(_outcome_serial, built, state_id, still_valid, deliver, finished, 1)
	return true


func _request_outcome(serial: int, built: Dictionary, state_id: String, still_valid: Callable, deliver: Callable, finished: Callable, attempt: int) -> void:
	_send_outcome_request(str(built["prompt"]), func(result: Dictionary) -> void:
		if serial != _outcome_serial:
			return
		if not bool(still_valid.call()):
			_give_up("outcome_reaction", ["stale_context"])
			finished.call(false)
			return
		var line := _parse_line(str(result.get("inner_text", ""))) if bool(result.get("ok", false)) else ""
		var errors: Array = _screen("outcome_reaction", built, line) if not line.is_empty() else ["empty_response"]
		var quality := FixedCastLineValidator.validate_line(str(built["speaker"]), state_id, "quiet_moment", line)
		if not bool(quality.get("ok", false)):
			errors.append("fixed_cast_validation")
		if not errors.is_empty():
			if attempt < 2:
				_request_outcome(serial, built, state_id, still_valid, deliver, finished, attempt + 1)
			else:
				_give_up("outcome_reaction", errors)
				finished.call(false)
			return
		_in_flight = false
		var presented := bool(deliver.call(line))
		if presented:
			_selector_for(str(built["speaker"])).accept(line)
			_last_fired_msec = Time.get_ticks_msec()
		else:
			_give_up("outcome_reaction", ["presentation_suppressed"])
		finished.call(presented)
	)


func _outcome_model_available() -> bool:
	var llm := get_node_or_null("/root/LLMInterface")
	return llm != null and bool(llm.get("small_model_verified"))


func _send_outcome_request(prompt: String, callback: Callable) -> void:
	var llm := get_node_or_null("/root/LLMInterface")
	if llm == null:
		callback.call({"ok": false, "reason": "llm_unavailable"})
	else:
		llm.call("request_quiet_moment", prompt, callback)


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

	# Two-mode beats: the fact is always announced, the character line is a
	# rare flourish on top. The base line is authored, needs no model call,
	# and is NOT subject to the conversational cooldown — it's information the
	# player asked for by filling the hold, not chatter.
	var base_lines: Array = beat.get("base_lines", [])
	var full_probability := float(beat.get("full_line_probability", 1.0))
	var use_base := not base_lines.is_empty() and _rng.randf() > full_probability

	var now := Time.get_ticks_msec()
	var ignore_cooldown := bool(options.get("ignore_cooldown", false))
	if not use_base and not ignore_cooldown and _last_fired_msec >= 0:
		if now - _last_fired_msec < int(GLOBAL_COOLDOWN_SECONDS * 1000.0):
			# Cooldown blocks the flourish, but a two-mode beat still reports.
			if not base_lines.is_empty():
				_speak_base(beat_id, beat, base_lines)
				return true
			return false

	if use_base:
		_speak_base(beat_id, beat, base_lines)
		return true

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


# The factual half of a two-mode beat. No model call, no screening needed
# (it is authored text), but it still goes through recency so she does not
# announce a full hold the same way twice running.
func _speak_base(beat_id: String, beat: Dictionary, base_lines: Array) -> void:
	var speaker := str(beat.get("speaker", ""))
	var selector = _selector_for(speaker)

	# Exclude only the PREVIOUS one. Checking the full recency window fails
	# here: with a handful of base lines they are all "recent" almost
	# immediately, and the fallback then repeats back to back.
	var pool: Array = []
	var previous := str(_last_base_line.get(beat_id, ""))
	for candidate in base_lines:
		if str(candidate) != previous:
			pool.append(str(candidate))
	if pool.is_empty():
		pool = base_lines.duplicate()

	var line := str(pool[_rng.randi_range(0, pool.size() - 1)])
	_last_base_line[beat_id] = line
	selector.accept(line)
	quiet_moment_ready.emit(speaker, beat_id, line)


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
		# A second opinion on sense before anyone hears it (Abe, 2026-10-04:
		# garbled lines like "She was just my main shaft. She had her hands."
		# kept getting through the pattern checks).
		_sense_check(line, func(makes_sense: bool) -> void:
			var outcome := "spoken" if makes_sense else ("retry" if attempt < MAX_ATTEMPTS else "silent")
			_log_attempt(beat_id, built, attempt, line, [], "fine" if makes_sense else "word_salad", outcome)
			if makes_sense:
				_accept(beat_id, built, line)
			elif attempt < MAX_ATTEMPTS:
				_request(beat_id, beat, attempt + 1)
			else:
				_give_up(beat_id, ["garbled"]))
		return

	_log_attempt(beat_id, built, attempt, line, failures, "", "retry" if attempt < MAX_ATTEMPTS else "silent")
	if attempt < MAX_ATTEMPTS:
		_request(beat_id, beat, attempt + 1)
		return
	_give_up(beat_id, failures)


func _log_attempt(beat_id: String, built: Dictionary, attempt: int, line: String,
		failures: Array, sense: String, outcome: String) -> void:
	if log_path.is_empty():
		return
	var entry := {"time": Time.get_datetime_string_from_system(), "beat": beat_id,
		"speaker": str(built.get("speaker", "")), "attempt": attempt, "line": line,
		"pattern_failures": failures, "sense": sense,
		"sense_by": _last_check if not sense.is_empty() else "", "outcome": outcome}
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE) if FileAccess.file_exists(log_path) 		else FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		return
	if file.get_length() > LOG_MAX_BYTES:
		var lines := file.get_as_text().split("
", false)
		file.close()
		file = FileAccess.open(log_path, FileAccess.WRITE)
		for kept in lines.slice(lines.size() / 2):
			file.store_line(kept)
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.close()


## Test seam: replaces the model's sense check (callback(makes_sense)).
var sense_check_override: Callable = Callable()
const SENSE_CHECK_PROMPT := "N.O.V.A. is a ship's AI. Her style is clipped, dry and playful: short fragments and teasing the Captain are NORMAL for her and fine.

Reject a line only if it is EITHER:
1. WORD SALAD: words thrown together so a sentence means nothing, like a person who IS a machine part, or a tool that IS a person.
2. INNUENDO: it reads as sexual, or as her body or parts being handled, greased, filled, tightened or touched.
Word salad: \"She was just my main shaft. Pressure was his hands.\"
Innuendo: \"This shaft needs greasing all the way down. You can do it.\"
Fine: \"Not a scratch. You're showing off now, aren't you?\"
Fine: \"She's gone. You talk faster around her. Not that I'm timing it. I'm timing it.\"

The line:
\"%s\"

Should it be rejected? Return ONLY this JSON object: {\"line\":\"no\"} if it is fine, or {\"line\":\"yes\"} if it should be rejected."


## Asks the small model whether `line` makes sense; calls back true or false.
## A failed request counts as a pass: the check must never silence the cast
## when the model is busy.
func _sense_check(line: String, callback: Callable) -> void:
	if sense_check_override.is_valid():
		_last_check = "override"
		sense_check_override.call(line, callback)
		return
	var llm := get_node_or_null("/root/LLMInterface")
	if llm == null:
		_last_check = "unavailable"
		callback.call(true)
		return
	llm.call("request_quiet_moment", SENSE_CHECK_PROMPT % line, func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			_last_check = "unavailable"
			callback.call(true)
			return
		_last_check = "model"
		var verdict := _parse_line(str(result.get("inner_text", ""))).strip_edges().to_lower()
		# The question is "is it word salad?": "yes" rejects.
		var makes_sense := not verdict.begins_with("yes")
		if not makes_sense:
			var diagnostics := get_node_or_null("/root/GenerationDiagnostics")
			if diagnostics != null:
				diagnostics.call("record_event", "quiet_moment", "sense_check_rejected", "quiet_moment_director", {"line": line})
		callback.call(makes_sense))


## Words that only ever made her lines leer (playtest 2026-10-10 finding 2).
## The repair beat's soft double meaning ("took their time") isn't on it.
const NOVA_LEER := "(?i)\\b(shafts?|greas\\w*|lube\\w*|flush\\w*|leak\\w*|wet|tighten\\w*|access ports?|lower ports?|my ports|hands (on|in) me|handled me|did me|loose|elbow.deep|all the way down|warm (their|your) hands|fill(ed)? me|strok\\w*|moan\\w*|sweaty|naked|undress\\w*)\\b"


static func leer_word(line: String) -> String:
	var re := RegEx.new()
	re.compile(NOVA_LEER)
	var m := re.search(line)
	return m.get_string() if m != null else ""


func _screen(beat_id: String, built: Dictionary, line: String) -> Array:
	var speaker := str(built.get("speaker", ""))
	var selector = _selector_for(speaker)
	if speaker == "nova":
		var leer := leer_word(line)
		if leer != "":
			return ["innuendo:%s" % leer]
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
	# The repair beat may carry a soft double meaning; a body-word swap on top
	# of it is one joke too many (playtest 2026-10-10).
	if speaker == "nova" and beat_id != "nova_repair_done":
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
	_outcome_serial += 1
	_in_flight = false
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
	_outcome_serial += 1
	_in_flight = false
	_selectors.clear()
	_anatomy.reset()
	Beats.reset_rotation()
	_last_base_line.clear()
	_last_fired_msec = -1
