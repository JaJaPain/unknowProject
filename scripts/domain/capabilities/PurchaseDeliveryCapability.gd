extends MissionCapability


func capability_id() -> String:
	return "purchase_delivery"


func supported_objective_types() -> Array[String]:
	return ["PURCHASE_DELIVERY"]


func is_completed(data: Dictionary) -> bool:
	var item_id := str(data.get("item_id", ""))
	var quantity := maxi(1, int(data.get("quantity_required", 1)))
	return GlobalState.inventory.has_item(item_id, quantity)


func handle_event(_data: Dictionary, _event: String, _event_data: Dictionary) -> Dictionary:
	return {}


func format_tracker_text(data: Dictionary) -> String:
	var item_id := str(data.get("item_id", ""))
	var quantity := maxi(1, int(data.get("quantity_required", 1)))
	var owned := GlobalState.inventory.get_quantity(item_id)
	return "Purchase: %d / %d %s | Deliver to %s" % [
		owned,
		quantity,
		str(data.get("item_name", "item")),
		str(data.get("destination_display", "destination")),
	]


func on_complete(data: Dictionary) -> Dictionary:
	var item_id := str(data.get("item_id", ""))
	var quantity := maxi(1, int(data.get("quantity_required", 1)))
	if not GlobalState.inventory.has_item(item_id, quantity):
		return {"block": "required purchased item is missing"}
	return {"remove_inventory_item": item_id, "remove_inventory_quantity": quantity}


func on_cleanup(_data: Dictionary) -> Dictionary:
	return {}
