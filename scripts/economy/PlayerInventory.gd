extends RefCounted

signal item_changed(item_id: String, new_quantity: int)

var _items: Dictionary = {}
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


func add(item_id: String, quantity: int = 1, stack_max: int = -1) -> bool:
	if not can_add(item_id, quantity, stack_max):
		return false
	_items[item_id] = int(_items.get(item_id, 0)) + quantity
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
	else:
		_items[item_id] = after
	item_changed.emit(item_id, after)
	return true


func has_item(item_id: String, min_quantity: int = 1) -> bool:
	return _items.get(item_id, 0) >= min_quantity


func get_quantity(item_id: String) -> int:
	return _items.get(item_id, 0)


func get_all() -> Dictionary:
	return _items.duplicate()


func clear() -> void:
	_items.clear()


func to_dict() -> Dictionary:
	var out := _items.duplicate()
	out["__max_slots"] = max_slots
	return out


static func from_dict(data: Dictionary):
	var inv = new()
	for key in data.keys():
		if key == "__max_slots":
			inv.max_slots = int(data[key])
			continue
		var qty = int(data[key])
		if qty > 0:
			inv._items[str(key)] = qty
	return inv
