extends RefCounted

const StoreItemDef := preload("res://scripts/economy/StoreItemDefinition.gd")
const StoreDef := preload("res://scripts/economy/StoreDefinition.gd")

const ITEMS_PATH := "res://data/content/store_items.json"
const LAYOUTS_PATH := "res://data/content/store_layouts.json"

var _item_defs: Dictionary = {}
var _stores: Dictionary = {}
var _icon_sheet_paths: Dictionary = {}

static var _shared = null


static func shared():
	if _shared == null:
		_shared = new()
		_shared._load_data()
	return _shared


static func reset() -> void:
	_shared = null


func get_item(item_id: String) -> StoreItemDef:
	return _item_defs.get(item_id)


func get_all_items() -> Dictionary:
	return _item_defs


func get_icon_sheet_path(sheet_name: String) -> String:
	return str(_icon_sheet_paths.get(sheet_name, ""))


func get_store(store_id: String) -> StoreDef:
	return _stores.get(store_id)


func get_stores_for_station(station_id: String) -> Array:
	var result: Array = []
	for store in _stores.values():
		if store.station_id == station_id:
			result.append(store)
	return result


func restock_all(current_time_minutes: int) -> void:
	for store in _stores.values():
		store.restock_check(current_time_minutes)


func save_stock_state() -> Dictionary:
	var out := {}
	for store_id in _stores.keys():
		out[store_id] = _stores[store_id].to_dict()
	return out


func restore_stock_state(data: Dictionary) -> void:
	for store_id in data.keys():
		if _stores.has(store_id):
			var catalog: Dictionary = _stores[store_id]._catalog
			_stores[store_id] = StoreDef.from_dict(data[store_id], catalog)


func _load_data() -> void:
	_load_items()
	_load_layouts()


func _load_items() -> void:
	var file := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if file == null:
		push_warning("[StoreRegistry] Could not open %s" % ITEMS_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("[StoreRegistry] Failed to parse %s" % ITEMS_PATH)
		return
	var data: Dictionary = json.data
	_icon_sheet_paths = data.get("icon_sheets", {})
	for item_data in data.get("items", []):
		var item_def = StoreItemDef.from_dict(item_data)
		if not item_def.item_id.is_empty():
			_item_defs[item_def.item_id] = item_def


func _load_layouts() -> void:
	var file := FileAccess.open(LAYOUTS_PATH, FileAccess.READ)
	if file == null:
		push_warning("[StoreRegistry] Could not open %s" % LAYOUTS_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("[StoreRegistry] Failed to parse %s" % LAYOUTS_PATH)
		return
	var data: Dictionary = json.data
	for layout in data.get("stores", []):
		var store := StoreDef.new()
		store.store_id = str(layout.get("store_id", ""))
		store.station_id = str(layout.get("station_id", ""))
		var item_ids: Array = layout.get("item_ids", [])
		var stock_overrides: Dictionary = layout.get("stock_overrides", {})
		for item_id in item_ids:
			var item_def: StoreItemDef = _item_defs.get(str(item_id))
			if item_def:
				var initial: int = int(stock_overrides.get(str(item_id), -1))
				store.add_item(item_def, initial)
		if not store.store_id.is_empty():
			_stores[store.store_id] = store
