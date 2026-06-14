class_name MissionObjectiveDefinition
extends RefCounted

const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const TYPE_KILL_SHIPS := "KILL_SHIPS"
const TYPE_DELIVER_ORE := "DELIVER_ORE"
const TYPE_PICKUP_SPECIAL := "PICKUP_SPECIAL"
const SUPPORTED_TYPES := [
	TYPE_KILL_SHIPS,
	TYPE_DELIVER_ORE,
	TYPE_PICKUP_SPECIAL,
]

var type: String = ""
var data: Dictionary = {}


func load_from_dict(source: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	type = str(source.get("type", "")).strip_edges()
	data = source.duplicate(true)
	if not type in SUPPORTED_TYPES:
		result.add_error(
			"unsupported_objective_type",
			"Objective type '%s' is unsupported." % type,
			"type"
		)
		return result

	match type:
		TYPE_KILL_SHIPS:
			_require_text(source, "target_faction", result)
			_require_positive_number(source, "count_required", result)
		TYPE_DELIVER_ORE:
			_require_positive_number(source, "amount_required", result)
		TYPE_PICKUP_SPECIAL:
			for field in [
				"target_outpost",
				"target_npc",
				"part_name",
				"destination",
			]:
				_require_text(source, field, result)
	return result


func to_dict() -> Dictionary:
	var result := data.duplicate(true)
	result["type"] = type
	return result


func _require_text(
	source: Dictionary,
	field: String,
	result: ValidationResult
) -> void:
	if str(source.get(field, "")).strip_edges().is_empty():
		result.add_error(
			"missing_objective_field",
			"Objective field '%s' cannot be empty." % field,
			field
		)


func _require_positive_number(
	source: Dictionary,
	field: String,
	result: ValidationResult
) -> void:
	var value: Variant = source.get(field, null)
	if not value is int and not value is float:
		result.add_error(
			"invalid_objective_number",
			"Objective field '%s' must be numeric." % field,
			field
		)
	elif float(value) <= 0.0:
		result.add_error(
			"invalid_objective_number",
			"Objective field '%s' must be greater than zero." % field,
			field
		)
