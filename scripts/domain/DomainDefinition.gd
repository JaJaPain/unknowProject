class_name DomainDefinition
extends RefCounted

const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

var id: StringName
var schema_version: int = 0


func load_common(
	data: Dictionary,
	expected_namespace: String,
	supported_schema_version: int
) -> ValidationResult:
	var result := ValidationResultType.new()
	var raw_id: Variant = data.get("id", "")
	var canonical_id := DomainIdType.canonicalize(raw_id)
	var id_error := DomainIdType.validation_error(
		canonical_id,
		expected_namespace
	)
	if not id_error.is_empty():
		result.add_error("invalid_id", id_error, "id")
	else:
		id = canonical_id

	var raw_version: Variant = data.get("schema_version", null)
	if raw_version == null:
		result.add_error(
			"missing_schema_version",
			"Definition is missing schema_version.",
			"schema_version"
		)
	elif not raw_version is int and not raw_version is float:
		result.add_error(
			"invalid_schema_version",
			"schema_version must be an integer.",
			"schema_version"
		)
	elif raw_version is float and not is_equal_approx(
		float(raw_version),
		floorf(float(raw_version))
	):
		result.add_error(
			"invalid_schema_version",
			"schema_version must be a whole number.",
			"schema_version"
		)
	else:
		schema_version = int(raw_version)
		if schema_version != supported_schema_version:
			result.add_error(
				"unsupported_schema_version",
				"Schema version %d is unsupported; expected %d." % [
					schema_version,
					supported_schema_version,
				],
				"schema_version"
			)
	return result


func to_common_dict() -> Dictionary:
	return {
		"id": str(id),
		"schema_version": schema_version,
	}
