class_name SaveMigrator
extends RefCounted

const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const MissionAdapterType := preload(
	"res://scripts/domain/MissionAdapter.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const LEGACY_VERSION := 1
const CURRENT_VERSION := 2


static func prepare_for_save(
	runtime_data: Dictionary,
	registry: SystemRegistry
) -> Dictionary:
	var encoded := runtime_data.duplicate(true)
	encoded["version"] = CURRENT_VERSION

	var current_system := _canonical_system_id(
		encoded.get("current_system_id", ""),
		registry
	)
	if current_system.is_empty():
		return _failure("Save references an unknown current system.")
	encoded["current_system_id"] = current_system

	var arrival_gate := str(encoded.get("arrival_gate_id", ""))
	if not arrival_gate.is_empty():
		arrival_gate = _canonical_gate_id(arrival_gate, registry)
		if arrival_gate.is_empty():
			return _failure("Save references an unknown arrival gate.")
	encoded["arrival_gate_id"] = arrival_gate

	var encoded_systems := _encode_system_states(
		encoded.get("systems", {}),
		registry
	)
	if not bool(encoded_systems.get("ok", false)):
		return encoded_systems
	encoded["systems"] = encoded_systems["data"]

	var encoded_quest := _encode_quest(
		encoded.get("quest", {}),
		registry
	)
	if not bool(encoded_quest.get("ok", false)):
		return encoded_quest
	encoded["quest"] = encoded_quest["data"]

	var validation := validate_current(encoded, registry)
	if not validation.is_valid():
		return _failure(
			"Prepared save failed validation: %s" % validation.summary()
		)
	return _success(encoded)


static func load_for_runtime(
	path: String,
	registry: SystemRegistry
) -> Dictionary:
	var parsed := DomainJsonType.read_object(path)
	var parse_validation := parsed["validation"] as ValidationResult
	if not parse_validation.is_valid():
		return _failure(
			"Save file is damaged: %s" % parse_validation.summary()
		)

	var saved_data: Dictionary = parsed["data"]
	var version := int(saved_data.get("version", -1))
	var migrated := false
	var backup_path := ""
	if version == LEGACY_VERSION:
		var migration := migrate_legacy_data(saved_data, registry)
		if not bool(migration.get("ok", false)):
			return migration
		saved_data = migration["data"]
		var replacement := _replace_with_migrated_save(
			path,
			saved_data,
			registry
		)
		if not bool(replacement.get("ok", false)):
			return replacement
		migrated = true
		backup_path = str(replacement.get("backup_path", ""))
	elif version != CURRENT_VERSION:
		return _failure(
			"Save version %d is unsupported; expected version %d." % [
				version,
				CURRENT_VERSION,
			]
		)

	var validation := validate_current(saved_data, registry)
	if not validation.is_valid():
		return _failure(
			"Save file failed validation: %s" % validation.summary()
		)
	var decoded := decode_for_runtime(saved_data, registry)
	if not bool(decoded.get("ok", false)):
		return decoded
	decoded["migrated"] = migrated
	decoded["backup_path"] = backup_path
	return decoded


static func migrate_legacy_data(
	legacy_data: Dictionary,
	registry: SystemRegistry
) -> Dictionary:
	if int(legacy_data.get("version", -1)) != LEGACY_VERSION:
		return _failure("Only version 1 saves can use the legacy migrator.")
	if not _has_base_shape(legacy_data):
		return _failure("Legacy save is missing required state sections.")

	var normalized := legacy_data.duplicate(true)
	var quest: Variant = normalized.get("quest", {})
	if not quest is Dictionary:
		return _failure("Legacy save mission state is malformed.")
	normalized["quest"] = MissionAdapterType.normalize_legacy_state(quest)
	return prepare_for_save(normalized, registry)


static func decode_for_runtime(
	saved_data: Dictionary,
	registry: SystemRegistry
) -> Dictionary:
	var validation := validate_current(saved_data, registry)
	if not validation.is_valid():
		return _failure(
			"Cannot decode invalid save data: %s" % validation.summary()
		)

	var decoded := saved_data.duplicate(true)
	decoded["current_system_id"] = registry.runtime_system_id(
		saved_data.get("current_system_id", "")
	)
	var arrival_gate := str(saved_data.get("arrival_gate_id", ""))
	decoded["arrival_gate_id"] = (
		registry.runtime_gate_id(arrival_gate)
		if not arrival_gate.is_empty()
		else ""
	)

	var runtime_systems := {}
	for raw_id: Variant in (saved_data["systems"] as Dictionary).keys():
		var runtime_id := registry.runtime_system_id(raw_id)
		if runtime_id.is_empty():
			return _failure(
				"Save contains unknown system state '%s'." % raw_id
			)
		runtime_systems[runtime_id] = saved_data["systems"][raw_id]
	decoded["systems"] = runtime_systems

	var raw_quest = saved_data.get("quest", {})
	if raw_quest is Array:
		var quest_arr: Array = []
		for item in raw_quest:
			var q: Dictionary = (item as Dictionary).duplicate(true)
			if not q.is_empty():
				q["system_id"] = registry.runtime_system_id(
					q.get("system_id", "")
				)
			quest_arr.append(q)
		decoded["quest"] = quest_arr
	else:
		var quest: Dictionary = (raw_quest as Dictionary).duplicate(true)
		if not quest.is_empty():
			quest["system_id"] = registry.runtime_system_id(
				quest.get("system_id", "")
			)
		decoded["quest"] = quest
	return _success(decoded)


static func validate_current(
	data: Variant,
	registry: SystemRegistry
) -> ValidationResult:
	var result := ValidationResultType.new()
	if not data is Dictionary:
		result.add_error("invalid_save", "Save root must be an object.")
		return result
	if int(data.get("version", -1)) != CURRENT_VERSION:
		result.add_error(
			"unsupported_save_version",
			"Save version must be %d." % CURRENT_VERSION,
			"version"
		)
		return result
	if not _has_base_shape(data):
		result.add_error(
			"missing_save_sections",
			"Save is missing player, global, quest, or system state."
		)
		return result

	_validate_canonical_system(
		data.get("current_system_id", ""),
		"current_system_id",
		registry,
		result
	)
	var arrival_gate := str(data.get("arrival_gate_id", ""))
	if not arrival_gate.is_empty():
		_validate_canonical_gate(
			arrival_gate,
			"arrival_gate_id",
			registry,
			result
		)

	var systems: Dictionary = data["systems"]
	for raw_id: Variant in systems.keys():
		_validate_canonical_system(
			raw_id,
			"systems.%s" % raw_id,
			registry,
			result
		)

	var quest_data = data["quest"]
	if quest_data is Array:
		for i in range(quest_data.size()):
			var q: Dictionary = quest_data[i]
			result.merge(
				MissionAdapterType.validate_active_state(q),
				"quest[%d]" % i
			)
			_validate_canonical_system(
				q.get("system_id", ""),
				"quest[%d].system_id" % i,
				registry,
				result
			)
	elif quest_data is Dictionary and not quest_data.is_empty():
		result.merge(
			MissionAdapterType.validate_active_state(quest_data),
			"quest"
		)
		_validate_canonical_system(
			quest_data.get("system_id", ""),
			"quest.system_id",
			registry,
			result
		)
	return result


static func write_current(path: String, saved_data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(DomainJsonType.stringify(saved_data, false))
	return file.get_error() == OK


static func _replace_with_migrated_save(
	path: String,
	migrated_data: Dictionary,
	registry: SystemRegistry
) -> Dictionary:
	var backup_path := _available_backup_path(path)
	var source_path := ProjectSettings.globalize_path(path)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	var copy_error := DirAccess.copy_absolute(
		source_path,
		backup_absolute
	)
	if copy_error != OK:
		return _failure(
			"Could not create migration backup (error %d)." % copy_error
		)

	var temp_path := "%s.migration.tmp" % path
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_absolute)
	if not write_current(temp_path, migrated_data):
		DirAccess.remove_absolute(temp_absolute)
		return _failure(
			"Could not write migrated save; original save was preserved."
		)

	var temp_parsed := DomainJsonType.read_object(temp_path)
	var temp_validation := temp_parsed["validation"] as ValidationResult
	if temp_validation.is_valid():
		temp_validation.merge(
			validate_current(temp_parsed["data"], registry)
		)
	if not temp_validation.is_valid():
		DirAccess.remove_absolute(temp_absolute)
		return _failure(
			"Migrated save failed verification; original save was preserved."
		)

	var remove_error := DirAccess.remove_absolute(source_path)
	if remove_error != OK:
		DirAccess.remove_absolute(temp_absolute)
		return _failure(
			"Could not replace legacy save; original save was preserved."
		)
	var rename_error := DirAccess.rename_absolute(
		temp_absolute,
		source_path
	)
	if rename_error != OK:
		DirAccess.copy_absolute(backup_absolute, source_path)
		DirAccess.remove_absolute(temp_absolute)
		return _failure(
			"Migration replacement failed; original save was restored."
		)
	return {
		"ok": true,
		"data": migrated_data,
		"backup_path": backup_path,
	}


static func _encode_system_states(
	raw_systems: Variant,
	registry: SystemRegistry
) -> Dictionary:
	if not raw_systems is Dictionary:
		return _failure("Save system state must be an object.")
	var encoded := {}
	for raw_id: Variant in raw_systems.keys():
		var canonical := _canonical_system_id(raw_id, registry)
		if canonical.is_empty():
			return _failure(
				"Save contains unknown system state '%s'." % raw_id
			)
		if encoded.has(canonical):
			return _failure(
				"Multiple system states resolve to '%s'." % canonical
			)
		encoded[canonical] = raw_systems[raw_id]
	return _success(encoded)


static func _encode_quest(
	raw_quest: Variant,
	registry: SystemRegistry
) -> Dictionary:
	if raw_quest is Array:
		var encoded_array: Array = []
		for item in raw_quest:
			if not item is Dictionary:
				return _failure("Quest array item must be an object.")
			var result := _encode_single_quest(item, registry)
			if not bool(result.get("ok", false)):
				return result
			encoded_array.append(result["data"])
		return _success(encoded_array)
	if not raw_quest is Dictionary:
		return _failure("Save mission state must be an object or array.")
	return _encode_single_quest(raw_quest, registry)


static func _encode_single_quest(
	raw_quest: Dictionary,
	registry: SystemRegistry
) -> Dictionary:
	var quest: Dictionary = raw_quest.duplicate(true)
	if quest.is_empty():
		return _success(quest)
	quest = MissionAdapterType.normalize_legacy_state(quest)
	var canonical := _canonical_system_id(
		quest.get("system_id", ""),
		registry
	)
	if canonical.is_empty():
		return _failure("Mission references an unknown system.")
	quest["system_id"] = canonical
	var validation := MissionAdapterType.validate_active_state(quest)
	if not validation.is_valid():
		return _failure(
			"Mission state failed validation: %s" % validation.summary()
		)
	return _success(quest)


static func _canonical_system_id(
	raw_id: Variant,
	registry: SystemRegistry
) -> String:
	var canonical := str(registry.resolve_system_id(raw_id))
	return canonical if registry.has_system(canonical) else ""


static func _canonical_gate_id(
	raw_id: Variant,
	registry: SystemRegistry
) -> String:
	var canonical := str(registry.resolve_gate_id(raw_id))
	return canonical if registry.get_gate(canonical) != null else ""


static func _validate_canonical_system(
	raw_id: Variant,
	path: String,
	registry: SystemRegistry,
	result: ValidationResult
) -> void:
	var canonical := _canonical_system_id(raw_id, registry)
	if canonical.is_empty():
		result.add_error(
			"unknown_system",
			"Save references unknown system '%s'." % raw_id,
			path
		)
	elif canonical != str(raw_id):
		result.add_error(
			"legacy_system_id",
			"Save version %d requires canonical system IDs." %
				CURRENT_VERSION,
			path
		)


static func _validate_canonical_gate(
	raw_id: Variant,
	path: String,
	registry: SystemRegistry,
	result: ValidationResult
) -> void:
	var canonical := _canonical_gate_id(raw_id, registry)
	if canonical.is_empty():
		result.add_error(
			"unknown_gate",
			"Save references unknown gate '%s'." % raw_id,
			path
		)
	elif canonical != str(raw_id):
		result.add_error(
			"legacy_gate_id",
			"Save version %d requires canonical gate IDs." %
				CURRENT_VERSION,
			path
		)


static func _has_base_shape(data: Dictionary) -> bool:
	var quest = data.get("quest", null)
	var quest_ok := quest is Dictionary or quest is Array
	return data.get("player", null) is Dictionary \
		and data.get("global", null) is Dictionary \
		and quest_ok \
		and data.get("systems", null) is Dictionary


static func _available_backup_path(path: String) -> String:
	var timestamp := int(Time.get_unix_time_from_system())
	var base := "%s.v%d.%d.backup" % [
		path,
		LEGACY_VERSION,
		timestamp,
	]
	var candidate := base
	var suffix := 1
	while FileAccess.file_exists(candidate):
		candidate = "%s.%d" % [base, suffix]
		suffix += 1
	return candidate


static func _success(data: Variant) -> Dictionary:
	return {
		"ok": true,
		"data": data,
		"error": "",
	}


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"data": {},
		"error": message,
	}
