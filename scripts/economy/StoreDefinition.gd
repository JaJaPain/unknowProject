extends RefCounted

const StoreItemDef := preload("res://scripts/economy/StoreItemDefinition.gd")

var store_id: String = ""
var station_id: String = ""
var _catalog: Dictionary = {}
var _stock: Dictionary = {}
var _demand: Dictionary = {}

const PRICE_MULTIPLIERS := {
	"allied": 0.80,
	"trusted": 0.85,
	"friendly": 0.90,
	"cordial": 0.95,
	"neutral": 1.00,
	"wary": 1.10,
	"unfriendly": 1.25,
	"hostile": 1.50,
	"sworn enemy": 2.00,
}

const DEPLETION_PENALTY_MULTIPLIER := 2
const DEFAULT_DEMAND_MAX := 5
const DEMAND_RESTOCK_INTERVAL_MINUTES := 240


func add_item(item_def: StoreItemDef, initial_stock: int = -1) -> void:
	_catalog[item_def.item_id] = item_def
	if not _stock.has(item_def.item_id):
		var qty: int = initial_stock if initial_stock >= 0 else item_def.max_stock
		_stock[item_def.item_id] = {
			"quantity": mini(qty, item_def.max_stock),
			"restock_at": 0,
		}
	if not _demand.has(item_def.item_id):
		_demand[item_def.item_id] = {
			"quantity": _default_demand_for(item_def),
			"max": _default_demand_for(item_def),
			"restock_at": 0,
		}


func get_item_def(item_id: String) -> StoreItemDef:
	return _catalog.get(item_id)


func get_catalog_ids() -> Array:
	return _catalog.keys()


func get_price(item_id: String, reputation_tier: String) -> int:
	var item_def: StoreItemDef = _catalog.get(item_id)
	if item_def == null:
		return 0
	var mult: float = PRICE_MULTIPLIERS.get(reputation_tier, 1.0)
	return maxi(1, int(round(float(item_def.base_price) * mult)))


func get_sell_price(
	item_id: String,
	reputation_tier: String,
	origin_system_id: String,
	current_system_id: String
) -> int:
	var item_def: StoreItemDef = _catalog.get(item_id)
	if item_def == null:
		return 0
	var buy_price := get_price(item_id, reputation_tier)
	var category := item_def.category
	var same_system := origin_system_id == current_system_id \
		or origin_system_id == station_id \
		or origin_system_id == "unknown"
	if category == "consumable":
		return maxi(1, int(floor(float(buy_price) * 0.45)))
	if same_system:
		return maxi(1, int(floor(float(buy_price) * 0.55)))
	var demand_entry: Dictionary = _demand.get(item_id, {})
	var demand_qty := int(demand_entry.get("quantity", 0))
	var demand_max := maxi(1, int(demand_entry.get("max", DEFAULT_DEMAND_MAX)))
	if demand_qty <= 0:
		return maxi(1, int(floor(float(buy_price) * 0.50)))
	var demand_ratio := float(demand_qty) / float(demand_max)
	var multiplier := 0.65 + demand_ratio * 0.60
	var rep_mult: float = PRICE_MULTIPLIERS.get(reputation_tier, 1.0)
	return maxi(1, int(round(float(item_def.base_price) * multiplier * rep_mult)))


func get_demand(item_id: String) -> int:
	var entry: Dictionary = _demand.get(item_id, {})
	return int(entry.get("quantity", 0))


func get_stock(item_id: String) -> int:
	var entry: Dictionary = _stock.get(item_id, {})
	return int(entry.get("quantity", 0))


