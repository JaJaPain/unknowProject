extends SceneTree

const StoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const TEST_ROOT := "user://campaign_transaction_fixture"
const INDEX_PATH := "checkpoint_index.json"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_successful_visibility_commit()
	_test_failure_stages_preserve_prior_index()
	_test_corrupt_index_recovers_backup()
	_test_stale_transaction_cleanup()
	_test_lock_and_autosave_coalescing()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Campaign transaction and recovery tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_successful_visibility_commit() -> void:
	_cleanup()
	var first := StoreType.commit_json_set(
		TEST_ROOT,
		"autosave",
		_files("checkpoint.one", 1),
		INDEX_PATH,
		_index_validator
	)
	_expect(bool(first.get("ok", false)), first.get("error", ""))
	_expect(
		_read_index_id() == "checkpoint.one",
		"Committed checkpoint did not become visible through its index."
	)
	_expect(
		FileAccess.file_exists(
			"%s/checkpoints/checkpoint.one/checkpoint.json" % TEST_ROOT
		),
		"Committed immutable payload was not installed."
	)


func _test_failure_stages_preserve_prior_index() -> void:
	for failure_stage in StoreType.FAILURE_STAGES:
		_cleanup()
		var baseline := StoreType.commit_json_set(
			TEST_ROOT,
			"autosave",
			_files("checkpoint.base", 1),
			INDEX_PATH,
			_index_validator
		)
		_expect(bool(baseline.get("ok", false)), "Baseline commit failed.")
		var failed := StoreType.commit_json_set(
			TEST_ROOT,
			"autosave",
			_files("checkpoint.new", 2),
			INDEX_PATH,
			_index_validator,
			failure_stage
		)
		_expect(
			not bool(failed.get("ok", false)),
			"Injected failure '%s' unexpectedly committed." % failure_stage
		)
		_expect(
			_read_index_id() == "checkpoint.base",
			"Failure '%s' changed the authoritative prior index." % failure_stage
		)
		_expect(
			not StoreType.is_locked(TEST_ROOT),
			"Failure '%s' leaked the transaction lock." % failure_stage
		)


func _test_corrupt_index_recovers_backup() -> void:
	_cleanup()
	StoreType.commit_json_set(
		TEST_ROOT,
		"autosave",
		_files("checkpoint.one", 1),
		INDEX_PATH,
		_index_validator
	)
	StoreType.commit_json_set(
		TEST_ROOT,
		"autosave",
		_files("checkpoint.two", 2),
		INDEX_PATH,
		_index_validator
	)
	_write_text("%s/%s" % [TEST_ROOT, INDEX_PATH], "{ damaged")
	var recovered := StoreType.recover_index(
		TEST_ROOT,
		INDEX_PATH,
		_index_validator
	)
	_expect(
		bool(recovered.get("ok", false))
			and bool(recovered.get("recovered", false)),
		"Corrupt index did not recover its last-known-good copy."
	)
	_expect(
		_read_index_id() == "checkpoint.one",
		"Recovery did not restore the previous committed index."
	)


func _test_stale_transaction_cleanup() -> void:
	var stale := "%s/transactions/stale/staged" % TEST_ROOT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(stale))
	_write_text("%s/orphan.json" % stale, "{}")
	var recovered := StoreType.recover_index(
		TEST_ROOT,
		INDEX_PATH,
		_index_validator
	)
	_expect(bool(recovered.get("ok", false)), "Valid index failed recovery scan.")
	_expect(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(
				"%s/transactions/stale" % TEST_ROOT
			)
		),
		"Stale transaction directory was not cleaned."
	)


func _test_lock_and_autosave_coalescing() -> void:
	var scope := ProjectSettings.globalize_path(TEST_ROOT)
	StoreType._active_locks[scope] = true
	var duplicate := StoreType.commit_json_set(
		TEST_ROOT,
		"autosave",
		_files("checkpoint.duplicate", 3),
		INDEX_PATH,
		_index_validator
	)
	_expect(
		bool(duplicate.get("coalesced", false)),
		"Duplicate autosave was not coalesced while locked."
	)
	StoreType._active_locks.erase(scope)
	_expect(
		StoreType.consume_pending_autosave(TEST_ROOT),
		"Coalesced autosave request was not retained for consumption."
	)
	_expect(
		not StoreType.consume_pending_autosave(TEST_ROOT),
		"Consumed autosave request was not cleared."
	)


func _files(checkpoint_id: String, generation: int) -> Dictionary:
	return {
		"checkpoints/%s/checkpoint.json" % checkpoint_id: {
			"checkpoint_id": checkpoint_id,
			"generation": generation,
		},
		INDEX_PATH: {
			"schema_version": 1,
			"active_checkpoint_id": checkpoint_id,
			"generation": generation,
		},
	}


func _index_validator(path: String, data: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	if path.get_file() != INDEX_PATH:
		return result
	if int(data.get("schema_version", -1)) != 1:
		result.add_error(
			"invalid_index_version",
			"Checkpoint index version must be 1.",
			"schema_version"
		)
	if str(data.get("active_checkpoint_id", "")).is_empty():
		result.add_error(
			"missing_checkpoint_id",
			"Checkpoint index requires an active checkpoint.",
			"active_checkpoint_id"
		)
	return result


func _read_index_id() -> String:
	if not FileAccess.file_exists("%s/%s" % [TEST_ROOT, INDEX_PATH]):
		return ""
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("%s/%s" % [TEST_ROOT, INDEX_PATH])
	)
	return str(parsed.get("active_checkpoint_id", "")) \
		if parsed is Dictionary else ""


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)


func _cleanup() -> void:
	_remove_directory(ProjectSettings.globalize_path(TEST_ROOT))
	StoreType._active_locks.clear()
	StoreType._pending_autosaves.clear()


func _remove_directory(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
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
