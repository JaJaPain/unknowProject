extends MissionCapability


func capability_id() -> String:
	return "purchase_delivery"


func supported_objective_types() -> Array[String]:
	return ["PURCHASE_DELIVERY"]


func is_completed(data: Dictionary) -> bool:
	var gs := _global_state()
	if gs == null:
		return false
	var item_id := str(data.get("item_id", ""))
	var quantity := maxi(1, int(data.get("quantity_required", 1)))
	return gs.inventory.has_item(item_id, quantity)


func handle_event(_data: Dictionary, _event: String, _event_data: Dictionary) -> Dictionary:
	return {}


func format_tracker_text(data: Dictionary) -> String:
	var gs := _global_state()
	var item_id := str(data.get("item_id", ""))
	var quantity := maxi(1, int(data.get("quantity_required", 1)))
	var owned := 0
	if gs != null:
		owned = int(gs.inventory.get_quantity(item_id))
	return "Purchase: %d / %d %s | Deliver to %s" % [
		owned,
		quantity,
		str(data.get("item_name", "item")),
		str(data.get("destination_display", "destination")),
	]


func on_complete(data: Dictionary) -> Dictionary:
	var gs := _global_state()
	if gs == null:
		return {"block": "inventory is unavailable"}
	var item_id := str(data.get("item_id", ""))
	var quantity := maxi(1, int(data.get("quantity_required", 1)))
	if not gs.inventory.has_item(item_id, quantity):
		return {"block": "required purchased item is missing"}
	return {"remove_inventory_item": item_id, "remove_inventory_quantity": quantity}


func on_cleanup(_data: Dictionary) -> Dictionary:
	return {}


func _global_state() -> Node:
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not main_loop.has_method("get_root"):
		return null
	var root = main_loop.root
	if root == null:
		return null
	return root.get_node_or_null("GlobalState")
