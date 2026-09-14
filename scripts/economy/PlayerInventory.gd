extends RefCounted

signal item_changed(item_id: String, new_quantity: int)

var _items: Dictionary = {}
var _origins: Dictionary = {} # item_id -> origin_id -> quantity
var max_slots: int = 8


func slot_count() -> int:
	return _items.size()


func is_full() -> bool:
	return _items.size() >= max_slots


func can_add(item_id: String, quantity: int = 1, stack_max: int = -1) -> bool:
	if quantity <= 0 or item_id.is_empty():
		return false
	if not _items.has(item_id) and _items.size() >= max_slots:
		return false
	if stack_max > 0:
		var after: int = int(_items.get(item_id, 0)) + quantity
		if after > stack_max:
			return false
	return true


func add(
	item_id: String,
	quantity: int = 1,
	stack_max: int = -1,
	origin_id: String = "unknown"
) -> bool:
	if not can_add(item_id, quantity, stack_max):
		return false
	_items[item_id] = int(_items.get(item_id, 0)) + quantity
	_add_origin(item_id, origin_id, quantity)
	item_changed.emit(item_id, _items[item_id])
	return true


func remove(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0 or item_id.is_empty():
		return false
	var current: int = _items.get(item_id, 0)
	if current < quantity:
		return false
	var after: int = current - quantity
	if after == 0:
		_items.erase(item_id)
		_origins.erase(item_id)
	else:
		_items[item_id] = after
		_remove_origin_quantity(item_id, quantity)
	item_changed.emit(item_id, after)
	return true


func remove_for_sale(item_id: String, destination_origin: String) -> String:
	var origin := best_origin_for_sale(item_id, destination_origin)
	if origin.is_empty():
		return ""
	if not remove_from_origin(item_id, origin, 1):
		return ""
	return origin


func remove_from_origin(item_id: String, origin_id: String, quantity: int = 1) -> bool:
	if quantity <= 0 or get_origin_quantity(item_id, origin_id) < quantity:
		return false
	var current: int = int(_items.get(item_id, 0))
	if current < quantity:
		return false
	var origin_map: Dictionary = _origins.get(item_id, {})
	var after_origin := int(origin_map.get(origin_id, 0)) - quantity
	if after_origin <= 0:
		origin_map.erase(origin_id)
	else:
		origin_map[origin_id] = after_origin
	if origin_map.is_empty():
		_origins.erase(item_id)
	else:
		_origins[item_id] = origin_map
	var after := current - quantity
	if after <= 0:
		_items.erase(item_id)
		_origins.erase(item_id)
	else:
		_items[item_id] = after
	item_changed.emit(item_id, maxi(after, 0))
	return true


func has_item(item_id: String, min_quantity: int = 1) -> bool:
	return _items.get(item_id, 0) >= min_quantity


func get_quantity(item_id: String) -> int:
	return _items.get(item_id, 0)


func get_origin_quantity(item_id: String, origin_id: String) -> int:
	var origin_map: Dictionary = _origins.get(item_id, {})
	return int(origin_map.get(origin_id, 0))


func best_origin_for_sale(item_id: String, destination_origin: String) -> String:
	var origin_map: Dictionary = _origins.get(item_id, {})
	if origin_map.is_empty():
		return "unknown" if get_quantity(item_id) > 0 else ""
	for origin_id in origin_map.keys():
		if str(origin_id) != destination_origin and int(origin_map[origin_id]) > 0:
			return str(origin_id)
	if origin_map.has(destination_origin) and int(origin_map[destination_origin]) > 0:
		return destination_origin
	for origin_id in origin_map.keys():
		if int(origin_map[origin_id]) > 0:
			return str(origin_id)
	return ""


func get_origins(item_id: String) -> Dictionary:
	return (_origins.get(item_id, {}) as Dictionary).duplicate()


func get_all() -> Dictionary:
	return _items.duplicate()


func clear() -> void:
	_items.clear()
	_origins.clear()


func to_dict() -> Dictionary:
	var out := _items.duplicate()
	out["__max_slots"] = max_slots
	out["__origins"] = _origins.duplicate(true)
	return out


static func from_dict(data: Dictionary):
	var inv = new()
	for key in data.keys():
		if key == "__max_slots":
			inv.max_slots = int(data[key])
			continue
		if key == "__origins":
			continue
		var qty = int(data[key])
		if qty > 0:
			inv._items[str(key)] = qty
	var origins: Dictionary = data.get("__origins", {})
	if origins is Dictionary:
		for item_id in origins.keys():
			if not inv._items.has(str(item_id)):
				continue
			var origin_map: Dictionary = origins[item_id]
			var cleaned: Dictionary = {}
			var total := 0
			for origin_id in origin_map.keys():
				var qty := int(origin_map[origin_id])
				if qty > 0:
					cleaned[str(origin_id)] = qty
					total += qty
			if total > 0:
				inv._origins[str(item_id)] = cleaned
	for item_id in inv._items.keys():
		if not inv._origins.has(item_id):
			inv._origins[item_id] = {"unknown": int(inv._items[item_id])}
	return inv


func _add_origin(item_id: String, origin_id: String, quantity: int) -> void:
	var clean_origin := origin_id.strip_edges()
	if clean_origin.is_empty():
		clean_origin = "unknown"
	var origin_map: Dictionary = _origins.get(item_id, {})
	origin_map[clean_origin] = int(origin_map.get(clean_origin, 0)) + quantity
	_origins[item_id] = origin_map


func _remove_origin_quantity(item_id: String, quantity: int) -> void:
	var remaining := quantity
	var origin_map: Dictionary = _origins.get(item_id, {})
	for origin_id in origin_map.keys():
		if remaining <= 0:
			break
		var available := int(origin_map[origin_id])
		var take = mini(available, remaining)
		available -= take
		remaining -= take
		if available <= 0:
			origin_map.erase(origin_id)
		else:
			origin_map[origin_id] = available
	if origin_map.is_empty():
		_origins.erase(item_id)
	else:
		_origins[item_id] = origin_map
