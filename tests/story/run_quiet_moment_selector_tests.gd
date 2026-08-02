extends SceneTree

# Recency gating and save persistence. Persistence is the case that matters
# most: without it the freshness guarantee resets on every reload.

const Selector := preload("res://scripts/story/QuietMomentSelector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_opener_recency()
	_test_phrase_recency()
	_test_closer_recency()
	_test_windows_expire()
	_test_persistence_round_trip()
	_test_replace_last_line()
	if _failures.is_empty():
		print("[PASS] QuietMomentSelector (all cases)")
		quit(0)
		return          # quit() does not halt execution immediately
	for f in _failures:
		push_error(f)
	print("[FAIL] QuietMomentSelector: %d case(s)" % _failures.size())
	quit(1)


func _ctx() -> Dictionary:
	return {"speaker": "kaelen", "word_cap": 40}


func _test_opener_recency() -> void:
	var s := Selector.new()
	s.accept("This one paid small. No tricks, no traps.")
	var errors := s.reasons("This one didn't move anything at all.", _ctx())
	if not errors.has("opener_repeat"):
		_failures.append("opener_repeat not raised, got %s" % [errors])
	var different := s.reasons("Nobody bled. The number was low.", _ctx())
	if not different.is_empty():
		_failures.append("different opener rejected: %s" % [different])


func _test_phrase_recency() -> void:
	var s := Selector.new()
	s.accept("Lights stay on, but nothing moves at all.")
	var errors := s.reasons("Well, lights stay on, but nothing moves here.", _ctx())
	if not errors.has("phrase_repeat"):
		_failures.append("phrase_repeat not raised, got %s" % [errors])


func _test_closer_recency() -> void:
	var s := Selector.new()
	s.accept("Small money for small work. No complaints.")
	var errors := s.reasons("Thin pay again. No complaints from me.", _ctx())
	if not errors.has("closer_repeat") and not errors.has("phrase_repeat"):
		_failures.append("closer_repeat not raised, got %s" % [errors])


func _test_windows_expire() -> void:
	# An opener must become available again once it falls out of the window.
	var s := Selector.new()
	s.accept("Alpha one paid nothing much at all.")
	for i in Selector.OPENER_WINDOW:
		s.accept("Filler%d line goes here for spacing." % i)
	var errors := s.reasons("Alpha one barely covered the fuel.", _ctx())
	if errors.has("opener_repeat"):
		_failures.append("opener never expired from the window")


func _test_persistence_round_trip() -> void:
	var s := Selector.new()
	s.accept("This one paid small. No tricks, no traps.")
	var saved := s.to_save_dict()

	var reloaded := Selector.new()
	reloaded.load_from_dict(saved)
	var errors := reloaded.reasons("This one didn't move anything at all.", _ctx())
	if not errors.has("opener_repeat"):
		_failures.append("recency did not survive save/load: %s" % [errors])

	reloaded.clear()
	var after_clear := reloaded.reasons("This one didn't move anything at all.", _ctx())
	if after_clear.has("opener_repeat"):
		_failures.append("clear() did not reset recency")


func _test_replace_last_line() -> void:
	# The anatomy correction rewrites a line AFTER acceptance; recency has to
	# track what was actually spoken, not the pre-correction text.
	var s := Selector.new()
	s.accept("My ribs are aching from it.")
	s.replace_last_line("My ribs are aching from it. My frame spars, technically.")
	if not s.recent_lines[s.recent_lines.size() - 1].contains("frame spars"):
		_failures.append("replace_last_line did not update the tracked line")
