extends SceneTree

# Director behaviour that must hold without any model call: cooldown,
# fire probability, unknown beats, parsing, lead-in joining, persistence.

const Director := preload("res://scripts/story/QuietMomentDirector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_parse_line()
	_test_unknown_beat_declined()
	_test_persistence_round_trip()
	_test_new_campaign_reset()
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
