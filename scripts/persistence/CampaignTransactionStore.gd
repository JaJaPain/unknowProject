class_name CampaignTransactionStore
extends RefCounted

const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const JOURNAL_VERSION := 1
const FAILURE_STAGES: Array[String] = [
	"after_lock",
	"after_journal",
	"after_stage",
	"after_validation",
	"after_backup",
	"after_payload_install",
	"before_index_install",
]

static var _active_locks: Dictionary = {}
static var _pending_autosaves: Dictionary = {}


static func commit_json_set(
	store_root: String,
	operation: String,
	files: Dictionary,
	visibility_index_path: String,
	validator: Callable = Callable(),
	failure_stage: String = ""
) -> Dictionary:
	var root := store_root.trim_suffix("/")
	var scope := ProjectSettings.globalize_path(root)
	if _active_locks.has(scope):
		if operation == "autosave":
			_pending_autosaves[scope] = true
			return {
				"ok": false,
				"coalesced": true,
				"error": "An autosave is already in progress.",
			}
		return {
			"ok": false,
			"coalesced": false,
			"error": "A campaign save transaction is already active.",
		}
	_active_locks[scope] = true

	var transaction_id := "%d_%s" % [
		Time.get_ticks_usec(),
		Crypto.new().generate_random_bytes(6).hex_encode(),
	]
	var transaction_root := "%s/transactions/%s" % [root, transaction_id]
	var staged_root := "%s/staged" % transaction_root
	var journal_path := "%s/journal.json" % transaction_root
	var result := {"ok": false, "transaction_id": transaction_id}

	if failure_stage == "after_lock":
		result["error"] = "Injected failure after lock acquisition."
		return _finish(scope, result)
	if not _make_directory(staged_root):
		result["error"] = "Transaction staging directory could not be created."
		return _finish(scope, result)

	var journal := {
		"schema_version": JOURNAL_VERSION,
		"transaction_id": transaction_id,
		"operation": operation,
		"visibility_index_path": visibility_index_path,
		"status": "staging",
		"files": files.keys(),
	}
	if not _write_json(journal_path, journal):
		result["error"] = "Transaction journal could not be written."
		return _finish(scope, result)
	if failure_stage == "after_journal":
		result["error"] = "Injected failure after journal creation."
		return _finish(scope, result)

	for relative_path in files:
		if not _is_safe_relative_path(str(relative_path)):
			result["error"] = "Transaction contains an unsafe relative path."
			return _finish(scope, result)
		var staged_path := "%s/%s" % [staged_root, relative_path]
		if not _write_json(staged_path, files[relative_path]):
			result["error"] = "Transaction file could not be staged."
			return _finish(scope, result)
	if failure_stage == "after_stage":
		result["error"] = "Injected failure after staging."
		return _finish(scope, result)

	var validation := _validate_staged_files(
		staged_root,
		files,
		validator
	)
	if not validation.is_valid():
		result["error"] = "Staged transaction failed validation."
		result["validation"] = validation.to_dict()
		return _finish(scope, result)
	journal["status"] = "validated"
	_write_json(journal_path, journal)
	if failure_stage == "after_validation":
		result["error"] = "Injected failure after validation."
		return _finish(scope, result)

	var recovery_root := "%s/recovery" % root
	var live_index := "%s/%s" % [root, visibility_index_path]
	var recovery_index := "%s/last_known_good_%s" % [
		recovery_root,
		visibility_index_path.get_file(),
	]
	if FileAccess.file_exists(live_index):
		if not _make_directory(recovery_root) \
				or DirAccess.copy_absolute(
					ProjectSettings.globalize_path(live_index),
					ProjectSettings.globalize_path(recovery_index)
				) != OK:
			result["error"] = "Last-known-good index could not be preserved."
			return _finish(scope, result)
	if failure_stage == "after_backup":
		result["error"] = "Injected failure after index backup."
		return _finish(scope, result)

	for relative_path in files:
		if str(relative_path) == visibility_index_path:
			continue
		var installed := _install_staged_file(
			"%s/%s" % [staged_root, relative_path],
			"%s/%s" % [root, relative_path]
		)
		if not installed:
			result["error"] = "Transaction payload could not be installed."
			return _finish(scope, result)
	if failure_stage == "after_payload_install":
		result["error"] = "Injected failure after payload installation."
		return _finish(scope, result)
	if failure_stage == "before_index_install":
		result["error"] = "Injected failure before index installation."
		return _finish(scope, result)

	if not files.has(visibility_index_path):
		result["error"] = "Transaction is missing its visibility index."
		return _finish(scope, result)
	if not _install_staged_file(
		"%s/%s" % [staged_root, visibility_index_path],
		live_index
	):
		result["error"] = "Transaction visibility index could not be installed."
		return _finish(scope, result)

	journal["status"] = "committed"
	_write_json(journal_path, journal)
	result = {
		"ok": true,
		"transaction_id": transaction_id,
		"coalesced_autosave_pending": bool(
			_pending_autosaves.get(scope, false)
		),
	}
	_remove_tree(transaction_root)
	return _finish(scope, result)


