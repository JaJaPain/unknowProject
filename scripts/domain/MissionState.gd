class_name MissionState
extends RefCounted

const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)
const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const ObjectiveType := preload(
	"res://scripts/domain/MissionObjectiveDefinition.gd"
)

const SCHEMA_VERSION := 1

var data: Dictionary = {}


func load_from_dict(source: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	data = source.duplicate(true)
	if source.is_empty():
		return result

	var runtime_id := str(source.get("runtime_id", ""))
	if not DomainIdType.is_valid(runtime_id, "mission"):
		result.add_error(
			"invalid_runtime_id",
			"Active mission requires a valid runtime_id.",
			"runtime_id"
		)
	var definition_id := str(source.get("definition_id", ""))
	if not DomainIdType.is_valid(definition_id, "mission"):
		result.add_error(
			"invalid_definition_id",
			"Active mission requires a valid definition_id.",
			"definition_id"
		)
	if str(source.get("title", "")).strip_edges().is_empty():
		result.add_error(
			"missing_title",
			"Active mission title cannot be empty.",
			"title"
		)

	var objective_type := str(source.get("objective_type", ""))
	if not objective_type in ObjectiveType.SUPPORTED_TYPES:
		result.add_error(
			"unsupported_objective_type",
			"Active mission objective type '%s' is unsupported." % objective_type,
			"objective_type"
		)
		return result

	if float(source.get("reward_credits", 0)) < 0.0:
		result.add_error(
			"invalid_reward",
			"Active mission reward cannot be negative.",
			"reward_credits"
		)

	match objective_type:
		ObjectiveType.TYPE_KILL_SHIPS:
			_require_positive(source, "count_required", result)
			if int(source.get("current_count", -1)) < 0:
				result.add_error(
					"invalid_progress",
					"current_count cannot be negative.",
					"current_count"
				)
			if str(source.get("target_faction", "")).is_empty():
				result.add_error(
					"missing_target",
					"Kill missions require target_faction.",
					"target_faction"
				)
		ObjectiveType.TYPE_DELIVER_ORE:
			_require_positive(source, "amount_required", result)
			if float(source.get("partial_delivered", -1.0)) < 0.0:
				result.add_error(
					"invalid_progress",
					"partial_delivered cannot be negative.",
					"partial_delivered"
				)
		ObjectiveType.TYPE_PICKUP_SPECIAL:
			for field in [
				"target_outpost",
				"target_npc",
				"part_name",
				"destination",
			]:
				if str(source.get(field, "")).strip_edges().is_empty():
					result.add_error(
						"missing_pickup_field",
						"Pickup missions require '%s'." % field,
						field
					)
	return result


func to_dict() -> Dictionary:
	return data.duplicate(true)


func _require_positive(
	source: Dictionary,
	field: String,
	result: ValidationResult
) -> void:
	if float(source.get(field, 0.0)) <= 0.0:
		result.add_error(
			"invalid_requirement",
			"Active mission field '%s' must be greater than zero." % field,
			field
		)
