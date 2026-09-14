extends SceneTree

# Phase 7 exit-gate sim: save after accepting, reload, complete, and turn in;
# the mission-keyed Kaelen reaction bundle must remain ready and correct.
# Runs the real pipeline: accept_quest -> store bundle -> capture_all_quests
# -> SaveMigrator.prepare_for_save -> JSON file -> load_for_runtime ->
# restore_all_quests -> objective completion -> turn-in line read.

const MigratorType := preload(
	"res://scripts/persistence/SaveMigrator.gd"
)
const RegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_PATH := "user://kaelen_reaction_bundle_fixture.json"

const ACCEPT_COMPLETION_LINE := (
	"The refinery crews at Kova get their ore and we get paid. Clean work."
)
const ACCEPT_ABANDON_LINE := (
	"You walked off a Zenith ore contract. That follows you, pilot."
)
const OBJECTIVE_COMPLETION_LINE := (
	"Full load banked before the deadline. Kova's smelters stay lit, "
	+ "and the important part: everyone got paid."
)
const OBJECTIVE_ABANDON_LINE := (
	"Dropping it now, after the ore's banked? That would be a first."
)

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_bundle_survives_save_reload_complete_turn_in()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Kaelen reaction bundle persistence tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_bundle_survives_save_reload_complete_turn_in() -> void:
	var qm = root.get_node("QuestManager")
	var clock = root.get_node("CampaignClock")
	var gs = root.get_node("GlobalState")
	qm.reset_for_restart()
	clock.restore_state({"total_minutes": 480})
	gs.clear_cargo()

	# 1. Accept, then store the acceptance-time reaction bundle
	#    (what UIManager does when the LLM callback resolves).
	_expect(
		qm.accept_quest(_ore_offer(), _accept_choice()),
		"Ore offer was rejected on acceptance."
	)
	if not qm.is_quest_active():
		return
	var runtime_id := str(qm.active_quest.get("runtime_id", ""))
	_expect(
		not runtime_id.is_empty(),
		"Accepted mission has no runtime id."
	)
	_expect(
		qm.store_active_kaelen_reaction_bundle(
			runtime_id,
			ACCEPT_COMPLETION_LINE,
			ACCEPT_ABANDON_LINE,
			"llm_kaelen_reaction_mission_acceptance"
		),
		"Acceptance-time Kaelen reaction bundle was not stored."
	)

	# 2. Save through the real pipeline.
	var quest_array: Array = qm.capture_all_quests()
	_expect(
		quest_array.size() == 1,
		"capture_all_quests did not capture the accepted mission: %s"
			% qm.last_validation_error
	)
	if quest_array.size() != 1:
		return
	var registry := RegistryType.load_default()
	_expect(registry.is_valid(), "System registry failed to load.")
	var prepared := MigratorType.prepare_for_save(
		_runtime_save(quest_array),
		registry
	)
	_expect(
		bool(prepared.get("ok", false)),
		"prepare_for_save failed: %s" % str(prepared.get("error", ""))
	)
	if not bool(prepared.get("ok", false)):
		return
	_write_text(TEST_PATH, JSON.stringify(prepared["data"]))

	# 3. Simulate an app restart, then reload from disk.
	qm.reset_for_restart()
	_expect(
		not qm.is_quest_active(),
		"Reset should clear the active mission before reload."
	)
	var fresh_registry := RegistryType.load_default()
	var loaded := MigratorType.load_for_runtime(TEST_PATH, fresh_registry)
	_expect(
		bool(loaded.get("ok", false)),
		"load_for_runtime failed: %s" % str(loaded.get("error", ""))
	)
	if not bool(loaded.get("ok", false)):
		return
	var loaded_quests: Variant = (loaded["data"] as Dictionary).get("quest", [])
	_expect(
		loaded_quests is Array and (loaded_quests as Array).size() == 1,
		"Reloaded save lost the mission array."
	)
	_expect(
		qm.restore_all_quests(loaded_quests),
		"restore_all_quests refused the reloaded mission: %s"
			% qm.last_validation_error
	)

	# 4. The contextual line is still ready and keyed correctly after reload.
	_expect(
		str(qm.active_quest.get("runtime_id", "")) == runtime_id,
		"Reload changed the mission runtime id."
	)
	_expect(
		qm.active_kaelen_reaction_line("completion") == ACCEPT_COMPLETION_LINE,
		"Completion line was lost or altered across save/reload."
	)
	_expect(
		qm.active_kaelen_reaction_line("abandon") == ACCEPT_ABANDON_LINE,
		"Abandon line was lost or altered across save/reload."
	)

	# 5. A stale runtime id cannot clobber the restored bundle.
	_expect(
		not qm.store_active_kaelen_reaction_bundle(
			"mission.runtime.stale",
			"wrong line",
			"wrong line",
			"llm_kaelen_reaction_stale"
		),
		"A stale runtime id was allowed to overwrite the reaction bundle."
	)
	_expect(
		qm.active_kaelen_reaction_line("completion") == ACCEPT_COMPLETION_LINE,
		"Stale-id store attempt corrupted the completion line."
	)

	# 6. Complete the objective through the real progression path and
	#    refresh the bundle from the objective-complete snapshot
	#    (what UIManager does on quest_objective_completed_details).
	var objective_snapshots: Array = []
	var on_objective_complete := func(quest_data: Dictionary) -> void:
		objective_snapshots.append(quest_data)
	qm.quest_objective_completed_details.connect(on_objective_complete)
	gs.cargo_type = gs.CargoType.ORE
	gs.cargo = 10.0
	var delivered: float = qm.deliver_partial(10.0)
	qm.quest_objective_completed_details.disconnect(on_objective_complete)
	_expect(
		delivered >= 10.0,
		"Ore delivery did not bank the required amount (%.1f)." % delivered
	)
	_expect(
		qm.is_quest_completed(),
		"Mission objective was not completed after full delivery."
	)
	_expect(
		objective_snapshots.size() == 1,
		"Objective completion did not emit exactly one details snapshot."
	)
	if objective_snapshots.size() != 1:
		return
	var snapshot_runtime_id := str(objective_snapshots[0].get("runtime_id", ""))
	_expect(
		snapshot_runtime_id == runtime_id,
		"Objective-complete snapshot carries the wrong runtime id."
	)
	_expect(
		qm.store_active_kaelen_reaction_bundle(
			snapshot_runtime_id,
			OBJECTIVE_COMPLETION_LINE,
			OBJECTIVE_ABANDON_LINE,
			"llm_kaelen_reaction_objective_complete"
		),
		"Objective-complete bundle refresh was rejected after reload."
	)

	# 7. Turn in: UIManager reads the line before complete_quest removes
	#    the mission. The refreshed contextual line must be the one served.
	var turn_in_line: String = qm.active_kaelen_reaction_line("completion")
	_expect(
		turn_in_line == OBJECTIVE_COMPLETION_LINE,
		"Turn-in did not read the refreshed contextual completion line."
	)
	qm.complete_quest()
	_expect(
		not qm.is_quest_active(),
		"complete_quest did not clear the active mission."
	)
	_expect(
		qm.active_kaelen_reaction_line("completion").is_empty(),
		"Completion line remained readable after the mission was removed."
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


func _ore_offer() -> Dictionary:
	return {
		"title": "Kova Smelter Feed",
		"faction": "zenith",
		"agent_name": "Broker Kaelen",
		"dialogue": "Kova's smelters are running dry. Bring them ore.",
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": 10.0,
			"reward_credits": 140,
		},
		"choices": [],
	}


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
		_failures.append("Could not write the persistence fixture.")
		return
	file.store_string(text)


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
