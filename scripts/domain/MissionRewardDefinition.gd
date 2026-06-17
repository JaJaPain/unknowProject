class_name MissionRewardDefinition
extends RefCounted

const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

var credits: int = 0
var reputation: Dictionary = {}


func load_from_objective(source: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	var raw_credits: Variant = source.get("reward_credits", null)
	if not raw_credits is int and not raw_credits is float:
		result.add_error(
			"invalid_reward",
			"reward_credits must be numeric.",
			"reward_credits"
		)
	else:
		credits = int(raw_credits)
		if credits < 0:
			result.add_error(
				"invalid_reward",
				"reward_credits cannot be negative.",
				"reward_credits"
			)
	return result


func to_dict() -> Dictionary:
	return {
		"credits": credits,
		"reputation": reputation.duplicate(true),
	}
