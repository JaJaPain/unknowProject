extends MissionCapability


func capability_id() -> String:
	return "comms_reversal"


func supported_objective_types() -> Array[String]:
	return ["TARGET_WITH_COMMS_REVERSAL"]


func is_completed(data: Dictionary) -> bool:
	var branch: String = str(data.get("branch_id", ""))
	if branch == "finish_kill":
		return int(data.get("current_count", 0)) >= int(data.get("count_required", 1))
	return bool(data.get("branch_chosen", false))


func handle_event(data: Dictionary, event: String, event_data: Dictionary) -> Dictionary:
	if event != "ship_destroyed":
		return {}
	var faction := str(event_data.get("faction", ""))
	if str(data.get("target_faction", "")) != faction:
		return {}
	if bool(data.get("comms_triggered", false)) and not bool(data.get("branch_chosen", false)):
		return {}
	if bool(data.get("branch_chosen", false)) and str(data.get("branch_id", "")) != "finish_kill":
		return {}
	data["current_count"] = int(data.get("current_count", 0)) + 1
	var threshold: int = int(data.get("count_required", 3)) - 1
	var result := {"progress_changed": true}
	if not bool(data.get("comms_triggered", false)) and int(data["current_count"]) >= threshold:
		data["comms_triggered"] = true
		result["trigger_comms"] = true
		result["comms_faction"] = str(data.get("target_faction", ""))
	elif int(data["current_count"]) < int(data.get("count_required", 0)):
		result["needs_respawn"] = true
		result["respawn_faction"] = faction
	return result


func format_tracker_text(data: Dictionary) -> String:
	if bool(data.get("branch_chosen", false)):
		var branch: String = str(data.get("branch_id", ""))
		match branch:
			"finish_kill":
				return "Target eliminated."
			"accept_bribe":
				return "Deal accepted. Target released."
			"walk_away":
				return "Walked away. No payout."
		return "Resolved."
	if bool(data.get("comms_triggered", false)):
		return "INCOMING TRANSMISSION — respond"
	return "Kills: %d / %d (%s)" % [
		int(data.get("current_count", 0)),
		int(data.get("count_required", 0)),
		faction_display(data),
	]


func on_complete(data: Dictionary) -> Dictionary:
	var branch: String = str(data.get("branch_id", ""))
	var result := {}
	match branch:
		"accept_bribe":
			result["block"] = ""
	return result


func on_cleanup(data: Dictionary) -> Dictionary:
	return {"clear_ceasefire_faction": str(data.get("target_faction", ""))}
