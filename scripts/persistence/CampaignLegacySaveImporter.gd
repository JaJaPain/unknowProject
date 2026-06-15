class_name CampaignLegacySaveImporter
extends RefCounted

const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const SaveMigratorType := preload(
	"res://scripts/persistence/SaveMigrator.gd"
)

const DEFAULT_SAVE_PATH := "user://savegame.json"
const MARKER_FILE := "legacy_import.json"


static func status(
	slot_registry: CampaignSlotRegistry,
	system_registry: SystemRegistry,
	save_path: String = DEFAULT_SAVE_PATH
) -> Dictionary:
	if slot_registry == null or not slot_registry.is_valid():
		return _blocked("storage_unavailable", "Campaign storage is unavailable.")
	if not FileAccess.file_exists(save_path):
		return _blocked("save_missing", "No version-2 prototype save was found.")
	if _has_import_marker(slot_registry.root_path):
		return _blocked(
			"already_imported",
			"The prototype save has already been imported."
		)
	if slot_registry.first_empty_slot_id().is_empty():
		return _blocked(
			"slots_full",
			"All three campaign slots are occupied. Delete a campaign before importing."
		)
	var source := _read_valid_source(save_path, system_registry)
	if not bool(source.get("ok", false)):
		return _blocked(
			"save_invalid",
			str(source.get("error", "The prototype save is invalid."))
		)
	return {
		"available": true,
		"block_code": "",
		"message": "A version-2 prototype save is ready to import.",
		"target_slot_id": slot_registry.first_empty_slot_id(),
	}


static func import_first_available(
	slot_registry: CampaignSlotRegistry,
	system_registry: SystemRegistry,
	save_path: String = DEFAULT_SAVE_PATH
) -> Dictionary:
	var import_status := status(slot_registry, system_registry, save_path)
	if not bool(import_status.get("available", false)):
		return _failure(
			str(import_status.get("block_code", "import_blocked")),
			str(import_status.get("message", "Prototype save import is unavailable."))
		)
	return import_to_slot(
		slot_registry,
		system_registry,
		str(import_status.get("target_slot_id", "")),
		save_path
	)


static func import_to_slot(
	slot_registry: CampaignSlotRegistry,
	system_registry: SystemRegistry,
	slot_id: String,
	save_path: String = DEFAULT_SAVE_PATH
) -> Dictionary:
	if slot_registry == null or not slot_registry.is_valid():
		return _failure(
			"storage_unavailable",
			"Campaign storage is unavailable."
		)
	if bool(slot_registry.get_slot(slot_id).get("occupied", false)):
		return _failure(
			"slot_occupied",
			"The selected campaign slot is already occupied."
		)
	if _has_import_marker(slot_registry.root_path):
		return _failure(
			"already_imported",
			"The prototype save has already been imported."
		)
	var source := _read_valid_source(save_path, system_registry)
	if not bool(source.get("ok", false)):
		return source
	var backup_path := _available_backup_path(save_path)
	var previous_selected_slot_id := slot_registry.selected_slot_id
	var copy_error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(save_path),
		ProjectSettings.globalize_path(backup_path)
	)
	if copy_error != OK:
		return _failure(
			"backup_failed",
			"Import could not create a safety backup. The original save and campaign slots were not changed."
		)
	var created := slot_registry.create_campaign(
		slot_id,
		"Imported Prototype Campaign",
		"prototype-version-2-import",
		source["data"],
		system_registry,
		false
	)
	if not bool(created.get("ok", false)):
		return _failure(
			"campaign_create_failed",
			"Import could not create the campaign. The original save and existing campaigns were not changed.",
			backup_path
		)
	var verified := slot_registry.load_initial_bundle(slot_id)
	if not bool(verified.get("ok", false)):
		slot_registry.delete_campaign(slot_id)
		return _failure(
			"campaign_verification_failed",
			"Imported campaign verification failed. The original save and existing campaigns were preserved.",
			backup_path
		)
	var marker_written := _write_import_marker(
		slot_registry.root_path,
		slot_id,
		str(created.get("campaign", {}).get("id", "")),
		str(source.get("source_hash", ""))
	)
	if not marker_written:
		slot_registry.delete_campaign(slot_id)
		return _failure(
			"import_marker_failed",
			"Import could not record its completion. The original save and existing campaigns were preserved.",
			backup_path
		)
	var selected := slot_registry.select_campaign(slot_id)
	if not bool(selected.get("ok", false)):
		_remove_import_marker(slot_registry.root_path)
		slot_registry.delete_campaign(slot_id)
		if not previous_selected_slot_id.is_empty():
			slot_registry.select_campaign(previous_selected_slot_id)
		return _failure(
			"campaign_activation_failed",
			"Imported campaign activation failed. The original save and existing campaigns were preserved.",
			backup_path
		)
	return {
		"ok": true,
		"slot_id": slot_id,
		"campaign_id": created.get("campaign", {}).get("id", ""),
		"backup_path": backup_path,
		"marker_written": true,
		"message": (
			"Prototype save imported into %s." %
				slot_id.replace("_", " ").to_upper()
		),
	}


