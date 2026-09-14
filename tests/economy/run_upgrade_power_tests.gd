extends SceneTree

var _failed := false
var _state: Node = null


func _initialize() -> void:
	_state = root.get_node_or_null("GlobalState")
	if _state == null:
		_expect(false, "GlobalState autoload should be available.")
		quit(1)
		return
	_test_baseline_power_budget()
	_test_sensor_upgrade_power_draw()
	_test_powerplant_gates_stacked_upgrades()
	if _failed:
		quit(1)
	else:
		print("[UpgradePowerTests] PASS")
		quit(0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("[UpgradePowerTests] " + message)


func _reset_with_resources() -> void:
	_state.reset_for_restart()
	_state.player_credits = 10000
	_state.player_storage_ore = 10000.0


func _test_baseline_power_budget() -> void:
	_state.reset_for_restart()
	_expect(
		int(_state.get_current_power_draw()) == 255,
		"Starter ship should draw 255 MW."
	)
	_expect(int(_state.power_capacity) == 300, "Starter reactor should provide 300 MW.")
	_expect(int(_state.sensor_tier) == 0, "Starter sensors should reveal threat only.")


func _test_sensor_upgrade_power_draw() -> void:
	_reset_with_resources()
	_expect(_state.purchase_upgrade("sensors", "standard"), "Sensor Mk II should install.")
	_expect(int(_state.sensor_tier) == 1, "Sensor Mk II should set combat intel tier 1.")
	_expect(int(_state.get_current_power_draw()) == 265, "Sensor Mk II should add 10 MW.")
	_expect(_state.purchase_upgrade("sensors", "standard"), "Sensor Mk III should install.")
	_expect(int(_state.sensor_tier) == 2, "Sensor Mk III should set combat intel tier 2.")
	_expect(int(_state.get_current_power_draw()) == 280, "Sensor Mk III should add another 15 MW.")


func _test_powerplant_gates_stacked_upgrades() -> void:
	_reset_with_resources()
	_expect(_state.purchase_upgrade("shields", "bulwark"), "First shield upgrade should fit stock reactor.")
	_expect(not _state.purchase_upgrade("engine", "speed"), "Stacked engine upgrade should exceed stock reactor.")
	_expect(_state.purchase_upgrade("power", "standard"), "Powerplant Mk II should install.")
	_expect(_state.purchase_upgrade("engine", "speed"), "Engine upgrade should fit after powerplant upgrade.")
