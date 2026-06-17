extends SceneTree

const StoreItemDef = preload("res://scripts/economy/StoreItemDefinition.gd")
const StoreDef = preload("res://scripts/economy/StoreDefinition.gd")
const StoreReg = preload("res://scripts/economy/StoreRegistry.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_item_def_from_dict()
	_test_store_add_item_and_get_stock()
	_test_store_purchase_deducts_stock()
	_test_store_purchase_insufficient_stock()
	_test_store_purchase_zero_quantity()
	_test_price_tiers()
	_test_price_minimum_one()
	_test_restock_advances_stock()
	_test_restock_caps_at_max()
	_test_restock_does_not_fire_early()
	_test_depletion_penalty()
	_test_store_to_dict_from_dict_roundtrip()
	_test_registry_loads_data()
	_test_registry_stores_for_station()
	_test_registry_save_restore_stock()
	_test_registry_restock_all()

	if _failures.is_empty():
		print("[PASS] Store economy tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make_item(overrides: Dictionary = {}) -> StoreItemDef:
	var base = {
		"item_id": "test_item",
		"display_name": "Test Item",
		"description": "A test item.",
		"category": "consumable",
		"base_price": 100,
		"stack_max": 10,
		"restock_interval_minutes": 60,
		"restock_quantity": 2,
		"max_stock": 5,
	}
	base.merge(overrides, true)
	return StoreItemDef.from_dict(base)


func _make_store(items: Array = []) -> StoreDef:
	var store = StoreDef.new()
	store.store_id = "store.test"
	store.station_id = "test_station"
	for item in items:
		store.add_item(item)
	return store


func _test_item_def_from_dict() -> void:
	var item = _make_item({"item_id": "repair_kit", "base_price": 30})
	_expect(item.item_id == "repair_kit", "item_id mismatch")
	_expect(item.base_price == 30, "base_price mismatch")
	_expect(item.stack_max == 10, "stack_max mismatch")


func _test_store_add_item_and_get_stock() -> void:
	var item = _make_item()
	var store = _make_store([item])
	_expect(store.get_stock("test_item") == 5, "Initial stock should be max_stock")
	_expect(store.get_stock("nonexistent") == 0, "Nonexistent item should return 0")


func _test_store_purchase_deducts_stock() -> void:
	var item = _make_item()
	var store = _make_store([item])
	_expect(store.purchase("test_item", 2), "Purchase should succeed")
	_expect(store.get_stock("test_item") == 3, "Stock should be 3 after buying 2")


func _test_store_purchase_insufficient_stock() -> void:
	var item = _make_item()
	var store = _make_store([item])
	_expect(not store.purchase("test_item", 10), "Purchase exceeding stock should fail")
	_expect(store.get_stock("test_item") == 5, "Stock should be unchanged after failed purchase")


func _test_store_purchase_zero_quantity() -> void:
	var item = _make_item()
	var store = _make_store([item])
	_expect(not store.purchase("test_item", 0), "Zero quantity purchase should fail")
	_expect(not store.purchase("test_item", -1), "Negative quantity purchase should fail")


func _test_price_tiers() -> void:
	var item = _make_item({"base_price": 100})
	var store = _make_store([item])
	var allied = store.get_price("test_item", "allied")
	var neutral = store.get_price("test_item", "neutral")
	var hostile = store.get_price("test_item", "hostile")
	_expect(allied == 80, "Allied price should be 80, got %d" % allied)
	_expect(neutral == 100, "Neutral price should be 100, got %d" % neutral)
	_expect(hostile == 150, "Hostile price should be 150, got %d" % hostile)
	_expect(allied < neutral and neutral < hostile, "Prices should increase with hostility")


func _test_price_minimum_one() -> void:
	var item = _make_item({"base_price": 1})
	var store = _make_store([item])
	var price = store.get_price("test_item", "allied")
	_expect(price >= 1, "Price should never be less than 1, got %d" % price)


func _test_restock_advances_stock() -> void:
	var item = _make_item({"restock_interval_minutes": 60, "restock_quantity": 2, "max_stock": 5})
	var store = _make_store([item])
	store.purchase("test_item", 3)
	_expect(store.get_stock("test_item") == 2, "Stock should be 2 after buying 3")
	store.restock_check(0)
	var restock_time = 60
	store.restock_check(restock_time)
	_expect(store.get_stock("test_item") == 4, "Stock should be 4 after restock (+2)")


func _test_restock_caps_at_max() -> void:
	var item = _make_item({"restock_interval_minutes": 60, "restock_quantity": 5, "max_stock": 5})
	var store = _make_store([item])
	store.purchase("test_item", 1)
	store.restock_check(0)
	store.restock_check(60)
	_expect(store.get_stock("test_item") == 5, "Stock should cap at max_stock 5, got %d" % store.get_stock("test_item"))


func _test_restock_does_not_fire_early() -> void:
	var item = _make_item({"restock_interval_minutes": 120, "restock_quantity": 1})
	var store = _make_store([item])
	store.purchase("test_item", 2)
	store.restock_check(0)
	store.restock_check(60)
	_expect(store.get_stock("test_item") == 3, "Stock should not restock before interval, got %d" % store.get_stock("test_item"))


func _test_depletion_penalty() -> void:
	var item = _make_item({"restock_interval_minutes": 60, "restock_quantity": 1, "max_stock": 2})
	var store = _make_store([item])
	store.restock_check(0)
	store.purchase("test_item", 2)
	_expect(store.get_stock("test_item") == 0, "Stock should be 0")
	store.restock_check(60)
	_expect(store.get_stock("test_item") == 0, "Should still be 0 during depletion penalty")
	store.restock_check(180)
	_expect(store.get_stock("test_item") >= 1, "Should restock after depletion penalty window")


func _test_store_to_dict_from_dict_roundtrip() -> void:
	var item = _make_item()
	var store = _make_store([item])
	store.purchase("test_item", 2)
	store.restock_check(100)
	var d = store.to_dict()
	var catalog = {item.item_id: item}
	var restored = StoreDef.from_dict(d, catalog)
	_expect(restored.store_id == store.store_id, "store_id mismatch after roundtrip")
	_expect(restored.get_stock("test_item") == store.get_stock("test_item"),
		"Stock mismatch after roundtrip: %d vs %d" % [restored.get_stock("test_item"), store.get_stock("test_item")])


func _make_registry():
	var reg = StoreReg.new()
	reg._load_data()
	return reg


func _test_registry_loads_data() -> void:
	var reg = _make_registry()
	var repair = reg.get_item("repair_kit")
	_expect(repair != null, "Registry should have repair_kit item")
	if repair:
		_expect(repair.display_name == "Repair Kit", "repair_kit display_name wrong")
		_expect(repair.base_price == 30, "repair_kit base_price wrong: %d" % repair.base_price)
	var haven = reg.get_store("store.haven.general")
	_expect(haven != null, "Registry should have haven store")
	if haven:
		_expect(haven.get_stock("repair_kit") > 0, "Haven should stock repair_kit")
		_expect(haven.get_stock("emp_charge") > 0, "Haven should stock emp_charge")


func _test_registry_stores_for_station() -> void:
	var reg = _make_registry()
	var haven_stores = reg.get_stores_for_station("haven")
	_expect(haven_stores.size() == 1, "Haven should have 1 store, got %d" % haven_stores.size())
	var iron_stores = reg.get_stores_for_station("iron_reach")
	_expect(iron_stores.size() == 1, "Iron Reach should have 1 store")
	var none = reg.get_stores_for_station("nonexistent")
	_expect(none.is_empty(), "Nonexistent station should return empty")


func _test_registry_save_restore_stock() -> void:
	var reg = _make_registry()
	var haven = reg.get_store("store.haven.general")
	if haven == null:
		_expect(false, "Haven store missing for save/restore test")
		return
	haven.purchase("repair_kit", 1)
	var before = haven.get_stock("repair_kit")
	var saved = reg.save_stock_state()
	haven.purchase("repair_kit", 1)
	_expect(haven.get_stock("repair_kit") == before - 1, "Stock should decrease by 1")
	reg.restore_stock_state(saved)
	var after = reg.get_store("store.haven.general").get_stock("repair_kit")
	_expect(after == before, "Stock should restore to saved state: %d vs %d" % [after, before])


func _test_registry_restock_all() -> void:
	var reg = _make_registry()
	var haven = reg.get_store("store.haven.general")
	if haven == null:
		_expect(false, "Haven store missing for restock test")
		return
	haven.purchase("repair_kit", haven.get_stock("repair_kit"))
	_expect(haven.get_stock("repair_kit") == 0, "Should deplete repair_kit stock")
	reg.restock_all(0)
	reg.restock_all(500)
	_expect(haven.get_stock("repair_kit") > 0, "Should restock after enough time")