static func _read_valid_source(
	save_path: String,
	system_registry: SystemRegistry
) -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return _failure(
			"save_missing",
			"No version-2 prototype save was found."
		)
	var parsed := DomainJsonType.read_object(save_path)
	var parse_validation := parsed["validation"] as ValidationResult
	if not parse_validation.is_valid():
		return _failure(
			"save_damaged",
			"The prototype save is damaged. The original file was not changed."
		)
	var data: Dictionary = parsed["data"]
	if int(data.get("version", -1)) != SaveMigratorType.CURRENT_VERSION:
		return _failure(
			"unsupported_version",
			"Only a version-2 prototype save can be imported."
		)
	var validation := SaveMigratorType.validate_current(data, system_registry)
	if not validation.is_valid():
		return _failure(
			"save_invalid",
			"The prototype save failed validation. The original file was not changed."
		)
	return {
		"ok": true,
		"data": data.duplicate(true),
		"source_hash":
			FileAccess.get_file_as_string(save_path).sha256_text(),
	}


static func _write_import_marker(
	root_path: String,
	slot_id: String,
	campaign_id: String,
	source_hash: String
) -> bool:
	var marker := {
		"schema_version": 1,
		"slot_id": slot_id,
		"campaign_id": campaign_id,
		"source_sha256": source_hash,
		"imported_at_unix": int(Time.get_unix_time_from_system()),
	}
	var marker_path := "%s/%s" % [root_path, MARKER_FILE]
	var file := FileAccess.open(marker_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(DomainJsonType.stringify(marker, false))
	return file.get_error() == OK


static func _has_import_marker(root_path: String) -> bool:
	return FileAccess.file_exists("%s/%s" % [root_path, MARKER_FILE])


static func _remove_import_marker(root_path: String) -> void:
	var marker_path := "%s/%s" % [root_path, MARKER_FILE]
	if FileAccess.file_exists(marker_path):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(marker_path)
		)


static func _available_backup_path(save_path: String) -> String:
	var timestamp := int(Time.get_unix_time_from_system())
	var base := "%s.v2.%d.campaign-import.backup" % [
		save_path,
		timestamp,
	]
	var candidate := base
	var suffix := 1
	while FileAccess.file_exists(candidate):
		candidate = "%s.%d" % [base, suffix]
		suffix += 1
	return candidate


static func _blocked(code: String, message: String) -> Dictionary:
	return {
		"available": false,
		"block_code": code,
		"message": message,
		"target_slot_id": "",
	}


static func _failure(
	code: String,
	message: String,
	backup_path: String = ""
) -> Dictionary:
	return {
		"ok": false,
		"block_code": code,
		"error": message,
		"backup_path": backup_path,
	}
