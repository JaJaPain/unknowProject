extends SceneTree

const CheckpointStoreType := preload(
	"res://scripts/persistence/CampaignCheckpointStore.gd"
)
const ChronicleStoreType := preload(
	"res://scripts/persistence/CampaignChronicleStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://phase_2_storage_measurement"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"
const AUTOSAVE_COUNT := 25
const CHRONICLE_EVENT_COUNT := 100


func _initialize() -> void:
	_cleanup()
	var registry := SlotRegistryType.open(TEST_ROOT)
	var system_registry := SystemRegistryType.load_default()
	var create_started := Time.get_ticks_usec()
	var created := registry.create_campaign(
		"slot_01",
		"Phase 2 Measurement",
		"phase-2-measurement",
		_runtime_state(100),
		system_registry
	)
	var create_ms := _elapsed_ms(create_started)
	if not bool(created.get("ok", false)):
		_fail(created.get("error", "Campaign creation failed."))
		return
	var checkpoint_store := CheckpointStoreType.open(CAMPAIGN_PATH)
	var chronicle_store := ChronicleStoreType.open(CAMPAIGN_PATH)
	if not checkpoint_store.is_valid() or not chronicle_store.is_valid():
		_fail("Measurement stores failed to open.")
		return
	checkpoint_store.set_chronicle_context(
		chronicle_store.current_timeline_id(),
		chronicle_store.current_head_event_id()
	)
	var checkpoint_id := str(created.get("checkpoint", {}).get("id", ""))
	var autosave_total_usec := 0
	for save_index in range(AUTOSAVE_COUNT):
		var started := Time.get_ticks_usec()
		var saved := checkpoint_store.capture_autosave(
			_runtime_state(100 + save_index),
			{
				"type": "docked",
				"system_id": "system.start",
				"station_id": "station.start.main",
			},
			"dock"
		)
		autosave_total_usec += Time.get_ticks_usec() - started
		if not bool(saved.get("ok", false)):
			_fail(saved.get("error", "Autosave measurement failed."))
			return
		checkpoint_id = str(saved.get("checkpoint_id", checkpoint_id))
	for slot_index in range(2):
		var copied := checkpoint_store.copy_active_to_manual(
			slot_index,
			"Measurement %d" % (slot_index + 1)
		)
		if not bool(copied.get("ok", false)):
			_fail(copied.get("error", "Manual checkpoint copy failed."))
			return
	var chronicle_total_usec := 0
	for event_index in range(CHRONICLE_EVENT_COUNT):
		var started := Time.get_ticks_usec()
		var appended := chronicle_store.append_event(
			"measurement_event",
			[chronicle_store.campaign["id"]],
			{"index": event_index},
			checkpoint_id
		)
		chronicle_total_usec += Time.get_ticks_usec() - started
		if not bool(appended.get("ok", false)):
			_fail(appended.get("error", "Chronicle measurement failed."))
			return
	var reopen_started := Time.get_ticks_usec()
	var reopened := CheckpointStoreType.open(CAMPAIGN_PATH)
	var reopen_ms := _elapsed_ms(reopen_started)
	if not reopened.is_valid():
		_fail("Measured campaign did not reopen.")
		return
	var stats := _directory_stats(CAMPAIGN_PATH)
	stats["campaign_create_ms"] = create_ms
	stats["average_autosave_ms"] = (
		float(autosave_total_usec) / AUTOSAVE_COUNT / 1000.0
	)
	stats["average_chronicle_append_ms"] = (
		float(chronicle_total_usec) / CHRONICLE_EVENT_COUNT / 1000.0
	)
	stats["campaign_reopen_ms"] = reopen_ms
	stats["autosave_iterations"] = AUTOSAVE_COUNT
	stats["chronicle_events"] = CHRONICLE_EVENT_COUNT
	stats["autosave_bundle_directories"] = _count_directories(
		"%s/checkpoints/autosave" % CAMPAIGN_PATH
	)
	print("[Phase2StorageMeasurement] " + JSON.stringify(stats))
	_cleanup()
	quit(0)


func _runtime_state(credits: int) -> Dictionary:
	var entities := {}
	for entity_index in range(120):
		entities["asteroid.measurement.%03d" % entity_index] = {
			"world_id": "asteroid.measurement.%03d" % entity_index,
			"type": "asteroid",
			"resources": 1000.0 - entity_index,
			"destroyed": false,
		}
	return {
		"current_system_id": "system.start",
		"arrival_gate_id": "",
		"player": {"health": 87.0, "shield": 41.0},
		"global": {
			"credits": credits,
			"cargo": 35.0,
			"storage_ore": 250.0,
			"upgrades": {},
			"reputations": {},
		},
		"quest": {},
		"systems": {"system.start": {"entities": entities}},
	}


func _directory_stats(path: String) -> Dictionary:
	var output := {"bytes": 0, "files": 0, "directories": 0}
	_accumulate_directory(path, output)
	return output


func _accumulate_directory(path: String, output: Dictionary) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := "%s/%s" % [path, entry]
			if directory.current_is_dir():
				output["directories"] = int(output["directories"]) + 1
				_accumulate_directory(child, output)
			else:
				output["files"] = int(output["files"]) + 1
				output["bytes"] = int(output["bytes"]) + FileAccess.get_file_as_bytes(
					child
				).size()
		entry = directory.get_next()
	directory.list_dir_end()


func _count_directories(path: String) -> int:
	var directory := DirAccess.open(path)
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


func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0


func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_directory(absolute)


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


func _fail(message: String) -> void:
	push_error("[Phase2StorageMeasurement] FAIL: " + message)
	_cleanup()
	quit(1)
