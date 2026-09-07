extends SceneTree

# The scan hold is what makes gathering evidence an act of piloting rather than a
# click. These pin that it cannot be skipped, banked, or asserted by a caller
# that never actually held position.

const ControllerType := preload("res://scripts/domain/ScanHoldController.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var smoke = ControllerType.new()
	if smoke == null or not (smoke.update(0.0, "", 0.0, 0.0, false) is Dictionary):
		push_error("[FAIL] ScanHoldController did not compile or update.")
		quit(1)
		return
	_test_completes_only_after_the_full_hold()
	_test_each_condition_cancels_without_cost()
	_test_progress_cannot_be_banked()
	_test_token_is_required_and_one_shot()
	if _failures.is_empty():
		print("[PASS] Scan hold controller tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


## Hold cleanly at a good distance and speed for `seconds`.
func _hold(controller, site: String, seconds: float, step: float = 0.5) -> Dictionary:
	var last: Dictionary = {}
	var elapsed := 0.0
	while elapsed < seconds - 0.0001:
		last = controller.update(step, site, 100.0, 2.0, false)
		elapsed += step
	return last


func _test_completes_only_after_the_full_hold() -> void:
	var controller = ControllerType.new()
	var partial: Dictionary = _hold(controller, "s1", 2.5)
	_expect(
		str(partial["state"]) == ControllerType.STATE_HOLDING,
		"Two and a half seconds must not complete the scan, got %s" % str(partial["state"])
	)
	_expect(
		float(partial["progress"]) > 0.7 and float(partial["progress"]) < 1.0,
		"Progress should report partway, got %.2f" % float(partial["progress"])
	)
	var done: Dictionary = controller.update(0.5, "s1", 100.0, 2.0, false)
	_expect(
		str(done["state"]) == ControllerType.STATE_COMPLETE,
		"Three seconds should complete the scan, got %s" % str(done["state"])
	)
	_expect(
		not str(done["token"]).is_empty(),
		"Completion must issue a token."
	)


func _test_each_condition_cancels_without_cost() -> void:
	# Each condition is checked on its own, so a change to one rule cannot be
	# masked by another rule happening to block at the same time.
	var cases := [
		{"name": "out of range", "distance": 400.0, "speed": 2.0, "combat": false, "reason": "out_of_range"},
		{"name": "too fast", "distance": 100.0, "speed": 40.0, "combat": false, "reason": "too_fast"},
		{"name": "in combat", "distance": 100.0, "speed": 2.0, "combat": true, "reason": "in_combat"},
	]
	for case in cases:
		var controller = ControllerType.new()
		_hold(controller, "s1", 2.5)
		var blocked: Dictionary = controller.update(
			0.5, "s1", float(case["distance"]), float(case["speed"]), bool(case["combat"])
		)
		_expect(
			str(blocked["state"]) == ControllerType.STATE_BLOCKED,
			"%s should block the hold, got %s" % [str(case["name"]), str(blocked["state"])]
		)
		_expect(
			str(blocked["reason"]) == str(case["reason"]),
			"%s should report reason %s, got %s" % [
				str(case["name"]), str(case["reason"]), str(blocked["reason"])
			]
		)
		_expect(
			is_zero_approx(float(blocked["progress"])),
			"%s must cancel progress, got %.2f" % [str(case["name"]), float(blocked["progress"])]
		)
		# Cancelling costs nothing beyond the progress: the very next good frame
		# starts a fresh hold rather than locking the player out.
		var resumed: Dictionary = controller.update(0.5, "s1", 100.0, 2.0, false)
		_expect(
			str(resumed["state"]) == ControllerType.STATE_HOLDING,
			"%s must not lock out a retry, got %s" % [str(case["name"]), str(resumed["state"])]
		)


func _test_progress_cannot_be_banked() -> void:
	# Without this, a player could bank 2.9 seconds on each of several sites and
	# then sweep them all instantly.
	var controller = ControllerType.new()
	_hold(controller, "s1", 2.5)
	var switched: Dictionary = controller.update(0.5, "s2", 100.0, 2.0, false)
	_expect(
		str(switched["state"]) == ControllerType.STATE_HOLDING,
		"Switching sites should start a new hold, got %s" % str(switched["state"])
	)
	_expect(
		float(switched["progress"]) < 0.4,
		"A new site must start near zero, got %.2f" % float(switched["progress"])
	)
	var back: Dictionary = controller.update(0.5, "s1", 100.0, 2.0, false)
	_expect(
		float(back["progress"]) < 0.4,
		"Returning to the first site must not resume banked progress, got %.2f" % float(back["progress"])
	)
	# A load must not resume a hold either.
	_hold(controller, "s3", 2.5)
	controller.reset()
	var after_load: Dictionary = controller.update(0.5, "s3", 100.0, 2.0, false)
	_expect(
		float(after_load["progress"]) < 0.4,
		"reset() must clear progress, got %.2f" % float(after_load["progress"])
	)


func _test_token_is_required_and_one_shot() -> void:
	var controller = ControllerType.new()
	var done: Dictionary = _hold(controller, "s1", 3.0)
	var token := str(done["token"])
	_expect(
		not controller.consume_token("s1:hold:999", "s1"),
		"An invented token must be refused."
	)
	_expect(
		not controller.consume_token(token, "s2"),
		"A token from one site must not validate a scan of another."
	)
	_expect(controller.consume_token(token, "s1"), "The real token should validate once.")
	_expect(
		not controller.consume_token(token, "s1"),
		"A token must be one-shot -- a replayed scan_complete must not pay out twice."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
