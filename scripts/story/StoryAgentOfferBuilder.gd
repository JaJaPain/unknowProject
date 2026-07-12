class_name StoryAgentOfferBuilder
extends RefCounted

const MissionAdapterType := preload("res://scripts/domain/MissionAdapter.gd")
const MissionTemplateRegistryType := preload(
	"res://scripts/domain/MissionTemplateRegistry.gd"
)
const PublicBoardOfferBuilderType := preload(
	"res://scripts/domain/PublicBoardOfferBuilder.gd"
)

const TEMPLATE_ONLY_OBJECTIVES := [
	"DELIVERY_COURIER",
	"PURCHASE_DELIVERY",
	"RECOVER_COMBAT_DROP",
	"TARGET_WITH_COMMS_REVERSAL",
]


static func can_build(agent_profile: Dictionary) -> bool:
	var candidate := _candidate(agent_profile)
	return str(candidate.get("objective_type", "")) in TEMPLATE_ONLY_OBJECTIVES


static func build_offer(
	agent_faction: String,
	agent_profile: Dictionary,
	current_time_minutes: int = 0
) -> Dictionary:
	var story_context: Dictionary = agent_profile.get("story_agent_offer_context", {}) \
		if agent_profile.get("story_agent_offer_context", {}) is Dictionary else {}
	var candidate: Dictionary = story_context.get("candidate", {}) \
		if story_context.get("candidate", {}) is Dictionary else {}
	var budget: Dictionary = story_context.get("budget", {}) \
		if story_context.get("budget", {}) is Dictionary else {}
	if candidate.is_empty():
		return {}
	var objective_type := str(candidate.get("objective_type", ""))
	if not objective_type in TEMPLATE_ONLY_OBJECTIVES:
		return {}
	var objective := _objective_for_candidate(
		objective_type,
		candidate,
		budget,
		current_time_minutes
	)
	if objective.is_empty():
		return {}
	var agent_name := str(agent_profile.get("agent_name", "Local Contact"))
	if agent_name.strip_edges().is_empty():
		agent_name = "Local Contact"
	var agent_role := str(agent_profile.get("agent_role", "Station faction contact"))
	var title := _title_for_candidate(candidate, objective)
	var dialogue := _dialogue_for_candidate(candidate, objective, budget)
	var quest := {
		"title": title,
		"campaign_name": _campaign_name(),
		"faction": agent_faction if not agent_faction.strip_edges().is_empty() else "neutral",
		"agent_name": agent_name,
		"agent_role": agent_role,
		"agent_portrait_id": str(agent_profile.get("agent_portrait_id", "")),
		"agent_voice_profile_id": str(agent_profile.get("agent_voice_profile_id", "")),
		"agent_memory_id": str(agent_profile.get("agent_memory_id", "")),
		"dialogue": dialogue,
		"objective": objective,
		"objective_summary": _objective_summary(objective),
		"choices": [_accept_choice()],
		"narrative_metadata": _narrative_metadata(candidate, budget),
		"story_thread_id": str(candidate.get("thread_id", "")),
		"story_beat_id": str(candidate.get("beat_id", "")),
		"cause_id": str(candidate.get("cause_id", "")),
		"stake": str(candidate.get("stake", "")),
		"story_hook_ref": str(candidate.get("thread_id", "")),
	}
	var timing := _timing_from_budget(budget)
	if not timing.is_empty():
		quest["timing"] = timing
	var validation := MissionAdapterType.build_active_state(
		quest,
		quest["choices"][0],
		"mission.runtime.story_agent_preview",
		str(_global_state_value("current_system_id", "start_system")),
		current_time_minutes
	)
	var validation_result = validation.get("validation")
	if validation_result == null or not validation_result.is_valid():
		return {}
	return quest


static func _candidate(agent_profile: Dictionary) -> Dictionary:
	var story_context: Dictionary = agent_profile.get("story_agent_offer_context", {}) \
		if agent_profile.get("story_agent_offer_context", {}) is Dictionary else {}
	return story_context.get("candidate", {}) \
		if story_context.get("candidate", {}) is Dictionary else {}


static func _objective_for_candidate(
	objective_type: String,
	candidate: Dictionary,
	budget: Dictionary,
	current_time_minutes: int
) -> Dictionary:
	match objective_type:
		"DELIVERY_COURIER":
			return _delivery_courier_objective(candidate)
		"PURCHASE_DELIVERY":
			return _purchase_delivery_objective(current_time_minutes)
		"RECOVER_COMBAT_DROP":
			return _recover_combat_drop_objective(candidate, budget)
		"TARGET_WITH_COMMS_REVERSAL":
			return _target_with_comms_reversal_objective(candidate, budget)
	return {}


