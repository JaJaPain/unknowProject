extends RefCounted

const RISK_TAGS = ["combat_target", "valuable_cargo", "urgent"]
const BASE_PRIORITY := 1.0
const URGENT_PRIORITY_BONUS := 0.5
const HOSTILE_REP_THRESHOLD := -10.0
const STORY_PRESSURE_PRIORITY_BONUS := 0.2
const STORY_PRESSURE_COUNT_THRESHOLD := 3


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
	var pack := _current_story_pack(context)
	if not pack.is_empty():
		if not str(pack.get("active_tension", "")).strip_edges().is_empty():
			p += STORY_PRESSURE_PRIORITY_BONUS
		if int(pack.get("arc_pressure", 0)) >= STORY_PRESSURE_COUNT_THRESHOLD:
			p += STORY_PRESSURE_PRIORITY_BONUS
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
	var local_faction := _pick_story_faction(context)
	if not local_faction.is_empty():
		return local_faction
	return "reaver"


func _pick_count(context) -> int:
	if context == null:
		return 1
	var base := 1
	if "urgent" in context.active_mission_risk_tags:
		base += 1
	if "combat_target" in context.active_mission_risk_tags:
		base += 1
	var pack := _current_story_pack(context)
	if int(pack.get("arc_pressure", 0)) >= STORY_PRESSURE_COUNT_THRESHOLD:
		base += 1
	return mini(base, 3)


func _pick_story_faction(context) -> String:
	var config = _current_system_config(context)
	if config == null or config.faction_weights.is_empty():
		return ""
	var factions: Array = config.faction_weights.keys()
	if factions.is_empty():
		return ""
	var pack: Dictionary = config.story_pack
	var tension := str(pack.get("active_tension", "")).to_lower()
	for faction_name in factions:
		var candidate := str(faction_name)
		if tension.find(_story_faction_label(candidate).to_lower()) != -1:
			return candidate
	for faction_name in factions:
		var candidate := str(faction_name)
		if candidate not in ["zenith", "aurelia", "vanguard"]:
			return candidate
	return str(factions[0])


func _current_story_pack(context) -> Dictionary:
	var config = _current_system_config(context)
	if config == null:
		return {}
	return config.story_pack


func _current_system_config(context):
	if context == null:
		return null
	var registry = null
	if "system_registry" in context:
		registry = context.system_registry
	if registry == null or not registry.has_method("get_generated_config"):
		return null
	var config = registry.get_generated_config(str(context.current_system_id))
	if config != null:
		return config
	if registry.has_method("resolve_system_id"):
		config = registry.get_generated_config(
			str(registry.resolve_system_id(context.current_system_id))
		)
		if config != null:
			return config
	if registry.has_method("runtime_system_id"):
		var runtime_id := str(registry.runtime_system_id(context.current_system_id))
		if not runtime_id.is_empty():
			config = registry.get_generated_config(runtime_id)
	return config


func _story_faction_label(faction_name: String) -> String:
	var clean := faction_name.strip_edges()
	if clean.begins_with("gen_"):
		clean = clean.trim_prefix("gen_")
	var parts := clean.replace("_", " ").split(" ", false)
	var titled: Array[String] = []
	for part in parts:
		var lower := str(part).to_lower()
		if lower.length() <= 2 and lower.is_valid_int():
			continue
		titled.append(lower.substr(0, 1).to_upper() + lower.substr(1))
	if titled.is_empty():
		return clean.capitalize()
	return " ".join(titled)
