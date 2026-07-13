extends SceneTree

# READY_TO_TURN_IN lifecycle: objective completion transitions the instance
# to READY_TO_TURN_IN, COMPLETED is only reachable through it, the state
# persists across the real save pipeline, and a timed contract can still
# expire while waiting for the hand-in.

const InstanceType := preload("res://scripts/domain/MissionInstance.gd")
const MigratorType := preload("res://scripts/persistence/SaveMigrator.gd")
const RegistryType := preload("res://scripts/registry/SystemRegistry.gd")

const TEST_PATH := "user://mission_state_transition_fixture.json"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_transition_rules()
	_test_ready_state_round_trips_through_dict()
	_test_objective_completion_marks_ready_and_persists()
	_test_timed_contract_expires_while_ready()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Mission state transition tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_transition_rules() -> void:
	var inst = InstanceType.new()
	inst.state = InstanceType.State.ACTIVE
	_expect(
		not inst.transition_to(InstanceType.State.COMPLETED),
		"ACTIVE -> COMPLETED should remain invalid."
	)
	_expect(
		inst.state == InstanceType.State.ACTIVE,
		"Refused transition should not change the state."
	)
	_expect(
		inst.transition_to(InstanceType.State.READY_TO_TURN_IN)
			and inst.transition_to(InstanceType.State.COMPLETED),
		"ACTIVE -> READY_TO_TURN_IN -> COMPLETED should be valid."
	)
	for terminal in [
		InstanceType.State.EXPIRED,
		InstanceType.State.ABANDONED,
		InstanceType.State.ACTIVE,
	]:
		var ready = InstanceType.new()
		ready.state = InstanceType.State.READY_TO_TURN_IN
		_expect(
			ready.transition_to(terminal),
			"READY_TO_TURN_IN -> %s should be valid."
				% InstanceType.state_name_of(terminal)
		)


func _test_ready_state_round_trips_through_dict() -> void:
	var inst = InstanceType.new()
	inst.state = InstanceType.State.READY_TO_TURN_IN
	inst.data = {"runtime_id": "mission.runtime.ready_round_trip"}
	var serialized: Dictionary = inst.to_dict()
	_expect(
		str(serialized.get("_instance_state", "")) == "READY_TO_TURN_IN",
		"to_dict did not serialize READY_TO_TURN_IN."
	)
	var restored = InstanceType.from_dict(serialized)
	_expect(
		restored.state == InstanceType.State.READY_TO_TURN_IN,
		"from_dict did not restore READY_TO_TURN_IN."
	)


func _test_objective_completion_marks_ready_and_persists() -> void:
	var qm = root.get_node("QuestManager")
	var clock = root.get_node("CampaignClock")
	var gs = root.get_node("GlobalState")
	qm.reset_for_restart()
	clock.restore_state({"total_minutes": 480})
	gs.clear_cargo()

	_expect(
		qm.accept_quest(_ore_offer(false), _accept_choice()),
		"Ore offer was rejected on acceptance."
	)
	if not qm.is_quest_active():
		return
	var instance = qm._collection.get_focused()
	_expect(
		instance.state == InstanceType.State.ACTIVE,
		"Accepted mission should start ACTIVE."
	)

	gs.cargo_type = gs.CargoType.ORE
	gs.cargo = 10.0
	qm.deliver_partial(10.0)
	_expect(
		instance.state == InstanceType.State.READY_TO_TURN_IN,
		"Objective completion did not transition to READY_TO_TURN_IN."
	)

	# Persist through the real save pipeline and reload.
	var quest_array: Array = qm.capture_all_quests()
	_expect(
		quest_array.size() == 1
			and str(quest_array[0].get("_instance_state", ""))
				== "READY_TO_TURN_IN",
		"capture_all_quests did not carry the ready state."
	)
	var registry := RegistryType.load_default()
	var prepared := MigratorType.prepare_for_save(
		_runtime_save(quest_array),
		registry
	)
	_expect(
		bool(prepared.get("ok", false)),
		"prepare_for_save refused a READY_TO_TURN_IN mission: %s"
			% str(prepared.get("error", ""))
	)
	if not bool(prepared.get("ok", false)):
		return
	_write_text(TEST_PATH, JSON.stringify(prepared["data"]))
	qm.reset_for_restart()
	var loaded := MigratorType.load_for_runtime(
		TEST_PATH,
		RegistryType.load_default()
	)
	_expect(
		bool(loaded.get("ok", false)),
		"load_for_runtime failed: %s" % str(loaded.get("error", ""))
	)
	if not bool(loaded.get("ok", false)):
		return
	_expect(
		qm.restore_all_quests((loaded["data"] as Dictionary).get("quest", [])),
		"restore_all_quests refused the reloaded mission: %s"
			% qm.last_validation_error
	)
	var restored = qm._collection.get_focused()
	_expect(
		restored != null
			and restored.state == InstanceType.State.READY_TO_TURN_IN,
		"Reload did not restore READY_TO_TURN_IN."
	)

	# Turn in: the instance reaches COMPLETED through the valid path.
	_expect(
		qm.is_quest_completed(),
		"Restored mission lost its completed objective."
	)
	qm.complete_quest()
	_expect(
		restored.state == InstanceType.State.COMPLETED,
		"complete_quest did not land the instance in COMPLETED."
	)
	_expect(
		not qm.is_quest_active(),
		"complete_quest did not remove the mission."
	)