static func _delivery_courier_objective(candidate: Dictionary) -> Dictionary:
	var destination := _destination_outpost(candidate)
	if destination.is_empty():
		return {}
	var item_name := _story_item_name(candidate, "Sealed Courier Package")
	return {
		"type": "DELIVERY_COURIER",
		"item_name": item_name,
		"origin_station_id": _main_station_id(),
		"origin_display": _main_station_display(),
		"destination_station_id": str(destination.get("id", "")),
		"destination_display": str(destination.get("display", destination.get("id", ""))),
		"reward_credits": 220,
	}


static func _purchase_delivery_objective(current_time_minutes: int) -> Dictionary:
	var item := PublicBoardOfferBuilderType._store_purchase_item(current_time_minutes)
	if item.is_empty():
		return {}
	var item_id := str(item.get("item_id", ""))
	var item_name := str(item.get("display_name", item_id))
	return {
		"type": "PURCHASE_DELIVERY",
		"item_id": item_id,
		"item_name": item_name,
		"quantity_required": int(item.get("quantity", 1)),
		"store_station_id": str(item.get("station_id", _main_station_id())),
		"store_display": str(item.get("store_display", _main_station_display())),
		"destination_station_id": _main_station_id(),
		"destination_display": _main_station_display(),
		"reward_credits": int(item.get("base_price", 20)) + 140,
	}


static func _recover_combat_drop_objective(
	candidate: Dictionary,
	budget: Dictionary
) -> Dictionary:
	var count := int(budget.get("kill_count", 0))
	if count <= 0:
		count = 3
	return {
		"type": "RECOVER_COMBAT_DROP",
		"target_faction": _target_faction(candidate),
		"count_required": count,
		"drop_chance": 0.33,
		"item_name": _story_item_name(candidate, "data pack"),
		"turn_in_location": _main_station_display(),
		"reward_credits": int(round(520.0 * float(budget.get("reward_multiplier", 1.0)))),
	}


static func _target_with_comms_reversal_objective(
	candidate: Dictionary,
	budget: Dictionary
) -> Dictionary:
	var count := int(budget.get("kill_count", 0))
	if count <= 0:
		count = 3
	return {
		"type": "TARGET_WITH_COMMS_REVERSAL",
		"target_faction": _target_faction(candidate),
		"count_required": count,
		"reward_credits": int(round(620.0 * float(budget.get("reward_multiplier", 1.0)))),
	}


static func _narrative_metadata(candidate: Dictionary, budget: Dictionary) -> Dictionary:
	return {
		"story_thread_id": str(candidate.get("thread_id", "")),
		"story_beat_id": str(candidate.get("beat_id", "")),
		"story_hook_ref": str(candidate.get("thread_id", "")),
		"cause_id": str(candidate.get("cause_id", "")),
		"public_because": str(candidate.get("world_consequence", "")),
		"stake": str(candidate.get("stake", "")),
		"question_fact_ids": (
			candidate.get("disclosure_fact_ids", []) as Array
		).duplicate(true) if candidate.get("disclosure_fact_ids", []) is Array else [],
		"completion_fact_ids": (
			candidate.get("completion_fact_ids", []) as Array
		).duplicate(true) if candidate.get("completion_fact_ids", []) is Array else [],
		"outcome_snapshot": {
			"story_candidate": candidate.duplicate(true),
			"challenge_budget": budget.duplicate(true),
		},
	}


static func _timing_from_budget(budget: Dictionary) -> Dictionary:
	var deadline := int(budget.get("deadline_minutes", 0))
	if deadline <= 0:
		return {}
	return {
		"timed": true,
		"urgent": str(budget.get("difficulty_band", "")) in ["dangerous", "story_climax"],
		"duration_minutes": deadline,
		"expiration_policy": "fail",
		"urgent_reward_multiplier": float(budget.get("reward_multiplier", 1.0)),
	}


static func _accept_choice() -> Dictionary:
	return {
		"text": "Accept contract.",
		"consequence": {
			"credits_immediate": 0,
			"reputation_change": {},
			"combat_multiplier": 1.0,
			"reward_credits_multiplier": 1.0,
			"dialogue_response": "Good. I will mark the window and keep the channel warm.",
		},
	}


