extends SceneTree

## System quirks in play: the pure rules and the runner against a stand-in ship.
##   Godot --headless --path . --script res://tests/story/run_system_quirk_tests.gd --log-file <path> -- --baseline-offline

const Effects := preload("res://scripts/story/quirks/SystemQuirkEffects.gd")
const RunnerType := preload("res://scripts/story/quirks/SystemQuirkRunner.gd")
const Reserved := preload("res://scripts/story/ReservedTopics.gd")

var _failures: Array[String] = []


class FakeShip extends Node3D:
	var current_shield := 100.0
	var is_docked := false
	var destroyed := false


func _initialize() -> void:
	await process_frame
	_test_rules()
	_test_runner()
	if _failures.is_empty():
		print("[PASS] System quirk tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_rules() -> void:
	var plain := Effects.effects_for(["dense_debris"])
	_check(plain["hazards"].is_empty() and plain["notes"].is_empty() and plain["environment"]["radio"] == true, "quirks outside the slice do nothing yet")
	var all := Effects.effects_for(Effects.SLICE_QUIRKS)
	_check(all["environment"]["player_detection_mult"] == Effects.NEBULA_DETECTION_MULT, "nebula shortens detection")
	_check(all["environment"]["radio"] == false, "dark zone silences the radio")
	_check(all["hazards"].size() == 2 and all["notes"].size() == 4, "pulsar and ion storm are hazards; every quirk is announced")
	for text in all["notes"] + Effects.WARNINGS.values() + Effects.STARTS.values() + Effects.ENDS.values():
		_check(Reserved.is_clean(str(text)), "quirk text stays clear of reserved topics: %s" % text)
	var p := Effects.PULSAR
	_check(Effects.phase(p, 0.0)["state"] == "calm", "nothing happens on arrival")
	_check(Effects.phase(p, 81.0)["state"] == "warning", "a warning comes before the sweep")
	_check(Effects.phase(p, 89.0)["state"] == "active", "then the sweep")
	_check(Effects.phase(p, 91.0) == {"state": "calm", "cycle": 1}, "then calm, next cycle")
	_check(Effects.pulsar_drain(p, 100.0, 100.0) == 15.0, "a sweep drains 15% of shields")
	_check(Effects.pulsar_drain(p, 100.0, 4.0) == 4.0, "a sweep never reaches the hull")
	var storm := Effects.effects_for(["ion_storm"])
	_check(Effects.environment_at(storm, 10.0)["shield_regen_mult"] == 1.0, "no storm, normal recharge")
	_check(is_equal_approx(float(Effects.environment_at(storm, 130.0)["shield_regen_mult"]), 0.4), "storm overhead slows recharge")


func _test_runner() -> void:
	var GlobalState: Node = root.get_node("GlobalState")
	var ship := FakeShip.new()
	root.add_child(ship)
	var saved_player = GlobalState.player
	var saved_capacity = GlobalState.shield_capacity
	GlobalState.player = ship
	GlobalState.shield_capacity = 100.0
	var runner = RunnerType.new()
	_check(runner != null, "the runner loads")
	if runner == null:
		return
	root.add_child(runner)
	runner.set_process(false)  # driven by hand below

	runner.enter_system(["pulsar", "nebula"])
	_check(float(GlobalState.environment_value("player_detection_mult", 1.0)) == Effects.NEBULA_DETECTION_MULT, "arrival sets the environment")
	for i in 200:  # 100 seconds
		runner._process(0.5)
	_check(is_equal_approx(ship.current_shield, 85.0), "one sweep in 100 s drains once (shield %.1f)" % ship.current_shield)
	ship.is_docked = true
	for i in 400:
		runner._process(0.5)
	_check(is_equal_approx(ship.current_shield, 85.0), "docked, the clock stops")
	ship.is_docked = false

	runner.enter_system(["ion_storm"])
	for i in 260:  # 130 s: inside the first storm window (110-150 s)
		runner._process(0.5)
	_check(is_equal_approx(float(GlobalState.environment_value("shield_regen_mult", 1.0)), 0.4), "the storm slows recharge while overhead")
	for i in 60:  # 160 s: storm passed
		runner._process(0.5)
	_check(float(GlobalState.environment_value("shield_regen_mult", 1.0)) == 1.0, "and recovers after")

	runner.leave_system()
	_check(GlobalState.system_environment.is_empty(), "leaving clears the environment")
	runner.enabled = false
	runner.enter_system(["pulsar", "relay_dark_zone"])
	_check(GlobalState.system_environment.is_empty(), "switched off, quirks do nothing")

	GlobalState.player = saved_player
	GlobalState.shield_capacity = saved_capacity
	runner.free()
	ship.free()
