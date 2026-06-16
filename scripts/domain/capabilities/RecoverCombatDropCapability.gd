extends MissionCapability


func capability_id() -> String:
	return "recover_combat_drop"


func supported_objective_types() -> Array[String]:
	return ["RECOVER_COMBAT_DROP"]


func is_completed(data: Dictionary) -> bool:
	return bool(data.get("ship_log_recovered", false))


func handle_event(data: Dictionary, event: String, event_data: Dictionary) -> Dictionary:
	if event != "ship_destroyed":
		return {}
	var faction := str(event_data.get("faction", ""))
	if str(data.get("target_faction", "")) != faction:
		return {}
	if bool(data.get("ship_log_recovered", false)):
		return {}

	data["current_count"] = int(data.get("current_count", 0)) + 1
	var drop_chance := clampf(float(data.get("drop_chance", 0.33)), 0.01, 1.0)
	var recovered := randf() <= drop_chance

	var result := {"progress_changed": true}
	if recovered:
		data["ship_log_recovered"] = true
		data["ship_log_entry"] = "Recovered %s from %s wreckage after %d eligible kills." % [
			str(data.get("item_name", "data pack")),
			str(data.get("target_faction", "hostile")),
			int(data.get("current_count", 0)),
		]
		result["chatter"] = {
			"source": "SYSTEM",
			"text": "Recovered %s into ship log. Return to %s for payout." % [
				str(data.get("item_name", "data pack")),
				str(data.get("turn_in_location", "station")),
			],
			"color": Color(0.65, 1.0, 0.75),
		}
	else:
		result["needs_respawn"] = true
		result["respawn_faction"] = faction

	return result


func format_tracker_text(data: Dictionary) -> String:
	if bool(data.get("ship_log_recovered", false)):
		return "Recovered: %s | Turn in: %s" % [
			str(data.get("item_name", "data pack")),
			str(data.get("turn_in_location", "station")),
		]
	return "Wrecks searched: %d | Hunt %s until the data turns up" % [
		int(data.get("current_count", 0)),
		str(data.get("target_faction", "hostile")).to_upper(),
	]


func on_complete(data: Dictionary) -> Dictionary:
	if not bool(data.get("ship_log_recovered", false)):
		return {"block": "data is not recovered"}
	return {}


func on_cleanup(_data: Dictionary) -> Dictionary:
	return {}
