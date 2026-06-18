extends SceneTree

const MigratorType := preload(
	"res://scripts/persistence/SaveMigrator.gd"
)
const RegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_PATH := "user://save_migration_fixture.json"

var _failures: Array[String] = []
var _registry: SystemRegistry


func _initialize() -> void:
	_registry = RegistryType.load_default()
	_expect(_registry.is_valid(), "System registry failed to load.")
	_cleanup()

	_test_in_memory_migration()
	_test_file_migration_and_backup()
	_test_damaged_source_is_untouched()
	_test_unsupported_source_is_untouched()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Save migration tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_in_memory_migration() -> void:
	var migrated := MigratorType.migrate_legacy_data(
		_legacy_save(),
		_registry
	)
	_expect(bool(migrated.get("ok", false)), migrated.get("error", ""))
	if not bool(migrated.get("ok", false)):
		return
	var data: Dictionary = migrated["data"]
	_expect(
		int(data.get("version", 0)) == MigratorType.CURRENT_VERSION,
		"Migration did not advance the save version."
	)
	_expect(
		data.get("current_system_id") == "system.start"
			and data.get("arrival_gate_id") == "gate.start.to_test",
		"Migration did not canonicalize top-level IDs."
	)
	_expect(
		(data.get("systems", {}) as Dictionary).has("system.start")
			and not (data.get("systems", {}) as Dictionary).has(
				"start_system"
			),
		"Migration did not canonicalize system-state keys."
	)
	_expect(
		(data.get("quest", {}) as Dictionary).get("system_id")
			== "system.start",
		"Migration did not canonicalize mission system identity."
	)
	_expect(
		MigratorType.validate_current(data, _registry).is_valid(),
		"Migrated save failed current-schema validation."
	)

	var decoded := MigratorType.decode_for_runtime(data, _registry)
	_expect(bool(decoded.get("ok", false)), decoded.get("error", ""))
	if bool(decoded.get("ok", false)):
		var runtime: Dictionary = decoded["data"]
		_expect(
			runtime.get("current_system_id") == "start_system"
				and runtime.get("arrival_gate_id") == "start_to_test"
				and (runtime.get("systems", {}) as Dictionary).has(
					"start_system"
				),
			"Current save did not decode to compatible runtime IDs."
		)


func _test_file_migration_and_backup() -> void:
	var original_text := JSON.stringify(_legacy_save())
	_write_text(TEST_PATH, original_text)
	var loaded := MigratorType.load_for_runtime(TEST_PATH, _registry)
	_expect(bool(loaded.get("ok", false)), loaded.get("error", ""))
	_expect(
		bool(loaded.get("migrated", false)),
		"Version 1 file did not report a migration."
	)
	var backup_path := str(loaded.get("backup_path", ""))
	_expect(
		not backup_path.is_empty() and FileAccess.file_exists(backup_path),
		"Migration did not create a backup."
	)
	if FileAccess.file_exists(backup_path):
		_expect(
			FileAccess.get_file_as_string(backup_path) == original_text,
			"Migration backup does not match the original source."
		)
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(backup_path)
		)
	var rewritten: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TEST_PATH)
	)
	_expect(
		rewritten is Dictionary
			and int(rewritten.get("version", 0))
				== MigratorType.CURRENT_VERSION,
		"Migrated file was not installed as the active save."
	)


func _test_damaged_source_is_untouched() -> void:
	var damaged := "{\"version\":1,\"player\":"
	_write_text(TEST_PATH, damaged)
	var loaded := MigratorType.load_for_runtime(TEST_PATH, _registry)
	_expect(
		not bool(loaded.get("ok", false)),
		"Damaged save was accepted."
	)
	_expect(
		FileAccess.get_file_as_string(TEST_PATH) == damaged,
		"Damaged source save was modified."
	)


func _test_unsupported_source_is_untouched() -> void:
	var future := _legacy_save()
	future["version"] = MigratorType.CURRENT_VERSION + 1
	var future_text := JSON.stringify(future)
	_write_text(TEST_PATH, future_text)
	var loaded := MigratorType.load_for_runtime(TEST_PATH, _registry)
	_expect(
		not bool(loaded.get("ok", false)),
		"Unsupported future save was accepted."
	)
	_expect(
		FileAccess.get_file_as_string(TEST_PATH) == future_text,
		"Unsupported source save was modified."
	)


func _legacy_save() -> Dictionary:
	return {
		"version": MigratorType.LEGACY_VERSION,
		"current_system_id": "start_system",
		"arrival_gate_id": "start_to_test",
		"player": {
			"health": 73.0,
			"shield": 17.0,
			"position": [1.0, 2.0, 3.0],
			"rotation": [0.0, 0.5, 0.0],
		},
		"global": {
			"credits": 4321,
			"cargo": 27.0,
		},
		"quest": {
			"title": "Legacy Ore",
			"faction": "zenith",
			"objective_type": "DELIVER_ORE",
			"amount_required": 40.0,
			"partial_delivered": 11.0,
			"reward_credits": 120,
			"system_id": "start_system",
		},
		"systems": {
			"start_system": {
				"entities": {
					"asteroid.start.test": {
						"world_id": "asteroid.start.test",
						"state": {"resources": 123.0},
					},
				},
			},
		},
	}


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write migration fixture.")
		return
	file.store_string(text)


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var temp_path := "%s.migration.tmp" % TEST_PATH
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
