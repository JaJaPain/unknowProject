extends MissionCapability


func capability_id() -> String:
	return "delivery_courier"


func supported_objective_types() -> Array[String]:
	return ["DELIVERY_COURIER"]


func is_completed(data: Dictionary) -> bool:
	var gs := _global_state()
	if gs == null:
		return false
	var expected_item := str(data.get("item_name", ""))
	return bool(data.get("cargo_loaded", false)) \
		and int(gs.cargo_type) == int(gs.CargoType.SPECIAL) \
		and str(gs.cargo_special.get("name", "")) == expected_item


func handle_event(_data: Dictionary, _event: String, _event_data: Dictionary) -> Dictionary:
	return {}


func format_tracker_text(data: Dictionary) -> String:
	return "Courier: %s -> %s" % [
		str(data.get("item_name", "package")),
		str(data.get("destination_display", "destination")),
	]


func on_complete(data: Dictionary) -> Dictionary:
	if not is_completed(data):
		return {"block": "assigned cargo is not in the hold"}
	return {"clear_cargo": true}


func on_cleanup(data: Dictionary) -> Dictionary:
	var gs := _global_state()
	if gs == null:
		return {}
	var expected_item := str(data.get("item_name", ""))
	if int(gs.cargo_type) == int(gs.CargoType.SPECIAL) \
			and str(gs.cargo_special.get("name", "")) == expected_item:
		return {"clear_cargo": true}
	return {}


func _global_state() -> Node:
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not main_loop.has_method("get_root"):
		return null
	var root = main_loop.root
	if root == null:
		return null
	return root.get_node_or_null("GlobalState")
