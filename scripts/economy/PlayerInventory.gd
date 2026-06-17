extends RefCounted

signal item_changed(item_id: String, new_quantity: int)

var _items: Dictionary = {}


func add(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0 or item_id.is_empty():
		return false
	_items[item_id] = _items.get(item_id, 0) + quantity
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
	return _items.duplicate()


static func from_dict(data: Dictionary):
	var inv = new()
	for key in data.keys():
		var qty = int(data[key])
		if qty > 0:
			inv._items[str(key)] = qty
	return inv
