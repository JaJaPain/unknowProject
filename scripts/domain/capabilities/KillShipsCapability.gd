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
	# by_player defaults true so legacy callers/tests (which omit it) still count.
	var by_player := bool(event_data.get("by_player", true))
	if not by_player:
		# An NPC (or the environment) destroyed the quest target. Do NOT credit the
		# player — schedule a replacement so the contract stays completable instead
		# of being finished, or stalled, by a kill the player never made.
		if is_completed(data):
			return {}
		return {"needs_respawn": true, "respawn_faction": faction}
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
