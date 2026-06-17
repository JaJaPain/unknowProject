extends SceneTree

const MI := preload("res://scripts/domain/MissionInstance.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_create_active_sets_state()
	_test_create_active_detects_board_lane()
	_test_create_active_detects_agent_lane()
	_test_valid_transition_active_to_completed()
	_test_valid_transition_active_to_abandoned()
	_test_valid_transition_active_to_expired()
	_test_valid_transition_active_to_resolved()
	_test_valid_transition_active_to_ready()
	_test_valid_transition_ready_to_completed()
	_test_valid_transition_ready_back_to_active()
	_test_invalid_transition_active_to_offered()
	_test_invalid_transition_completed_to_active()
	_test_invalid_transition_expired_to_active()
	_test_invalid_transition_abandoned_to_active()
	_test_terminal_states()
	_test_non_terminal_states()
	_test_to_dict_includes_instance_fields()
	_test_from_dict_round_trip()
	_test_from_dict_without_instance_state_defaults_active()
	_test_from_dict_board_from_public_board_flag()
	_test_get_field_compat_method()
	_test_data_mutation_persists()
	_test_state_name_round_trip()
	_test_offered_to_accepted_to_active()
	_test_full_lifecycle_accept_to_complete()

	if _failures.is_empty():
		print("[PASS] Mission instance tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_create_active_sets_state() -> void:
	var inst = MI.create_active(_sample_state())
	_expect(
		inst.state == MI.State.ACTIVE,
		"create_active: state was not ACTIVE."
	)


func _test_create_active_detects_board_lane() -> void:
	var state = _sample_state()
	state["public_board"] = true
	var inst = MI.create_active(state)
	_expect(
		inst.source_lane == MI.SourceLane.BOARD,
		"create_active: board lane not detected from public_board flag."
	)


func _test_create_active_detects_agent_lane() -> void:
	var inst = MI.create_active(_sample_state())
	_expect(
		inst.source_lane == MI.SourceLane.AGENT,
		"create_active: agent lane not set for non-board mission."
	)


func _test_valid_transition_active_to_completed() -> void:
	var inst = _active_instance()
	_expect(
		not inst.transition_to(MI.State.COMPLETED),
		"active_to_completed: ACTIVE should not transition directly to COMPLETED."
	)


func _test_valid_transition_active_to_abandoned() -> void:
	var inst = _active_instance()
	_expect(
		inst.transition_to(MI.State.ABANDONED),
		"active_to_abandoned: valid transition rejected."
	)
	_expect(
		inst.state == MI.State.ABANDONED,
		"active_to_abandoned: state not updated."
	)


func _test_valid_transition_active_to_expired() -> void:
	var inst = _active_instance()
	_expect(
		inst.transition_to(MI.State.EXPIRED),
		"active_to_expired: valid transition rejected."
	)


func _test_valid_transition_active_to_resolved() -> void:
	var inst = _active_instance()
	_expect(
		inst.transition_to(MI.State.RESOLVED_BY_BRANCH),
		"active_to_resolved: valid transition rejected."
	)


func _test_valid_transition_active_to_ready() -> void:
	var inst = _active_instance()
	_expect(
		inst.transition_to(MI.State.READY_TO_TURN_IN),
		"active_to_ready: valid transition rejected."
	)


func _test_valid_transition_ready_to_completed() -> void:
	var inst = _active_instance()
	inst.transition_to(MI.State.READY_TO_TURN_IN)
	_expect(
		inst.transition_to(MI.State.COMPLETED),
		"ready_to_completed: valid transition rejected."
	)


func _test_valid_transition_ready_back_to_active() -> void:
	var inst = _active_instance()
	inst.transition_to(MI.State.READY_TO_TURN_IN)
	_expect(
		inst.transition_to(MI.State.ACTIVE),
		"ready_to_active: valid transition rejected."
	)


func _test_invalid_transition_active_to_offered() -> void:
	var inst = _active_instance()
	_expect(
		not inst.transition_to(MI.State.OFFERED),
		"active_to_offered: backward transition should be rejected."
	)


func _test_invalid_transition_completed_to_active() -> void:
	var inst = _active_instance()
	inst.transition_to(MI.State.READY_TO_TURN_IN)
	inst.transition_to(MI.State.COMPLETED)
	_expect(
		not inst.transition_to(MI.State.ACTIVE),
		"completed_to_active: terminal state should reject transitions."
	)


func _test_invalid_transition_expired_to_active() -> void:
	var inst = _active_instance()
	inst.transition_to(MI.State.EXPIRED)
	_expect(
		not inst.transition_to(MI.State.ACTIVE),
		"expired_to_active: terminal state should reject transitions."
	)


func _test_invalid_transition_abandoned_to_active() -> void:
	var inst = _active_instance()
	inst.transition_to(MI.State.ABANDONED)
	_expect(
		not inst.transition_to(MI.State.ACTIVE),
		"abandoned_to_active: terminal state should reject transitions."
	)


func _test_terminal_states() -> void:
	for terminal_state in MI.TERMINAL_STATES:
		var inst = MI.new()
		inst.state = terminal_state
		_expect(
			inst.is_terminal(),
			"terminal: state %s should be terminal." % MI.state_name_of(terminal_state)
		)


func _test_non_terminal_states() -> void:
	for non_terminal in [MI.State.OFFERED, MI.State.ACCEPTED, MI.State.ACTIVE, MI.State.READY_TO_TURN_IN]:
		var inst = MI.new()
		inst.state = non_terminal
		_expect(
			not inst.is_terminal(),
			"non_terminal: state %s should not be terminal." % MI.state_name_of(non_terminal)
		)


func _test_to_dict_includes_instance_fields() -> void:
	var inst = MI.create_active(_sample_state())
	var d = inst.to_dict()
	_expect(
		d.get("_instance_state", "") == "ACTIVE"
			and d.get("_source_lane", "") == "AGENT",
		"to_dict: missing instance metadata fields."
	)


func _test_from_dict_round_trip() -> void:
	var inst = MI.create_active(_sample_state())
	inst.transition_to(MI.State.READY_TO_TURN_IN)
	var d = inst.to_dict()
	var restored = MI.from_dict(d)
	_expect(
		restored.state == MI.State.READY_TO_TURN_IN
			and restored.source_lane == MI.SourceLane.AGENT
			and restored.runtime_id == inst.runtime_id
			and restored.title == inst.title,
		"round_trip: state or data not preserved through to_dict/from_dict."
	)


func _test_from_dict_without_instance_state_defaults_active() -> void:
	var restored = MI.from_dict(_sample_state())
	_expect(
		restored.state == MI.State.ACTIVE,
		"from_dict_default: missing _instance_state should default to ACTIVE."
	)


func _test_from_dict_board_from_public_board_flag() -> void:
	var state = _sample_state()
	state["public_board"] = true
	var restored = MI.from_dict(state)
	_expect(
		restored.source_lane == MI.SourceLane.BOARD,
		"from_dict_board: public_board flag should set BOARD lane."
	)


func _test_get_field_compat_method() -> void:
	var inst = MI.create_active(_sample_state())
	_expect(
		inst.get_field("title", "") == "Test Kill Contract"
			and inst.get_field("nonexistent", "fallback") == "fallback",
		"get_field: compat method did not return expected values."
	)


func _test_data_mutation_persists() -> void:
	var inst = MI.create_active(_sample_state())
	inst.data["current_count"] = 2
	_expect(
		int(inst.data.get("current_count", 0)) == 2,
		"data_mutation: direct data write did not persist."
	)


func _test_state_name_round_trip() -> void:
	var all_ok = true
	for state_val in MI._STATE_NAMES.keys():
		var name_str: String = MI._STATE_NAMES[state_val]
		var back: int = MI._STATE_BY_NAME[name_str]
		if back != state_val:
			all_ok = false
			break
	_expect(all_ok, "state_name_round_trip: name/enum mismatch.")


func _test_offered_to_accepted_to_active() -> void:
	var inst = MI.new()
	inst.state = MI.State.OFFERED
	inst.data = _sample_state()
	_expect(
		inst.transition_to(MI.State.ACCEPTED)
			and inst.transition_to(MI.State.ACTIVE),
		"offered_accepted_active: full early lifecycle failed."
	)


func _test_full_lifecycle_accept_to_complete() -> void:
	var inst = MI.create_active(_sample_state())
	var ok = inst.transition_to(MI.State.READY_TO_TURN_IN)
	ok = ok and inst.transition_to(MI.State.COMPLETED)
	_expect(
		ok and inst.is_terminal() and inst.state == MI.State.COMPLETED,
		"full_lifecycle: ACTIVE -> READY -> COMPLETED failed."
	)


func _sample_state() -> Dictionary:
	return {
		"mission_schema_version": 1,
		"definition_id": "mission.test.kill_contract",
		"runtime_id": "mission.runtime.abc123def456ab",
		"title": "Test Kill Contract",
		"faction": "zenith",
		"faction_id": "faction.zenith",
		"agent_name": "Director Voss",
		"giver_npc_id": "npc.voss",
		"dialogue": "Destroy the hostiles.",
		"objective_type": "KILL_SHIPS",
		"combat_multiplier": 1.0,
		"reward_credits_multiplier": 1.0,
		"reward_credits": 150,
		"choice_text_selected": "Accepted.",
		"agent_response": "Proceed.",
		"system_id": "system.start",
		"target_spawn_sequence": 0,
		"timing": {},
		"is_timed": false,
		"is_urgent": false,
		"accepted_time_minutes": 0,
		"expires_after_minutes": 0,
		"deadline_time_minutes": 0,
		"expiration_policy": "",
		"base_reward_credits": 150,
		"urgent_reward_multiplier": 1.0,
		"public_board": false,
		"public_board_template_id": "",
		"public_board_turn_in_line": "",
		"public_board_text_is_fallback": false,
		"target_faction": "zenith",
		"count_required": 3,
		"current_count": 0,
	}


func _active_instance():
	return MI.create_active(_sample_state())


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
