class_name MissionAdapter
extends RefCounted

const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)
const DefinitionType := preload(
	"res://scripts/domain/MissionDefinition.gd"
)
const ConsequenceType := preload(
	"res://scripts/domain/MissionConsequenceDefinition.gd"
)
const StateType := preload("res://scripts/domain/MissionState.gd")


static func build_active_state(
	quest_data: Dictionary,
	selected_choice: Dictionary,
	runtime_id: String,
	system_id: String
) -> Dictionary:
	var definition := DefinitionType.new()
	var validation := definition.load_from_offer(quest_data)
	var consequence := ConsequenceType.new()
	validation.merge(
		consequence.load_from_choice(selected_choice),
		"selected_choice"
	)
	if not validation.is_valid():
		return {
			"state": {},
			"validation": validation,
		}

	var objective := definition.objective.to_dict()
	var state := {
		"mission_schema_version": StateType.SCHEMA_VERSION,
		"definition_id": str(definition.id),
		"runtime_id": runtime_id,
		"title": definition.title,
		"faction": str(quest_data.get("faction", "neutral")),
		"faction_id": str(definition.faction_id),
		"agent_name": str(quest_data.get("agent_name", "Broker Kaelen")),
		"giver_npc_id": str(definition.giver_npc_id),
		"dialogue": definition.dialogue,
		"objective_type": definition.objective.type,
		"combat_multiplier": consequence.combat_multiplier,
		"reward_credits_multiplier": consequence.reward_credits_multiplier,
		"reward_credits": definition.reward.credits,
		"choice_text_selected": str(selected_choice.get("text", "")),
		"agent_response": consequence.dialogue_response,
		"system_id": system_id,
		"target_spawn_sequence": 0,
		"timing": definition.timing.to_dict(),
	}

	match definition.objective.type:
		"KILL_SHIPS":
			state["target_faction"] = str(
				objective.get("target_faction", "zenith")
			)
			state["count_required"] = max(
				1,
				int(
					float(objective.get("count_required", 3))
					* consequence.combat_multiplier
				)
			)
			state["current_count"] = 0
		"DELIVER_ORE":
			state["amount_required"] = maxf(
				1.0,
				snappedf(float(objective.get("amount_required", 20.0)), 1.0)
			)
			state["partial_delivered"] = 0.0
		"PICKUP_SPECIAL":
			state["target_outpost"] = str(objective.get("target_outpost", ""))
			state["target_outpost_display"] = str(
				objective.get(
					"target_outpost_display",
					state["target_outpost"]
				)
			)
			state["target_npc"] = str(objective.get("target_npc", ""))
			state["part_name"] = str(
				objective.get("part_name", "Unknown Part")
			)
			state["destination"] = str(
				objective.get("destination", "Grease Monkeys")
			)
			state["picked_up"] = false

	var state_validation := StateType.new().load_from_dict(state)
	validation.merge(state_validation, "state")
	return {
		"state": state if validation.is_valid() else {},
		"validation": validation,
		"definition": definition,
		"consequence": consequence,
	}


static func validate_active_state(source: Dictionary) -> ValidationResult:
	return StateType.new().load_from_dict(source)


static func normalize_legacy_state(source: Dictionary) -> Dictionary:
	if source.is_empty():
		return {}
	var normalized := source.duplicate(true)
	if not normalized.has("mission_schema_version"):
		normalized["mission_schema_version"] = StateType.SCHEMA_VERSION
	if str(normalized.get("definition_id", "")).is_empty():
		normalized["definition_id"] = DefinitionType.derive_offer_id({
			"title": normalized.get("title", ""),
			"faction": normalized.get("faction", "neutral"),
			"agent_name": normalized.get("agent_name", "Broker Kaelen"),
			"objective": _legacy_objective(normalized),
		})
	if str(normalized.get("runtime_id", "")).is_empty():
		var source_text := JSON.stringify(normalized)
		normalized["runtime_id"] = "mission.legacy.%s" % (
			source_text.sha256_text().substr(0, 16)
		)
	normalized["reward_credits"] = int(
		normalized.get("reward_credits", 0)
	)
	normalized["reward_credits_multiplier"] = maxf(
		0.5,
		float(normalized.get("reward_credits_multiplier", 1.0))
	)
	normalized["choice_text_selected"] = str(
		normalized.get("choice_text_selected", "")
	)
	normalized["system_id"] = str(
		normalized.get("system_id", "start_system")
	)
	match str(normalized.get("objective_type", "")):
		"KILL_SHIPS":
			normalized["current_count"] = max(
				0,
				int(normalized.get("current_count", 0))
			)
		"DELIVER_ORE":
			normalized["partial_delivered"] = maxf(
				0.0,
				float(normalized.get("partial_delivered", 0.0))
			)
		"PICKUP_SPECIAL":
			normalized["picked_up"] = bool(
				normalized.get("picked_up", false)
			)
	return normalized


static func _legacy_objective(source: Dictionary) -> Dictionary:
	var objective := {"type": str(source.get("objective_type", ""))}
	for field in [
		"target_faction",
		"count_required",
		"amount_required",
		"target_outpost",
		"target_outpost_display",
		"target_npc",
		"part_name",
		"destination",
		"reward_credits",
	]:
		if source.has(field):
			objective[field] = source[field]
	return objective
