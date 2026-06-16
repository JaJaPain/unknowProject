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
	_validate_timing(source, result)

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


func _validate_timing(
	source: Dictionary,
	result: ValidationResult
) -> void:
	var is_timed := bool(source.get("is_timed", false))
	if not is_timed:
		return
	var accepted := int(source.get("accepted_time_minutes", -1))
	var duration := int(source.get("expires_after_minutes", 0))
	var deadline := int(source.get("deadline_time_minutes", 0))
	if accepted < 0:
		result.add_error(
			"invalid_timing",
			"Timed missions require accepted_time_minutes >= 0.",
			"accepted_time_minutes"
		)
	if duration <= 0:
		result.add_error(
			"invalid_timing",
			"Timed missions require expires_after_minutes > 0.",
			"expires_after_minutes"
		)
	if deadline <= accepted:
		result.add_error(
			"invalid_timing",
			"Timed missions require deadline_time_minutes after acceptance.",
			"deadline_time_minutes"
		)
	if str(source.get("expiration_policy", "")).strip_edges().is_empty():
		result.add_error(
			"invalid_timing",
			"Timed missions require an expiration_policy.",
			"expiration_policy"
		)
	if float(source.get("urgent_reward_multiplier", 1.0)) < 1.0:
		result.add_error(
			"invalid_timing",
			"urgent_reward_multiplier cannot be below 1.0.",
			"urgent_reward_multiplier"
		)
	if int(source.get("base_reward_credits", 0)) < 0:
		result.add_error(
			"invalid_timing",
			"base_reward_credits cannot be negative.",
			"base_reward_credits"
		)
