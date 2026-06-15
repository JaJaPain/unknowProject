extends SceneTree

const ImporterType := preload(
	"res://scripts/persistence/CampaignLegacySaveImporter.gd"
)
const SchemaType := preload(
	"res://scripts/persistence/CampaignSchemaCatalog.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://campaign_legacy_import_fixture"
const SAVE_PATH := "user://campaign_legacy_import_save.json"

var _failures: Array[String] = []
var _system_registry: SystemRegistry


func _initialize() -> void:
	_system_registry = SystemRegistryType.load_default()
	_cleanup()
	_test_successful_import_and_backup()
	_cleanup()
	_test_full_slots_refuse_without_changes()
	_cleanup()
	_test_damaged_source_is_untouched()
	_cleanup()
	if _failures.is_empty():
		print("[PASS] Campaign version-2 legacy import tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_successful_import_and_backup() -> void:
	var original_text := JSON.stringify(_version_2_save(4321))
	_write_text(SAVE_PATH, original_text)
	var slots := SlotRegistryType.open(TEST_ROOT)
	var imported := ImporterType.import_first_available(
		slots,
		_system_registry,
		SAVE_PATH
	)
	_expect(bool(imported.get("ok", false)), imported.get("error", ""))
	if not bool(imported.get("ok", false)):
		return
	_expect(
		imported.get("slot_id", "") == "slot_01"
			and slots.selected_slot_id == "slot_01",
		"Import did not activate the first empty slot."
	)
	_expect(
		FileAccess.get_file_as_string(SAVE_PATH) == original_text,
		"Import modified the version-2 source save."
	)
	var backup_path := str(imported.get("backup_path", ""))
	_expect(
		FileAccess.file_exists(backup_path)
			and FileAccess.get_file_as_string(backup_path) == original_text,
		"Import backup was absent or not byte-for-byte identical."
	)
	var bundle := slots.load_initial_bundle("slot_01")
	_expect(
		bool(bundle.get("ok", false)),
		"Imported campaign bundle failed verification."
	)
	if bool(bundle.get("ok", false)):
		var checkpoint: Dictionary = {}
		for document in bundle.get("documents", []):
			if document.get("document_type", "") == SchemaType.CHECKPOINT:
				checkpoint = document
				break
		_expect(
			checkpoint.get("state", {}).get("global", {}).get("credits", 0)
				== 4321,
			"Imported checkpoint did not retain prototype gameplay state."
		)
	var repeated := ImporterType.import_first_available(
		slots,
		_system_registry,
		SAVE_PATH
	)
	_expect(
		not bool(repeated.get("ok", false))
			and repeated.get("block_code", "") == "already_imported"
			and not bool(slots.get_slot("slot_02").get("occupied", false)),
		"Import marker did not prevent a duplicate campaign."
	)


func _test_full_slots_refuse_without_changes() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	for slot_id in SlotRegistryType.SLOT_IDS:
		var created := slots.create_campaign(
			slot_id,
			"Existing %s" % slot_id,
			"phase-2-test",
			_version_2_save(100 + SlotRegistryType.SLOT_IDS.find(slot_id)),
			_system_registry
		)
		_expect(bool(created.get("ok", false)), created.get("error", ""))
	var original_text := JSON.stringify(_version_2_save(9999))
	_write_text(SAVE_PATH, original_text)
	var slots_before := FileAccess.get_file_as_string(
		"%s/slots.json" % TEST_ROOT
	)
	var imported := ImporterType.import_first_available(
		slots,
		_system_registry,
		SAVE_PATH
	)
	_expect(
		not bool(imported.get("ok", false))
			and imported.get("block_code", "") == "slots_full",
		"Importer did not clearly refuse three occupied slots."
	)
	_expect(
		FileAccess.get_file_as_string(SAVE_PATH) == original_text
			and FileAccess.get_file_as_string(
				"%s/slots.json" % TEST_ROOT
			) == slots_before,
		"Full-slot refusal modified the source save or slot registry."
	)
	_expect(
		_count_import_backups() == 0,
		"Full-slot refusal created a migration backup before eligibility."
	)


func _test_damaged_source_is_untouched() -> void:
	var damaged := "{\"version\":2,\"player\":"
	_write_text(SAVE_PATH, damaged)
	var slots := SlotRegistryType.open(TEST_ROOT)
	var slots_before := FileAccess.get_file_as_string(
		"%s/slots.json" % TEST_ROOT
	)
	var imported := ImporterType.import_first_available(
		slots,
		_system_registry,
		SAVE_PATH
	)
	_expect(
		not bool(imported.get("ok", false))
			and imported.get("block_code", "") == "save_invalid",
		"Damaged version-2 source was accepted."
	)
	_expect(
		FileAccess.get_file_as_string(SAVE_PATH) == damaged
			and FileAccess.get_file_as_string(
				"%s/slots.json" % TEST_ROOT
			) == slots_before,
		"Failed import modified the damaged source or empty slots."
	)
	_expect(
		_count_import_backups() == 0,
		"Damaged-source refusal created a misleading backup."
	)


func _version_2_save(credits: int) -> Dictionary:
	return {
		"version": 2,
		"current_system_id": "system.start",
		"arrival_gate_id": "",
		"player": {
			"health": 73.0,
			"shield": 17.0,
			"position": [1.0, 2.0, 3.0],
			"rotation": [0.0, 0.5, 0.0],
		},
		"global": {
			"credits": credits,
			"cargo": 27.0,
			"upgrades": {},
			"reputations": {},
		},
		"quest": {},
		"systems": {"system.start": {"entities": {}}},
	}


func _count_import_backups() -> int:
	var directory := DirAccess.open("user://")
	if directory == null:
		return 0
	var count := 0
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.begins_with(SAVE_PATH.get_file() + ".v2.") \
				and entry.contains(".campaign-import.backup"):
			count += 1
		entry = directory.get_next()
	directory.list_dir_end()
	return count


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write import fixture.")
		return
	file.store_string(text)


func _cleanup() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var user_directory := DirAccess.open("user://")
	if user_directory != null:
		user_directory.list_dir_begin()
		var entry := user_directory.get_next()
		while not entry.is_empty():
			if entry.begins_with(SAVE_PATH.get_file() + ".v2.") \
					and entry.contains(".campaign-import.backup"):
				DirAccess.remove_absolute(
					ProjectSettings.globalize_path("user://%s" % entry)
				)
			entry = user_directory.get_next()
		user_directory.list_dir_end()
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
