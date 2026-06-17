class_name GateDefinition
extends DomainDefinition

const SUPPORTED_SCHEMA_VERSION := 1

var legacy_id: String = ""
var system_id: StringName
var display_name: String = ""
var destination_system_id: StringName
var destination_gate_id: StringName


func load_from_dict(
	data: Dictionary,
	owning_system_id: StringName
) -> ValidationResult:
	var result := load_common(data, "gate", SUPPORTED_SCHEMA_VERSION)
	system_id = owning_system_id
	legacy_id = str(data.get("legacy_id", ""))
	display_name = str(data.get("display_name", "")).strip_edges()
	destination_system_id = DomainId.canonicalize(
		data.get("destination_system_id", "")
	)
	destination_gate_id = DomainId.canonicalize(
		data.get("destination_gate_id", "")
	)

	if legacy_id.is_empty():
		result.add_error(
			"missing_legacy_id",
			"Gate requires a runtime legacy_id during Phase 1.",
			"legacy_id"
		)
	if display_name.is_empty():
		result.add_error(
			"missing_display_name",
			"Gate requires a display name.",
			"display_name"
		)
	_validate_reference(
		result,
		destination_system_id,
		"system",
		"destination_system_id"
	)
	_validate_reference(
		result,
		destination_gate_id,
		"gate",
		"destination_gate_id"
	)
	return result


func to_dict() -> Dictionary:
	var data := to_common_dict()
	data.merge({
		"legacy_id": legacy_id,
		"system_id": str(system_id),
		"display_name": display_name,
		"destination_system_id": str(destination_system_id),
		"destination_gate_id": str(destination_gate_id),
	})
	return data


static func _validate_reference(
	result: ValidationResult,
	value: StringName,
	expected_namespace: String,
	path: String
) -> void:
	var error := DomainId.validation_error(value, expected_namespace)
	if not error.is_empty():
		result.add_error("invalid_reference", error, path)