static func _title_for_candidate(candidate: Dictionary, objective: Dictionary) -> String:
	var stake := str(candidate.get("stake", "")).strip_edges()
	match str(objective.get("type", "")):
		"DELIVERY_COURIER":
			return "Courier: %s" % str(objective.get("item_name", "Sealed Package"))
		"PURCHASE_DELIVERY":
			return "Procurement: %s" % str(objective.get("item_name", "Supplies"))
		"RECOVER_COMBAT_DROP":
			return "Recover: %s" % str(objective.get("item_name", "Data Pack"))
		"TARGET_WITH_COMMS_REVERSAL":
			return "Interdict: %s" % _target_faction_display(str(objective.get("target_faction", "")))
	return stake.left(80) if not stake.is_empty() else "Story Contract"


static func _dialogue_for_candidate(
	candidate: Dictionary,
	objective: Dictionary,
	budget: Dictionary
) -> String:
	var stake := str(candidate.get("stake", "")).strip_edges()
	var complication := str(candidate.get("complication", "")).strip_edges()
	var objective_summary := _objective_summary(objective)
	var band := str(budget.get("difficulty_band", "routine"))
	var text := "%s. The job is %s." % [
		stake if not stake.is_empty() else "This contract is tied to local pressure",
		objective_summary,
	]
	if not complication.is_empty():
		text += " Complication: %s." % complication
	if band != "routine":
		text += " Treat it as %s work." % band.replace("_", " ")
	return text


static func _objective_summary(objective: Dictionary) -> String:
	match str(objective.get("type", "")):
		"DELIVERY_COURIER":
			return "deliver %s to %s" % [
				str(objective.get("item_name", "the package")),
				str(objective.get("destination_display", "the destination")),
			]
		"PURCHASE_DELIVERY":
			return "buy %d %s from %s" % [
				int(objective.get("quantity_required", 1)),
				str(objective.get("item_name", "the item")),
				str(objective.get("store_display", "the store")),
			]
		"RECOVER_COMBAT_DROP":
			return "recover %s from %s wreckage" % [
				str(objective.get("item_name", "the data pack")),
				_target_faction_display(str(objective.get("target_faction", ""))),
			]
		"TARGET_WITH_COMMS_REVERSAL":
			return "eliminate %d %s ships; monitor comms before the final shot" % [
				int(objective.get("count_required", 1)),
				_target_faction_display(str(objective.get("target_faction", ""))),
			]
	return "complete the contract"


static func _destination_outpost(candidate: Dictionary) -> Dictionary:
	var wanted := str(candidate.get("location_id", "")).strip_edges()
	var outposts: Array = _global_state_call("get_current_pickup_outposts", [])
	for outpost in outposts:
		if outpost is Dictionary and str((outpost as Dictionary).get("id", "")) == wanted:
			return outpost as Dictionary
	if not outposts.is_empty() and outposts[0] is Dictionary:
		return outposts[0] as Dictionary
	return {}


static func _target_faction(candidate: Dictionary) -> String:
	var faction := str(candidate.get("faction_id", "")).strip_edges()
	if not faction.is_empty():
		return faction
	var factions: Array = _global_state_call("get_current_system_minor_factions", [])
	if not factions.is_empty():
		return str(factions[0])
	return "reavers"


static func _target_faction_display(faction: String) -> String:
	var gs: Node = _global_state()
	if gs != null and gs.has_method("faction_display_name"):
		return str(gs.call("faction_display_name", faction, true))
	return faction.capitalize()


static func _story_item_name(candidate: Dictionary, fallback: String) -> String:
	var fact_ids: Array = candidate.get("completion_fact_ids", []) \
		if candidate.get("completion_fact_ids", []) is Array else []
	if not fact_ids.is_empty():
		var label := str(fact_ids[0]).get_file().replace("_", " ").replace(".", " ")
		if not label.strip_edges().is_empty():
			return label.strip_edges().capitalize()
	return fallback


static func _main_station_id() -> String:
	var system_id := str(_global_state_value("current_system_id", "start_system"))
	return system_id if not system_id.is_empty() else "start_system"


static func _main_station_display() -> String:
	return "the main station"


static func _campaign_name() -> String:
	return "Far Horizon"


static func _global_state() -> Node:
	var tree: MainLoop = Engine.get_main_loop()
	if tree and tree.has_method("get_root"):
		return tree.get_root().get_node_or_null("GlobalState")
	return null


static func _global_state_value(property: String, fallback: Variant) -> Variant:
	var gs: Node = _global_state()
	if gs == null:
		return fallback
	var value = gs.get(property)
	return value if value != null else fallback


static func _global_state_call(method: String, fallback: Variant) -> Variant:
	var gs: Node = _global_state()
	if gs == null or not gs.has_method(method):
		return fallback
	return gs.call(method)
