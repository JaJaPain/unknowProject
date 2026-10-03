extends MissionCapability


func capability_id() -> String:
	return "pickup_special"


func supported_objective_types() -> Array[String]:
	return ["PICKUP_SPECIAL"]


func is_completed(data: Dictionary) -> bool:
	return bool(data.get("picked_up", false))


func handle_event(_data: Dictionary, _event: String, _event_data: Dictionary) -> Dictionary:
	return {}


## Where, who and how (playtest 2026-10-03 finding 14): QuestNextStep.
func format_tracker_text(data: Dictionary) -> String:
	return str(preload("res://scripts/domain/QuestNextStep.gd").for_quest(data)["text"])


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
