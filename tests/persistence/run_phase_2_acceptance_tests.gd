extends SceneTree

const CheckpointStoreType := preload(
	"res://scripts/persistence/CampaignCheckpointStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://phase_2_acceptance_fixture"

var _failures: Array[String] = []
var _system_registry: SystemRegistry


func _initialize() -> void:
	_cleanup()
	_system_registry = SystemRegistryType.load_default()
	_test_phase_2_ownership_and_isolation()
	_cleanup()
	if _failures.is_empty():
		print("[PASS] Phase 2 storage ownership acceptance tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_phase_2_ownership_and_isolation() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	for slot_index in range(3):
		var created := slots.create_campaign(
			"slot_%02d" % (slot_index + 1),
			"Acceptance %d" % (slot_index + 1),
			"phase-2-acceptance",
			_runtime_state((slot_index + 1) * 100),
			_system_registry
		)
		_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not _failures.is_empty():
		return
	var slot_one_path := "%s/slot_01" % TEST_ROOT
	var manifest_before := FileAccess.get_file_as_string(
		"%s/manifest.json" % slot_one_path
	)
	var slot_two_campaign_before := FileAccess.get_file_as_string(
		"%s/slot_02/campaign.json" % TEST_ROOT
	)
	var store := CheckpointStoreType.open(slot_one_path)
	_expect(store.is_valid(), "Slot 1 checkpoint store is invalid.")
	if not store.is_valid():
		return
	var first_state := _runtime_state(111)
	first_state["player"]["position"] = [9.0, 8.0, 7.0]
	first_state["player"]["nav_mode"] = "ATTACK"
	first_state["systems"]["system.start"]["projectiles"] = [{"damage": 99}]
	var first := store.capture_autosave(
		first_state,
		{
			"type": "docked",
			"system_id": "system.start",
			"station_id": "station.start.main",
		},
		"dock"
	)
	_expect(bool(first.get("ok", false)), first.get("error", ""))
	var copied := store.copy_active_to_manual(0, "Acceptance Rewind")
	_expect(bool(copied.get("ok", false)), copied.get("error", ""))
	var second := store.capture_autosave(
		_runtime_state(222),
		{
			"type": "gate_arrival",
			"system_id": "system.start",
			"gate_id": "gate.start.to_test",
		},
		"gate_arrival"
	)
	_expect(bool(second.get("ok", false)), second.get("error", ""))
	var rewound := store.runtime_state_from_manual(0)
	_expect(
		bool(rewound.get("ok", false))
			and int(rewound.get("state", {}).get("global", {}).get(
				"credits",
				0
			)) == 111,
		"Manual checkpoint did not rewind mutable state exactly."
	)
	_expect(
		not _contains_tactical_key(rewound.get("state", {})),
		"Safe checkpoint retained tactical advantage state."
	)
	_expect(
		FileAccess.get_file_as_string("%s/manifest.json" % slot_one_path)
			== manifest_before,
		"Checkpoint operations changed permanent campaign canon."
	)
	_expect(
		FileAccess.get_file_as_string(
			"%s/slot_02/campaign.json" % TEST_ROOT
		) == slot_two_campaign_before,
		"Slot 1 checkpoint writes changed slot 2."
	)
	var slot_one_id := str(slots.get_slot("slot_01").get("campaign_id", ""))
	var slot_three_id := str(slots.get_slot("slot_03").get("campaign_id", ""))
	var deleted := slots.delete_campaign("slot_02")
	_expect(bool(deleted.get("ok", false)), deleted.get("error", ""))
	_expect(
		slots.get_slot("slot_01").get("campaign_id", "") == slot_one_id
			and slots.get_slot("slot_03").get("campaign_id", "")
				== slot_three_id
			and FileAccess.file_exists(
				"%s/slot_01/campaign.json" % TEST_ROOT
			)
			and FileAccess.file_exists(
				"%s/slot_03/campaign.json" % TEST_ROOT
			),
		"Campaign deletion crossed slot ownership boundaries."
	)


func _runtime_state(credits: int) -> Dictionary:
	return {
		"current_system_id": "system.start",
		"arrival_gate_id": "",
		"player": {
			"health": 100.0,
			"shield": 20.0,
		},
		"global": {
			"credits": credits,
			"cargo": 5.0,
			"storage_ore": 10.0,
			"upgrades": {},
			"reputations": {},
		},
		"quest": {},
		"systems": {"system.start": {"entities": {}}},
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
