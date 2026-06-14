class_name MissionConsequenceDefinition
extends RefCounted

const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

var credits_immediate: int = 0
var reputation_change: Dictionary = {}
var combat_multiplier: float = 1.0
var reward_credits_multiplier: float = 1.0
var dialogue_response: String = ""


func load_from_choice(choice: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	var source: Variant = choice.get("consequence", {})
	if not source is Dictionary:
		result.add_error(
			"invalid_consequence",
			"Choice consequence must be an object.",
			"consequence"
		)
		return result
	var consequence := source as Dictionary
	credits_immediate = int(consequence.get("credits_immediate", 0))
	var raw_rep: Variant = consequence.get("reputation_change", {})
	if not raw_rep is Dictionary:
		result.add_error(
			"invalid_reputation_change",
			"reputation_change must be an object.",
			"consequence.reputation_change"
		)
	else:
		reputation_change = (raw_rep as Dictionary).duplicate(true)
	combat_multiplier = maxf(
		0.5,
		float(consequence.get("combat_multiplier", 1.0))
	)
	reward_credits_multiplier = maxf(
		0.5,
		float(consequence.get("reward_credits_multiplier", 1.0))
	)
	dialogue_response = str(consequence.get("dialogue_response", ""))
	return result


func to_dict() -> Dictionary:
	return {
		"credits_immediate": credits_immediate,
		"reputation_change": reputation_change.duplicate(true),
		"combat_multiplier": combat_multiplier,
		"reward_credits_multiplier": reward_credits_multiplier,
		"dialogue_response": dialogue_response,
	}
