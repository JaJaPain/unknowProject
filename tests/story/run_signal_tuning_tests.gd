extends SceneTree

## Signal tuning: the dials find and clear a drifting source, a clean hold
## locks, giving up keeps what was heard, and static eats words.
##   Godot --headless --path . --script res://tests/story/run_signal_tuning_tests.gd --log-file <path>

const Model := preload("res://scripts/story/activities/SignalTuningModel.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	# A captain who follows the source exactly locks in about LOCK_SECONDS.
	var s := Model.start(7)
	var t := 0.0
	while not bool(s["locked"]) and t < 20.0:
		s = Model.step(s, 0.1, float(s["target_freq"]), float(s["target_phase"]))
		t += 0.1
	_check(bool(s["locked"]) and t <= Model.LOCK_SECONDS + 0.5, "tracking the source locks in time (%.1fs)" % t)
	_check(Model.outcome(s) == "clean", "a clean hold is clean: %s" % Model.outcome(s))
	var frozen := Model.step(s, 1.0, 0.0, 0.0)
	_check(bool(frozen["locked"]) and frozen["elapsed"] == s["elapsed"], "a locked signal stays locked")

	# Dials parked far away never lock.
	s = Model.start(7)
	var far := fposmod(float(s["target_freq"]) + 0.5, 1.0)
	for i in range(200):
		s = Model.step(s, 0.1, far, 0.0)
	_check(not bool(s["locked"]) and Model.outcome(s) == "failed", "wrong dials fail")

	# The source drifts, so a dial that stops following loses it.
	s = Model.start(11, 3.0)
	var start_freq := float(s["target_freq"])
	for i in range(300):
		s = Model.step(s, 0.1, 0.0, 0.0)
	_check(absf(float(s["target_freq"]) - start_freq) > 0.01, "the source wanders")

	# Right frequency, wrong phase: found, but not clear enough to lock.
	s = Model.start(3)
	var q := Model.quality(s, float(s["target_freq"]), fposmod(float(s["target_phase"]) + 0.5, 1.0))
	_check(q > 0.2 and q < Model.LOCK_QUALITY, "frequency finds it, phase clears it (%.2f)" % q)

	# Heavy interference: a lock is possible but only partial.
	s = Model.start(5, 3.0)
	for i in range(100):
		s = Model.step(s, 0.1, float(s["target_freq"]), float(s["target_phase"]))
	_check(bool(s["locked"]) and Model.outcome(s) == "partial", "a storm lock is partial: %s locked=%s" % [Model.outcome(s), str(s["locked"])])

	# Giving up past half a lock keeps a partial.
	s = Model.start(9)
	for i in range(25):
		s = Model.step(s, 0.1, float(s["target_freq"]), float(s["target_phase"]))
	_check(not bool(s["locked"]) and Model.outcome(s) == "partial", "half a lock is partial")

	# Static eats words, the same way every time for one attempt.
	var text := "The shipment moves through the old relay at second shift and nobody signs for it"
	var heard := Model.garble(text, 0.5, 42)
	_check(heard != text and heard.contains("…"), "static eats words: %s" % heard)
	_check(heard == Model.garble(text, 0.5, 42), "garble is deterministic")
	_check(Model.garble(text, 1.0, 42) == text, "a clean lock hears everything")
	_check(Model.clarity_for("assisted", s) == Model.ASSIST_CLARITY and Model.clarity_for("failed", s) == 0.0, "clarity per outcome")

	if _failures.is_empty():
		print("[PASS] Signal tuning model")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
