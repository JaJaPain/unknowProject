extends MissionCapability


func capability_id() -> String:
	return "kill_ships"


func supported_objective_types() -> Array[String]:
	return ["KILL_SHIPS"]


func is_completed(data: Dictionary) -> bool:
	return int(data.get("current_count", 0)) >= int(data.get("count_required", 1))


func handle_event(data: Dictionary, event: String, event_data: Dictionary) -> Dictionary:
	if event != "ship_destroyed":
		return {}
	var faction := str(event_data.get("faction", ""))
	if str(data.get("target_faction", "")) != faction:
		return {}
	data["current_count"] = int(data.get("current_count", 0)) + 1
	var result := {"progress_changed": true}
	if int(data["current_count"]) < int(data.get("count_required", 0)):
		result["needs_respawn"] = true
		result["respawn_faction"] = faction
	return result


func format_tracker_text(data: Dictionary) -> String:
	return "Kills: %d / %d (%s)" % [
		int(data.get("current_count", 0)),
		int(data.get("count_required", 0)),
		faction_display(data),
	]


func on_complete(data: Dictionary) -> Dictionary:
	return {}


func on_cleanup(data: Dictionary) -> Dictionary:
	return {}