func _test_timed_contract_expires_while_ready() -> void:
	var qm = root.get_node("QuestManager")
	var clock = root.get_node("CampaignClock")
	var gs = root.get_node("GlobalState")
	qm.reset_for_restart()
	clock.restore_state({"total_minutes": 480})
	gs.clear_cargo()

	_expect(
		qm.accept_quest(_ore_offer(true), _accept_choice()),
		"Timed ore offer was rejected on acceptance."
	)
	if not qm.is_quest_active():
		return
	var instance = qm._collection.get_focused()
	gs.cargo_type = gs.CargoType.ORE
	gs.cargo = 10.0
	qm.deliver_partial(10.0)
	_expect(
		instance.state == InstanceType.State.READY_TO_TURN_IN,
		"Timed mission objective completion did not mark ready."
	)
	clock.advance_minutes(10)
	_expect(
		qm.check_active_quest_expiration(),
		"Deadline passing did not expire the ready mission."
	)
	_expect(
		instance.state == InstanceType.State.EXPIRED,
		"Expiration from READY_TO_TURN_IN did not land in EXPIRED."
	)
	_expect(
		not qm.is_quest_active(),
		"Expired mission was not removed."
	)


func _runtime_save(quest_array: Array) -> Dictionary:
	return {
		"version": MigratorType.CURRENT_VERSION,
		"current_system_id": "start_system",
		"arrival_gate_id": "",
		"player": {
			"health": 90.0,
			"shield": 25.0,
			"position": [1.0, 2.0, 3.0],
			"rotation": [0.0, 0.5, 0.0],
		},
		"global": {
			"credits": 1500,
			"cargo": 0.0,
		},
		"quest": quest_array,
		"systems": {
			"start_system": {},
		},
	}


func _ore_offer(timed: bool) -> Dictionary:
	var offer := {
		"title": "Ready State Ore",
		"faction": "zenith",
		"agent_name": "Broker Kaelen",
		"dialogue": "Bring the ore in.",
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": 10.0,
			"reward_credits": 120,
		},
		"choices": [],
	}
	if timed:
		offer["timing"] = {
			"timed": true,
			"duration_minutes": 10,
			"expiration_policy": "expire",
		}
	return offer


func _accept_choice() -> Dictionary:
	return {
		"text": "Accepted.",
		"consequence": {
			"credits_immediate": 0,
			"reputation_change": {},
			"combat_multiplier": 1.0,
			"reward_credits_multiplier": 1.0,
			"dialogue_response": "Proceed.",
		},
	}


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write the state transition fixture.")
		return
	file.store_string(text)


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