static func recover_index(
	store_root: String,
	visibility_index_path: String,
	validator: Callable = Callable()
) -> Dictionary:
	var root := store_root.trim_suffix("/")
	var live_path := "%s/%s" % [root, visibility_index_path]
	var recovery_path := "%s/recovery/last_known_good_%s" % [
		root,
		visibility_index_path.get_file(),
	]
	_cleanup_stale_transactions(root)
	var live := _read_and_validate(live_path, validator)
	if bool(live.get("ok", false)):
		return {"ok": true, "recovered": false, "data": live["data"]}
	var backup := _read_and_validate(recovery_path, validator)
	if not bool(backup.get("ok", false)):
		return {
			"ok": false,
			"recovered": false,
			"error": "Neither the active nor last-known-good index is valid.",
		}
	if not _install_staged_file(recovery_path, live_path):
		return {
			"ok": false,
			"recovered": false,
			"error": "Last-known-good index could not be restored.",
		}
	return {"ok": true, "recovered": true, "data": backup["data"]}


static func restore_last_known_good_index(
	store_root: String,
	visibility_index_path: String,
	validator: Callable = Callable()
) -> Dictionary:
	var root := store_root.trim_suffix("/")
	var live_path := "%s/%s" % [root, visibility_index_path]
	var recovery_path := "%s/recovery/last_known_good_%s" % [
		root,
		visibility_index_path.get_file(),
	]
	var backup := _read_and_validate(recovery_path, validator)
	if not bool(backup.get("ok", false)):
		return {
			"ok": false,
			"error": "No valid last-known-good index is available.",
		}
	if not _install_staged_file(recovery_path, live_path):
		return {
			"ok": false,
			"error": "Last-known-good index could not be restored.",
		}
	return {"ok": true, "recovered": true, "data": backup["data"]}


static func is_locked(store_root: String) -> bool:
	return _active_locks.has(
		ProjectSettings.globalize_path(store_root.trim_suffix("/"))
	)


static func consume_pending_autosave(store_root: String) -> bool:
	var scope := ProjectSettings.globalize_path(store_root.trim_suffix("/"))
	var pending := bool(_pending_autosaves.get(scope, false))
	_pending_autosaves.erase(scope)
	return pending


static func _validate_staged_files(
	staged_root: String,
	files: Dictionary,
	validator: Callable
) -> ValidationResult:
	var result := ValidationResultType.new()
	for relative_path in files:
		var parsed := DomainJsonType.read_object(
			"%s/%s" % [staged_root, relative_path]
		)
		result.merge(parsed["validation"], str(relative_path))
		if (parsed["validation"] as ValidationResult).is_valid() \
				and validator.is_valid():
			var custom: Variant = validator.call(
				str(relative_path),
				parsed["data"]
			)
			if custom is ValidationResult:
				result.merge(custom as ValidationResult, str(relative_path))
			elif custom != true:
				result.add_error(
					"custom_validation_failed",
					"Custom transaction validation failed.",
					str(relative_path)
				)
	return result


static func _read_and_validate(path: String, validator: Callable) -> Dictionary:
	var parsed := DomainJsonType.read_object(path)
	var validation := parsed["validation"] as ValidationResult
	if validation.is_valid() and validator.is_valid():
		var custom: Variant = validator.call(path.get_file(), parsed["data"])
		if custom is ValidationResult:
			validation.merge(custom as ValidationResult)
		elif custom != true:
			validation.add_error(
				"custom_validation_failed",
				"Index validation failed."
			)
	return {
		"ok": validation.is_valid(),
		"data": parsed["data"],
		"validation": validation,
	}


static func _install_staged_file(source: String, destination: String) -> bool:
	if not _make_directory(destination.get_base_dir()):
		return false
	var destination_absolute := ProjectSettings.globalize_path(destination)
	var temp_destination := "%s.installing" % destination
	var temp_absolute := ProjectSettings.globalize_path(temp_destination)
	if FileAccess.file_exists(temp_destination):
		DirAccess.remove_absolute(temp_absolute)
	if DirAccess.copy_absolute(
		ProjectSettings.globalize_path(source),
		temp_absolute
	) != OK:
		return false
	if FileAccess.file_exists(destination):
		if DirAccess.remove_absolute(destination_absolute) != OK:
			DirAccess.remove_absolute(temp_absolute)
			return false
	if DirAccess.rename_absolute(temp_absolute, destination_absolute) != OK:
		DirAccess.remove_absolute(temp_absolute)
		return false
	return true


static func _cleanup_stale_transactions(root: String) -> void:
	var transactions := "%s/transactions" % root
	var absolute := ProjectSettings.globalize_path(transactions)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and directory.current_is_dir():
			_remove_tree("%s/%s" % [transactions, entry])
		entry = directory.get_next()
	directory.list_dir_end()


static func _finish(scope: String, result: Dictionary) -> Dictionary:
	_active_locks.erase(scope)
	return result


static func _write_json(path: String, data: Dictionary) -> bool:
	if not _make_directory(path.get_base_dir()):
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(DomainJsonType.stringify(data, true))
	return file.get_error() == OK


static func _make_directory(path: String) -> bool:
	if path.is_empty():
		return false
	return DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path)
	) in [OK, ERR_ALREADY_EXISTS]


static func _remove_tree(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	var directory := DirAccess.open(absolute)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := "%s/%s" % [path, entry]
			if directory.current_is_dir():
				if not _remove_tree(child):
					directory.list_dir_end()
					return false
			elif DirAccess.remove_absolute(
				ProjectSettings.globalize_path(child)
			) != OK:
				directory.list_dir_end()
				return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute) == OK


static func _is_safe_relative_path(path: String) -> bool:
	return not path.is_empty() \
		and not path.is_absolute_path() \
		and ".." not in path.split("/")
