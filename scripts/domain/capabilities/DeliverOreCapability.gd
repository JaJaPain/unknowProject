extends MissionCapability


func capability_id() -> String:
	return "deliver_ore"


func supported_objective_types() -> Array[String]:
	return ["DELIVER_ORE"]


func is_completed(data: Dictionary) -> bool:
	var banked := float(data.get("partial_delivered", 0.0))
	var in_hold: float = GlobalState.deliverable_ore(str(data.get("ore_type", "")))
	return (banked + in_hold) >= float(data.get("amount_required", 1.0))


func handle_event(_data: Dictionary, _event: String, _event_data: Dictionary) -> Dictionary:
	return {}


func format_tracker_text(data: Dictionary) -> String:
	var banked := float(data.get("partial_delivered", 0.0))
	var ore_type := str(data.get("ore_type", ""))
	var in_hold: float = GlobalState.deliverable_ore(ore_type)
	var required := float(data.get("amount_required", 1.0))
	var total := banked + in_hold
	var label := "Ore" if ore_type.is_empty() else preload("res://scripts/economy/OreTypes.gd").display(ore_type)
	var unit := " m³"
	if ore_type == "fuel":
		label = "Fuel"
		unit = ""
	var text := "%s: %.0f / %.0f%s" % [label, total, required, unit]
	if banked > 0:
		text += " (%.0f banked)" % banked
	if total >= required:
		text += " (Ready)"
	return text


func on_complete(data: Dictionary) -> Dictionary:
	var banked := float(data.get("partial_delivered", 0.0))
	var remaining := maxf(0.0, float(data.get("amount_required", 0.0)) - banked)
	if remaining > 0.0:
		return {"remove_ore": remaining, "remove_ore_type": str(data.get("ore_type", ""))}
	return {}


func on_cleanup(_data: Dictionary) -> Dictionary:
	return {}
