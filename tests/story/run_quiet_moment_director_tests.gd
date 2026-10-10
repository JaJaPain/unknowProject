extends SceneTree

# Director behaviour that must hold without any model call: cooldown,
# fire probability, unknown beats, parsing, lead-in joining, persistence.

const Director := preload("res://scripts/story/QuietMomentDirector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	# Tests never write the player's quiet-moment log.
	Director.log_path = ""
	_test_parse_line()
	_test_unknown_beat_declined()
	_test_persistence_round_trip()
	_test_new_campaign_reset()
	_test_base_line_mode()
	_test_sense_check()
	_test_attempt_log()
	if _failures.is_empty():
		print("[PASS] QuietMomentDirector (all cases)")
		quit(0)
		return
	for f in _failures:
		push_error(f)
	print("[FAIL] QuietMomentDirector: %d case(s)" % _failures.size())
	quit(1)


func _test_parse_line() -> void:
	var good := Director._parse_line('{"line":"This one paid small."}')
	if good != "This one paid small.":
		_failures.append("parse failed on valid JSON: '%s'" % good)
	if Director._parse_line("not json at all") != "":
		_failures.append("parse accepted non-JSON")
	if Director._parse_line('{"other":"x"}') != "":
		_failures.append("parse accepted a missing line key")


func _test_unknown_beat_declined() -> void:
	var d := Director.new()
	get_root().add_child(d)
	if d.try_fire("no_such_beat"):
		_failures.append("fired for an unknown beat")
	d.queue_free()


func _test_persistence_round_trip() -> void:
	var d := Director.new()
	get_root().add_child(d)
	# seed some recency through the selector the director owns
	var selector = d.call("_selector_for", "kaelen")
	selector.accept("This one paid small. No tricks, no traps.")
	var saved := d.to_save_dict()

	var restored := Director.new()
	get_root().add_child(restored)
	restored.load_from_dict(saved)
	var reasons: Array = restored.call("_selector_for", "kaelen").reasons(
		"This one didn't move anything at all.", {"speaker": "kaelen", "word_cap": 40})
	if not reasons.has("opener_repeat"):
		_failures.append("director recency did not survive save/load: %s" % [reasons])
	d.queue_free()
	restored.queue_free()


func _test_new_campaign_reset() -> void:
	var d := Director.new()
	get_root().add_child(d)
	d.call("_selector_for", "nova").accept("My ribs are aching from it.")
	d.reset_for_new_campaign()
	var reasons: Array = d.call("_selector_for", "nova").reasons(
		"My ribs are aching from it.", {"speaker": "nova", "word_cap": 40})
	if reasons.has("phrase_repeat"):
		_failures.append("new campaign inherited previous recency")
	d.queue_free()


# Two-mode beats: the fact is always announced, the character line is rare.
func _test_base_line_mode() -> void:
	var d := Director.new()
	get_root().add_child(d)

	var beat := {
		"speaker": "nova",
		"base_lines": ["Hold's at capacity.", "Cargo hold is full, Captain."],
		"full_line_probability": 0.0,   # never the full line, always the base
	}
	var spoken: Array[String] = []
	d.quiet_moment_ready.connect(func(_s, _b, line): spoken.append(line))

	for i in 5:
		d.call("_speak_base", "nova_cargo_full", beat, beat["base_lines"])
	if spoken.size() != 5:
		_failures.append("base line did not emit every time: %d/5" % spoken.size())
	for line in spoken:
		if not (beat["base_lines"] as Array).has(line):
			_failures.append("base mode spoke something unauthored: %s" % line)
	# consecutive repeats should be avoided where an alternative exists
	var back_to_back := 0
	for i in range(1, spoken.size()):
		if spoken[i] == spoken[i - 1]:
			back_to_back += 1
	if back_to_back > 1:
		_failures.append("base lines repeated back to back %d times" % back_to_back)
	d.queue_free()


# Abe, 2026-10-04: garbled lines got through. A line that passes the pattern
# checks still gets a sense check; a "no" on the last attempt means silence,
# never the garbled line.
func _test_sense_check() -> void:
	var d = Director.new()
	root.add_child(d)
	var silent: Array = []
	var spoken: Array = []
	d.quiet_moment_silent.connect(func(_b, reasons) -> void: silent.append(reasons))
	d.quiet_moment_ready.connect(func(_s, _b, line) -> void: spoken.append(line))
	var built := {"speaker": "nova", "word_cap": 45, "lead_in": "", "packet": "", "brief": "", "demos": [], "third_parties": []}
	var good := JSON.stringify({"line": "Kross took her time on my plating. Smooth work, I'll give her that."})
	d.sense_check_override = func(_line: String, cb: Callable) -> void: cb.call(false)
	d.call("_on_response", "nova_long_transit", {}, built, Director.MAX_ATTEMPTS, {"ok": true, "inner_text": good})
	if silent.size() != 1 or not (silent[0] as Array).has("garbled") or not spoken.is_empty():
		_failures.append("sense check: a garbled verdict on the last try should go silent: silent %s spoken %s" % [silent, spoken])
	d.sense_check_override = func(_line: String, cb: Callable) -> void: cb.call(true)
	d.call("_on_response", "nova_long_transit", {}, built, Director.MAX_ATTEMPTS, {"ok": true, "inner_text": good})
	if spoken.size() != 1:
		_failures.append("sense check: a sensible line should be spoken: %s" % [spoken])
	if not Director.SENSE_CHECK_PROMPT.contains("WORD SALAD"):
		_failures.append("sense check prompt names the scrambled-meaning case")
	d.free()


# Abe, 2026-10-07: every attempt goes to a log Claude reviews after a playtest.
func _test_attempt_log() -> void:
	var path := "user://test_quiet_moment_log.jsonl"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Director.log_path = path
	var d = Director.new()
	root.add_child(d)
	var built := {"speaker": "nova", "word_cap": 45, "lead_in": "", "packet": "", "brief": "", "demos": [], "third_parties": []}
	var good := JSON.stringify({"line": "Kross took her time on my plating. Smooth work, I'll give her that."})
	d.sense_check_override = func(_line: String, cb: Callable) -> void: cb.call(false)
	d.call("_on_response", "nova_long_transit", {}, built, Director.MAX_ATTEMPTS, {"ok": true, "inner_text": good})
	d.sense_check_override = func(_line: String, cb: Callable) -> void: cb.call(true)
	d.call("_on_response", "nova_long_transit", {}, built, Director.MAX_ATTEMPTS, {"ok": true, "inner_text": good})
	var lines := FileAccess.get_file_as_string(path).split("
", false)
	if lines.size() != 2:
		_failures.append("attempt log: expected 2 entries, got %d" % lines.size())
	else:
		var first: Dictionary = JSON.parse_string(lines[0])
		var second: Dictionary = JSON.parse_string(lines[1])
		if first.get("sense") != "word_salad" or first.get("outcome") != "silent" or second.get("sense") != "fine" or second.get("outcome") != "spoken":
			_failures.append("attempt log: wrong entries %s / %s" % [first, second])
		if not str(first.get("line", "")).contains("Kross"):
			_failures.append("attempt log: the line itself is recorded")
	Director.log_path = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	d.free()
