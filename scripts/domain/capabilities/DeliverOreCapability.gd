extends MissionCapability


func capability_id() -> String:
	return "deliver_ore"


func supported_objective_types() -> Array[String]:
	return ["DELIVER_ORE"]


func is_completed(data: Dictionary) -> bool:
	var banked := float(data.get("partial_delivered", 0.0))
	var in_hold: float = (
		GlobalState.cargo
		if GlobalState.cargo_type == GlobalState.CargoType.ORE
		else 0.0
	)
	return (banked + in_hold) >= float(data.get("amount_required", 1.0))


func handle_event(_data: Dictionary, _event: String, _event_data: Dictionary) -> Dictionary:
	return {}


func format_tracker_text(data: Dictionary) -> String:
	var banked := float(data.get("partial_delivered", 0.0))
	var in_hold: float = (
		GlobalState.cargo
		if GlobalState.cargo_type == GlobalState.CargoType.ORE
		else 0.0
	)
	var required := float(data.get("amount_required", 1.0))
	var total := banked + in_hold
	var text := "Ore: %.0f / %.0f m³" % [total, required]
	if banked > 0:
		text += " (%.0f banked)" % banked
	if total >= required:
		text += " (Ready)"
	return text


func on_complete(data: Dictionary) -> Dictionary:
	var banked := float(data.get("partial_delivered", 0.0))
	var remaining := maxf(0.0, float(data.get("amount_required", 0.0)) - banked)
	if remaining > 0.0:
		return {"remove_ore": remaining}
	return {}


func on_cleanup(_data: Dictionary) -> Dictionary:
	return {}
