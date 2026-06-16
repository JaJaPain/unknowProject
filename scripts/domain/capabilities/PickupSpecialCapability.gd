extends MissionCapability


func capability_id() -> String:
	return "pickup_special"


func supported_objective_types() -> Array[String]:
	return ["PICKUP_SPECIAL"]


func is_completed(data: Dictionary) -> bool:
	return bool(data.get("picked_up", false))


func handle_event(_data: Dictionary, _event: String, _event_data: Dictionary) -> Dictionary:
	return {}


func format_tracker_text(data: Dictionary) -> String:
	if data.get("picked_up", false):
		return "Deliver: %s to %s" % [
			str(data.get("part_name", "item")),
			str(data.get("destination", "station")),
		]
	return "Pickup: %s from %s @ %s" % [
		str(data.get("part_name", "item")),
		str(data.get("target_npc", "contact")),
		str(data.get("target_outpost_display", data.get("target_outpost", "outpost"))),
	]


func on_complete(data: Dictionary) -> Dictionary:
	var expected_part := str(data.get("part_name", ""))
	if GlobalState.cargo_type != GlobalState.CargoType.SPECIAL:
		return {"block": "hold is empty"}
	if GlobalState.cargo_special.get("name", "") != expected_part:
		return {"block": "hold has wrong item"}
	return {"clear_cargo": true}


func on_cleanup(data: Dictionary) -> Dictionary:
	var expected_part := str(data.get("part_name", ""))
	if GlobalState.cargo_type == GlobalState.CargoType.SPECIAL \
			and str(GlobalState.cargo_special.get("name", "")) == expected_part:
		return {"clear_cargo": true}
	return {}