func purchase(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false
	var entry: Dictionary = _stock.get(item_id, {})
	var current: int = int(entry.get("quantity", 0))
	if current < quantity:
		return false
	var item_def: StoreItemDef = _catalog.get(item_id)
	entry["quantity"] = current - quantity
	if entry["quantity"] == 0 and item_def:
		entry["restock_at"] = int(entry.get("restock_at", 0)) + \
			item_def.restock_interval_minutes * DEPLETION_PENALTY_MULTIPLIER
	return true


func buy_from_player(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0 or not _catalog.has(item_id):
		return false
	var item_def: StoreItemDef = _catalog[item_id]
	var stock_entry: Dictionary = _stock.get(item_id, {})
	var current_stock := int(stock_entry.get("quantity", 0))
	stock_entry["quantity"] = mini(current_stock + quantity, item_def.max_stock)
	_stock[item_id] = stock_entry
	var demand_entry: Dictionary = _demand.get(item_id, {})
	var demand_qty := int(demand_entry.get("quantity", 0))
	demand_entry["quantity"] = maxi(0, demand_qty - quantity)
	if int(demand_entry.get("restock_at", 0)) <= 0:
		demand_entry["restock_at"] = 0
	_demand[item_id] = demand_entry
	return true


func force_restock() -> void:
	for item_id in _catalog.keys():
		var item_def: StoreItemDef = _catalog[item_id]
		if _stock.has(item_id):
			_stock[item_id]["quantity"] = item_def.max_stock
			_stock[item_id]["restock_at"] = 0
			if _demand.has(item_id):
				_demand[item_id]["quantity"] = int(_demand[item_id].get("max", DEFAULT_DEMAND_MAX))
				_demand[item_id]["restock_at"] = 0

func restock_check(current_time_minutes: int) -> void:
	for item_id in _catalog.keys():
		var item_def: StoreItemDef = _catalog[item_id]
		var entry: Dictionary = _stock.get(item_id, {})
		if entry.is_empty():
			continue
		var restock_at: int = int(entry.get("restock_at", 0))
		if restock_at <= 0:
			entry["restock_at"] = current_time_minutes + item_def.restock_interval_minutes
		else:
			while current_time_minutes >= restock_at:
				var qty: int = int(entry.get("quantity", 0))
				entry["quantity"] = mini(qty + item_def.restock_quantity, item_def.max_stock)
				restock_at += item_def.restock_interval_minutes
			entry["restock_at"] = restock_at
		var demand_entry: Dictionary = _demand.get(item_id, {})
		if demand_entry.is_empty():
			continue
		var demand_at: int = int(demand_entry.get("restock_at", 0))
		if demand_at <= 0:
			demand_entry["restock_at"] = current_time_minutes + DEMAND_RESTOCK_INTERVAL_MINUTES
			continue
		while current_time_minutes >= demand_at:
			var demand_qty: int = int(demand_entry.get("quantity", 0))
			var demand_max: int = int(demand_entry.get("max", DEFAULT_DEMAND_MAX))
			demand_entry["quantity"] = mini(demand_qty + 1, demand_max)
			demand_at += DEMAND_RESTOCK_INTERVAL_MINUTES
		demand_entry["restock_at"] = demand_at


func to_dict() -> Dictionary:
	var stock_out := {}
	for item_id in _stock.keys():
		var entry: Dictionary = _stock[item_id]
		stock_out[item_id] = {
			"quantity": int(entry.get("quantity", 0)),
			"restock_at": int(entry.get("restock_at", 0)),
		}
	return {
		"store_id": store_id,
		"station_id": station_id,
		"stock": stock_out,
		"demand": _demand.duplicate(true),
	}


static func from_dict(data: Dictionary, catalog: Dictionary):
	var store = new()
	store.store_id = str(data.get("store_id", ""))
	store.station_id = str(data.get("station_id", ""))
	store._catalog = catalog
	var saved_stock: Dictionary = data.get("stock", {})
	for item_id in catalog.keys():
		var item_def: StoreItemDef = catalog[item_id]
		if saved_stock.has(item_id):
			store._stock[item_id] = {
				"quantity": int(saved_stock[item_id].get("quantity", 0)),
				"restock_at": int(saved_stock[item_id].get("restock_at", 0)),
			}
		else:
			store._stock[item_id] = {
				"quantity": item_def.max_stock,
				"restock_at": 0,
			}
		var saved_demand: Dictionary = data.get("demand", {})
		if saved_demand.has(item_id):
			store._demand[item_id] = saved_demand[item_id].duplicate(true)
		else:
			store._demand[item_id] = {
				"quantity": store._default_demand_for(item_def),
				"max": store._default_demand_for(item_def),
				"restock_at": 0,
			}
	return store


func _default_demand_for(item_def: StoreItemDef) -> int:
	match item_def.category:
		"trade_good", "ship_part", "ammo", "novelty":
			return DEFAULT_DEMAND_MAX
		_:
			return 0
