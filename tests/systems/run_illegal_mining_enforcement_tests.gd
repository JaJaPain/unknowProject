extends SceneTree

const EnforcementType := preload(
	"res://scripts/systems/IllegalMiningEnforcement.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_test_first_violation_dispatches_two_ships()
	_test_repeated_violation_refreshes_heat_without_stacking()
	_test_heat_expires()
	_test_fine_payment_clears_heat()
	_test_enforcement_ship_marker()
	_test_unwitnessed_global_report_does_not_dispatch()
	_test_witnessed_global_report_dispatches_and_spawns()

	if _failures.is_empty():
		print("[PASS] Illegal mining enforcement tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_first_violation_dispatches_two_ships() -> void:
	var enforcement := EnforcementType.new()
	var result := enforcement.report_violation(
		"system.nightfall",
		"belt.alpha",
		"gen_cinder_foundry",
		1000
	)
	_expect(
		bool(result.get("dispatch", false))
			and int(result.get("ship_count", 0)) == EnforcementType.RESPONSE_SHIP_COUNT
			and enforcement.active_response_count("system.nightfall", "gen_cinder_foundry") == 1,
		"first_violation: expected one two-ship dispatch group."
	)


func _test_repeated_violation_refreshes_heat_without_stacking() -> void:
	var enforcement := EnforcementType.new()
	var first := enforcement.report_violation(
		"system.nightfall",
		"belt.alpha",
		"gen_cinder_foundry",
		1000
	)
	var second := enforcement.report_violation(
		"system.nightfall",
		"belt.alpha",
		"gen_cinder_foundry",
		2000
	)
	_expect(
		bool(first.get("dispatch", false))
			and not bool(second.get("dispatch", false))
			and str(second.get("reason", "")) == "already_active"
			and enforcement.active_response_count("system.nightfall", "gen_cinder_foundry") == 1,
		"repeat_violation: repeated reports should not stack response groups."
	)
	_expect(
		enforcement.fine_due("system.nightfall", "gen_cinder_foundry")
			== EnforcementType.BASE_FINE_CREDITS * 2,
		"repeat_violation: repeated reports should still increase the fine."
	)


func _test_heat_expires() -> void:
	var enforcement := EnforcementType.new()
	enforcement.report_violation(
		"system.nightfall",
		"belt.alpha",
		"gen_cinder_foundry",
		1000
	)
	var removed := enforcement.clear_expired(
		1000 + EnforcementType.HEAT_DURATION_MSEC
	)
	_expect(
		removed == 1
			and not enforcement.is_heat_active("system.nightfall", "gen_cinder_foundry")
			and enforcement.fine_due("system.nightfall", "gen_cinder_foundry")
				== EnforcementType.BASE_FINE_CREDITS,
		"heat_expiry: heat should expire while fines remain due."
	)


func _test_fine_payment_clears_heat() -> void:
	var enforcement := EnforcementType.new()
	enforcement.report_violation(
		"system.nightfall",
		"belt.alpha",
		"gen_cinder_foundry",
		1000
	)
	var denied := enforcement.pay_fine(
		"system.nightfall",
		"gen_cinder_foundry",
		EnforcementType.BASE_FINE_CREDITS - 1
	)
	var paid := enforcement.pay_fine(
		"system.nightfall",
		"gen_cinder_foundry",
		EnforcementType.BASE_FINE_CREDITS
	)
	_expect(
		not bool(denied.get("paid", false))
			and bool(paid.get("paid", false))
			and bool(paid.get("heat_cleared", false))
			and enforcement.fine_due("system.nightfall", "gen_cinder_foundry") == 0
			and not enforcement.is_heat_active("system.nightfall", "gen_cinder_foundry"),
		"fine_payment: full payment should clear fine and active heat."
	)


func _test_enforcement_ship_marker() -> void:
	var ship := Node.new()
	EnforcementType.mark_enforcement_ship(
		ship,
		"gen_cinder_foundry",
		"system.nightfall"
	)
	_expect(
		EnforcementType.is_enforcement_ship(ship)
			and str(ship.get_meta("enforcement_faction", "")) == "gen_cinder_foundry",
		"ship_marker: enforcement metadata was not applied."
	)
	ship.free()


func _test_unwitnessed_global_report_does_not_dispatch() -> void:
	var gs = root.get_node("GlobalState")
	var previous_player = gs.player
	var previous_root = gs.active_system_root
	var previous_entities: Array = gs.active_system_entities.duplicate()
	var player_node := Node3D.new()
	var asteroid := Node3D.new()
	gs.reset_for_restart()
	gs.current_system_id = "system.test"
	root.add_child(player_node)
	root.add_child(asteroid)
	gs.player = player_node
	asteroid.set_meta("belt_owner_faction", "zenith")
	asteroid.set_meta("belt_id", "quiet_belt")

	var result: Dictionary = gs.report_player_mined_asteroid(asteroid)
	_expect(
		not bool(result.get("dispatch", false))
			and str(result.get("reason", "")) == "unwitnessed",
		"global_unwitnessed: mining without a nearby miner should not dispatch enforcement."
	)

	asteroid.queue_free()
	player_node.queue_free()
	gs.player = previous_player
	gs.active_system_root = previous_root
	gs.active_system_entities = previous_entities


func _test_witnessed_global_report_dispatches_and_spawns() -> void:
	var gs = root.get_node("GlobalState")
	var previous_player = gs.player
	var previous_root = gs.active_system_root
	var previous_entities: Array = gs.active_system_entities.duplicate()
	var system_root := Node3D.new()
	var player_node := Node3D.new()
	var asteroid := Node3D.new()
	var witness := Node3D.new()
	gs.reset_for_restart()
	gs.current_system_id = "system.test"
	root.add_child(system_root)
	system_root.add_child(player_node)
	system_root.add_child(asteroid)
	system_root.add_child(witness)
	gs.active_system_root = system_root
	gs.player = player_node
	player_node.position = Vector3.ZERO
	asteroid.position = Vector3(20.0, 0.0, 0.0)
	asteroid.set_meta("belt_owner_faction", "zenith")
	asteroid.set_meta("belt_id", "watched_belt")
	witness.position = Vector3(30.0, 0.0, 0.0)
	witness.set("name", "Witness Miner")
	witness.set_meta("is_mining_witness", true)
	witness.set("faction", "zenith")
	gs.active_system_entities.append(witness)

	var result: Dictionary = gs.report_player_mined_asteroid(asteroid)
	var enforcement_count := 0
	for entity in system_root.get_children():
		if EnforcementType.is_enforcement_ship(entity):
			enforcement_count += 1
	_expect(
		bool(result.get("dispatch", false))
			and enforcement_count == EnforcementType.RESPONSE_SHIP_COUNT,
		"global_witnessed: witnessed mining should spawn two enforcement ships. result=%s count=%d" % [
			str(result),
			enforcement_count,
		]
	)

	system_root.queue_free()
	gs.player = previous_player
	gs.active_system_root = previous_root
	gs.active_system_entities = previous_entities


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
