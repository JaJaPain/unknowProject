extends RefCounted

const RISK_TAGS = ["combat_target", "valuable_cargo", "urgent"]
const BASE_PRIORITY := 1.0
const URGENT_PRIORITY_BONUS := 0.5
const HOSTILE_REP_THRESHOLD := -10.0


func event_type_id() -> String:
	return "interceptor"


func is_eligible(context) -> bool:
	if not context.just_arrived:
		return false
	for tag in context.active_mission_risk_tags:
		if tag in RISK_TAGS:
			return true
	return false


func priority(context) -> float:
	var p := BASE_PRIORITY
	if context and "active_mission_risk_tags" in context:
		if "urgent" in context.active_mission_risk_tags:
			p += URGENT_PRIORITY_BONUS
		if "combat_target" in context.active_mission_risk_tags:
			p += 0.25
	return p


func execute(context) -> Dictionary:
	var faction := _pick_faction(context)
	var count := _pick_count(context)
	return {
		"event": "interceptor",
		"faction": faction,
		"count": count,
		"system": context.current_system_id if context else "",
		"time": context.campaign_time if context else 0,
	}


func _pick_faction(context) -> String:
	if context == null:
		return "reaver"
	if "combat_target" in context.active_mission_risk_tags:
		var worst_faction := ""
		var worst_rep := 999.0
		for faction in context.reputations.keys():
			var rep: float = float(context.reputations[faction])
			if rep < worst_rep:
				worst_rep = rep
				worst_faction = faction
		if not worst_faction.is_empty() and worst_rep < HOSTILE_REP_THRESHOLD:
			return worst_faction
	return "reaver"


func _pick_count(context) -> int:
	if context == null:
		return 1
	var base := 1
	if "urgent" in context.active_mission_risk_tags:
		base += 1
	if "combat_target" in context.active_mission_risk_tags:
		base += 1
	return mini(base, 3)
