extends SceneTree

var CheckpointStoreType: GDScript = null
var SlotRegistryType: GDScript = null
var SystemRegistryType: GDScript = null

const TEST_ROOT := "user://campaign_checkpoint_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"

var _failures: Array[String] = []


func _initialize() -> void:
	CheckpointStoreType = load(
		"res://scripts/persistence/CampaignCheckpointStore.gd"
	)
	SlotRegistryType = load("res://scripts/persistence/CampaignSlotRegistry.gd")
	SystemRegistryType = load("res://scripts/registry/SystemRegistry.gd")
	if CheckpointStoreType == null \
			or SlotRegistryType == null \
			or SystemRegistryType == null:
		push_error("[FAIL] Checkpoint persistence scripts did not compile.")
		quit(1)
		return
	_cleanup()
	_test_safe_capture_restore_and_recovery()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Campaign safe checkpoint bundle tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_safe_capture_restore_and_recovery() -> void:
	var slots: RefCounted = SlotRegistryType.open(TEST_ROOT)
	var created: Dictionary = slots.create_campaign(
		"slot_01",
		"Checkpoint Fixture",
		"phase-2-test",
		_runtime_state(50, 100.0, "initial"),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return
	var initial_checkpoint: Dictionary = created["checkpoint"]
	_expect(
		not _contains_tactical_key(initial_checkpoint.get("state", {})),
		"Initial campaign checkpoint retained tactical state."
	)

	var store: RefCounted = CheckpointStoreType.open(CAMPAIGN_PATH)
	_expect(
		store.is_valid(),
		"Checkpoint store is invalid: %s" % store.validation.summary()
	)
	if not store.is_valid():
		return
	var manifest_before := FileAccess.get_file_as_string(
		"%s/manifest.json" % CAMPAIGN_PATH
	)
	var initial_map: Dictionary = store.current_map_knowledge()
	_expect(
		"gate.start.to_test" not in initial_map.get("known_gate_ids", [])
			and "gate.start.to_test" not in initial_map.get("rumored_gate_ids", [])
			and "gate.start.to_test" not in initial_map.get("hidden_gate_ids", []),
		"Initial unknown gate should not be pre-seeded into map knowledge."
	)

	var docked: Dictionary = store.capture_autosave(
		_runtime_state(125, 84.0, "dock"),
		{
			"type": "docked",
			"system_id": "system.start",
			"station_id": "station.start.main",
		},
		"dock"
	)
	_expect(bool(docked.get("ok", false)), docked.get("error", ""))
	var dock_bundle: Dictionary = store.load_active_bundle()
	_expect(bool(dock_bundle.get("ok", false)), dock_bundle.get("error", ""))
	if not bool(dock_bundle.get("ok", false)):
		return
	var dock_checkpoint: Dictionary = dock_bundle["checkpoint"]
	_expect(
		dock_checkpoint.get("source_reason") == "dock"
			and dock_checkpoint.get("safe_location", {}).get("station_id")
				== "station.start.main",
		"Dock checkpoint lost its safe station identity."
	)
	_expect(
		not _contains_tactical_key(dock_checkpoint.get("state", {})),
		"Dock checkpoint retained tactical session data."
	)
	var dock_story_state: Dictionary = dock_checkpoint.get(
		"state",
		{}
	).get("story_state", {})
	_expect(
		(dock_story_state.get("knowledge_states", {}) as Dictionary).has(
			"fact.dock"
		)
			and (dock_story_state.get("beat_states", {}) as Dictionary).has(
				"beat.dock"
			),
		"Dock checkpoint did not retain rewindable story_state."
	)
	var manual_copy: Dictionary = store.copy_active_to_manual(
		0,
		"  Before / Dangerous: Flight?  "
	)
	_expect(
		bool(manual_copy.get("ok", false)),
		manual_copy.get("error", "")
	)
	_expect(
		manual_copy.get("display_name", "") == "Before Dangerous Flight",
		"Manual checkpoint name was not sanitized predictably."
	)
	_expect(
		manual_copy.get("checkpoint_id", "") == dock_checkpoint.get("id", ""),
		"Manual checkpoint did not copy the active safe checkpoint."
	)
	var manual_bundle: Dictionary = store.load_manual_bundle(0)
	_expect(
		bool(manual_bundle.get("ok", false))
			and JSON.stringify(
				manual_bundle.get("checkpoint", {}),
				"",
				true
			) == JSON.stringify(dock_bundle.get("checkpoint", {}), "", true)
			and JSON.stringify(
				manual_bundle.get("map_knowledge", {}),
				"",
				true
			) == JSON.stringify(
				dock_bundle.get("map_knowledge", {}),
				"",
				true
			),
		"Manual checkpoint payload was not an exact safe-bundle copy."
	)
	var overwrite_required: Dictionary = store.copy_active_to_manual(
		0,
		"Replacement"
	)
	_expect(
		not bool(overwrite_required.get("ok", false))
			and bool(overwrite_required.get("requires_overwrite", false)),
		"Occupied manual checkpoint did not require overwrite confirmation."
	)

	var undocked: Dictionary = store.capture_autosave(
		_runtime_state(875, 100.0, "undock"),
		{
			"type": "docked",
			"system_id": "system.start",
			"station_id": "station.start.main",
		},
		"undock"
	)
	_expect(bool(undocked.get("ok", false)), undocked.get("error", ""))
	var undock_state: Dictionary = store.runtime_state_from_active()
	_expect(
		bool(undock_state.get("ok", false))
			and undock_state.get("source_reason") == "undock"
			and int(
				undock_state.get("state", {}).get("global", {}).get(
					"credits",
					0
				)
			) == 875,
		"Pre-undock checkpoint did not retain station-visit changes."
	)
	var preserved_manual: Dictionary = store.runtime_state_from_manual(0)
	_expect(
		bool(preserved_manual.get("ok", false))
			and int(
				preserved_manual.get("state", {}).get("global", {}).get(
					"credits",
					0
				)
			) == 125,
		"Later autosave changed the earlier manual checkpoint copy."
	)
	var overwritten: Dictionary = store.copy_active_to_manual(
		0,
		"After Station Visit",
		true
	)
	_expect(bool(overwritten.get("ok", false)), overwritten.get("error", ""))
	_expect(
		int(
			store.runtime_state_from_manual(0).get("state", {}).get(
				"global",
				{}
			).get("credits", 0)
		) == 875,
		"Confirmed overwrite did not replace the manual checkpoint."
	)
	_expect(
		bool(store.copy_active_to_manual(1, "Second Copy").get("ok", false)),
		"Both manual checkpoint slots were not independently writable."
	)
	var manual_entries: Array = store.list_manual_checkpoints()
	var all_manual_slots_occupied: bool = manual_entries.size() == 2
	for entry in manual_entries:
		all_manual_slots_occupied = all_manual_slots_occupied \
			and bool(entry.get("occupied", false))
	_expect(
		all_manual_slots_occupied,
		"Manual checkpoint listing did not report two occupied slots."
	)
	var renamed_manual: Dictionary = store.rename_manual_checkpoint(
		1,
		"  Second / Renamed  "
	)
	_expect(
		bool(renamed_manual.get("ok", false))
			and renamed_manual.get("display_name", "")
				== "Second Renamed"
			and store.list_manual_checkpoints()[1].get(
				"display_name",
				""
			) == "Second Renamed",
		"Manual checkpoint rename did not update sanitized metadata."
	)
	_expect(
		not bool(store.copy_active_to_manual(2, "Invalid").get("ok", false))
			and not bool(store.copy_active_to_manual(
				0,
				" /// "
			).get("ok", false)),
		"Invalid manual slot or empty sanitized name was accepted."
	)

	_expect(
		store.mark_gates_known([
			"gate.start.to_test",
			"gate.gen.frontier.first.return",
		]),
		"Handcrafted route discovery could not mark gates known."
	)
	var gate: Dictionary = store.capture_autosave(
		_runtime_state(990, 63.0, "gate"),
		{
			"type": "gate_arrival",
			"system_id": "system.gen.frontier.first",
			"gate_id": "gate.gen.frontier.first.return",
		},
		"gate_arrival"
	)
	_expect(bool(gate.get("ok", false)), gate.get("error", ""))
	var gate_bundle: Dictionary = store.load_active_bundle()
	_expect(
		bool(gate_bundle.get("ok", false))
			and gate_bundle.get("checkpoint", {}).get(
				"safe_location",
				{}
			).get("gate_id") == "gate.gen.frontier.first.return",
		"Gate checkpoint did not become the rolling autosave."
	)
	_expect(
		"gate.start.to_test" in gate_bundle.get(
			"map_knowledge",
			{}
		).get("known_gate_ids", [])
			and "gate.gen.frontier.first.return" in gate_bundle.get(
				"map_knowledge",
				{}
			).get("known_gate_ids", []),
		"Gate arrival checkpoint did not retain route discovery."
	)
	var older_manual_state: Dictionary = store.runtime_state_from_manual(0)
	_expect(
		store.restore_map_knowledge(
			older_manual_state.get("map_knowledge", {})
		)
			and "gate.start.to_test" not in store.current_map_knowledge().get(
				"known_gate_ids",
				[]
			)
			and "gate.gen.frontier.first.return" not in store.current_map_knowledge().get(
				"known_gate_ids",
				[]
			),
		"Restoring an older checkpoint did not rewind map visibility."
	)
	_expect(
		FileAccess.get_file_as_string("%s/manifest.json" % CAMPAIGN_PATH)
			== manifest_before,
		"Map discovery or rewind changed the permanent manifest."
	)

	var gate_path := str(store.index.get("autosave", {}).get("path", ""))
	_write_text(
		"%s/%s/checkpoint.json" % [CAMPAIGN_PATH, gate_path],
		"{ damaged"
	)
	var recovered: Dictionary = store.load_active_bundle()
	_expect(
		bool(recovered.get("ok", false))
			and bool(recovered.get("recovered", false))
			and recovered.get("checkpoint", {}).get("source_reason")
				== "undock",
		"Damaged latest checkpoint did not restore the prior safe bundle."
	)
	_expect(
		int(
			recovered.get("checkpoint", {}).get("state", {}).get(
				"global",
				{}
			).get("credits", 0)
		) == 875,
		"Recovered checkpoint did not preserve the prior station state."
	)
	_expect(
		_count_autosave_bundle_directories() <= 2,
		"Rolling autosave retained more than the active and recovery bundles."
	)

	var dead_state := _runtime_state(1, 0.0, "dead")
	dead_state["dead"] = true
	_expect(
		not bool(store.capture_autosave(
			dead_state,
			{
				"type": "docked",
				"system_id": "system.start",
				"station_id": "station.start.main",
			},
			"dock"
		).get("ok", false)),
		"Dead gameplay state created a safe checkpoint."
	)


func _runtime_state(
	credits: int,
	health: float,
	label: String
) -> Dictionary:
	return {
		"version": 2,
		"current_system_id": "system.start",
		"arrival_gate_id": "gate.start.to_test",
		"player": {
			"health": health,
			"shield": 15.0,
			"position": [10.0, 20.0, 30.0],
			"rotation": [0.0, 1.0, 0.0],
			"velocity": [200.0, 0.0, 0.0],
			"nav_mode": "APPROACH",
			"target_position": [999.0, 0.0, 0.0],
			"is_docked": label in ["dock", "undock"],
		},
		"global": {
			"credits": credits,
			"cargo": 12.0,
			"cargo_type": 1,
			"cargo_special": {},
			"storage_ore": 44.0,
			"upgrades": {"power": {"tier": 2, "path": "standard"}},
			"reputations": {"zenith": 55.0},
			"faction_kills": {},
		},
		"quest": {
			"title": "Checkpoint Test",
			"objective_type": "DELIVER_ORE",
			"amount_required": 25.0,
			"partial_delivered": 5.0,
			"faction": "zenith",
		},
		"story_state": _story_state(label),
		"systems": {
			"system.start": {
				"entities": {
					"asteroid.start.001": {
						"entity_id": "asteroid.start.001",
						"resources": 21.0,
					},
				},
				"aggro": {"enemy": true},
				"projectiles": [{"damage": 10}],
			},
		},
		"attack_target": "entity.enemy.001",
		"autopilot_waypoint": [500.0, 0.0, 0.0],
		"jump_transition": label == "gate",
	}


func _story_state(label: String) -> Dictionary:
	return {
		"schema_version": 2,
		"document_type": "story_state",
		"chapter": 2 if label == "dock" else 1,
		"story_revision": 5 if label == "dock" else 1,
		"knowledge_revision": 6 if label == "dock" else 1,
		"mission_history_revision": 7 if label == "dock" else 1,
		"knowledge_states": {
			"fact.%s" % label: {
				"state": "known",
				"source": "checkpoint_store_test",
				"learned_at_minute": 10,
				"confidence": "direct",
				"public_text": "%s story fact" % label,
			},
		},
		"beat_states": {
			"beat.%s" % label: {
				"state": "completed",
				"completed_at_minute": 11,
			},
		},
	}


func _contains_tactical_key(value: Variant) -> bool:
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			if str(key) in CheckpointStoreType.TACTICAL_KEYS:
				return true
			if _contains_tactical_key((value as Dictionary)[key]):
				return true
	elif value is Array:
		for item in value:
			if _contains_tactical_key(item):
				return true
	return false


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)


func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_directory(absolute)


func _count_autosave_bundle_directories() -> int:
	var directory := DirAccess.open(
		"%s/checkpoints/autosave" % CAMPAIGN_PATH
	)
	if directory == null:
		return 0
	var count := 0
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and entry != "." and entry != "..":
			count += 1
		entry = directory.get_next()
	directory.list_dir_end()
	return count


func _remove_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := "%s/%s" % [path, entry]
			if directory.current_is_dir():
				_remove_directory(child)
			else:
				DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
