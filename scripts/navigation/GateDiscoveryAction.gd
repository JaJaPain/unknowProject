class_name GateDiscoveryAction
extends RefCounted

enum ActionType {
	RUMOR,
	SCAN,
	INVESTIGATE,
	REPAIR,
	UNLOCK,
	KAELEN_REVEAL,
}

const STATE_TRANSITIONS: Dictionary = {
	ActionType.RUMOR: ["unknown"],
	ActionType.SCAN: ["rumored"],
	ActionType.INVESTIGATE: ["hidden"],
	ActionType.REPAIR: ["damaged"],
	ActionType.UNLOCK: ["blocked"],
	ActionType.KAELEN_REVEAL: ["rumored", "hidden", "blocked", "damaged"],
}

const TARGET_STATES: Dictionary = {
	ActionType.RUMOR: "rumored",
	ActionType.SCAN: "hidden",
	ActionType.INVESTIGATE: "",
	ActionType.REPAIR: "known",
	ActionType.UNLOCK: "known",
	ActionType.KAELEN_REVEAL: "known",
}

var action_type: ActionType
var gate_id: String
var credit_cost: int = 0
var ore_cost: int = 0
var required_reputation_faction: String = ""
var required_reputation_tier: String = ""
var required_missions_completed: int = 0
var narrative_text: String = ""


static func from_gate_definition(gate_def: GateDefinition) -> GateDiscoveryAction:
	var action := GateDiscoveryAction.new()
	action.gate_id = str(gate_def.id) if &"id" in gate_def else ""
	var action_str := gate_def.discovery_action
	action.action_type = _parse_action_type(action_str)
	var cost: Dictionary = gate_def.discovery_cost
	action.credit_cost = int(cost.get("credits", 0))
	action.ore_cost = int(cost.get("ore", 0))
	var prereqs: Array = gate_def.discovery_prerequisites
	for prereq in prereqs:
		if prereq is Dictionary:
			if prereq.has("reputation_faction"):
				action.required_reputation_faction = str(prereq["reputation_faction"])
				action.required_reputation_tier = str(prereq.get("reputation_tier", "friendly"))
			if prereq.has("missions_completed"):
				action.required_missions_completed = int(prereq["missions_completed"])
	return action


func can_execute(current_state: String) -> bool:
	var valid_from: Array = STATE_TRANSITIONS.get(action_type, [])
	return current_state in valid_from


func get_target_state() -> String:
	if action_type == ActionType.INVESTIGATE:
		return "blocked"
	return str(TARGET_STATES.get(action_type, ""))


func can_player_afford() -> bool:
	if credit_cost > 0 and GlobalState.player_credits < credit_cost:
		return false
	if ore_cost > 0 and int(GlobalState.cargo) < ore_cost:
		return false
	return true


func meets_prerequisites() -> bool:
	if not required_reputation_faction.is_empty():
		var rep: float = GlobalState.reputations.get(required_reputation_faction, 0.0)
		var threshold := _reputation_tier_threshold(required_reputation_tier)
		if rep < threshold:
			return false
	if required_missions_completed > 0:
		var completed := QuestManager.get_completed_count()
		if completed < required_missions_completed:
			return false
	return true


func get_cost_text() -> String:
	var parts: Array[String] = []
	if credit_cost > 0:
		parts.append("%d SC" % credit_cost)
	if ore_cost > 0:
		parts.append("%d ore" % ore_cost)
	if parts.is_empty():
		return "Free"
	return " + ".join(parts)


func get_prerequisite_text() -> String:
	var parts: Array[String] = []
	if not required_reputation_faction.is_empty():
		parts.append("%s rep: %s" % [
			required_reputation_faction.capitalize(),
			required_reputation_tier.capitalize(),
		])
	if required_missions_completed > 0:
		parts.append("%d missions completed" % required_missions_completed)
	return ", ".join(parts) if not parts.is_empty() else ""


static func _parse_action_type(action_str: String) -> ActionType:
	match action_str.to_lower():
		"rumor": return ActionType.RUMOR
		"scan": return ActionType.SCAN
		"investigate": return ActionType.INVESTIGATE
		"repair": return ActionType.REPAIR
		"unlock": return ActionType.UNLOCK
		"kaelen_reveal": return ActionType.KAELEN_REVEAL
	return ActionType.SCAN


static func _reputation_tier_threshold(tier: String) -> float:
	match tier.to_lower():
		"cordial": return 1.0
		"friendly": return 25.0
		"trusted": return 50.0
		"allied": return 75.0
	return 0.0
