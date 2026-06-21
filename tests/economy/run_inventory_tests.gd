extends SceneTree

const PlayerInv = preload("res://scripts/economy/PlayerInventory.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_add_and_get()
	_test_add_invalid()
	_test_remove_basic()
	_test_remove_insufficient()
	_test_remove_clears_entry()
	_test_has_item()
	_test_get_all_returns_copy()
	_test_clear()
	_test_save_load_roundtrip()
	_test_signal_emitted()
	_test_slot_limit()
	_test_stack_max()
	_test_save_load_max_slots()

	if _failures.is_empty():
		print("[PASS] Player inventory tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_add_and_get() -> void:
	var inv = PlayerInv.new()
	_expect(inv.add("repair_kit", 3), "add should succeed")
	_expect(inv.get_quantity("repair_kit") == 3, "Should have 3 repair kits")
	_expect(inv.add("repair_kit", 2), "add more should succeed")
	_expect(inv.get_quantity("repair_kit") == 5, "Should have 5 repair kits")


func _test_add_invalid() -> void:
	var inv = PlayerInv.new()
	_expect(not inv.add("", 1), "Empty item_id should fail")
	_expect(not inv.add("repair_kit", 0), "Zero quantity should fail")
	_expect(not inv.add("repair_kit", -1), "Negative quantity should fail")


func _test_remove_basic() -> void:
	var inv = PlayerInv.new()
	inv.add("shield_cell", 5)
	_expect(inv.remove("shield_cell", 2), "Remove should succeed")
	_expect(inv.get_quantity("shield_cell") == 3, "Should have 3 left")


func _test_remove_insufficient() -> void:
	var inv = PlayerInv.new()
	inv.add("shield_cell", 2)
	_expect(not inv.remove("shield_cell", 5), "Remove more than owned should fail")
	_expect(inv.get_quantity("shield_cell") == 2, "Quantity unchanged after failed remove")
	_expect(not inv.remove("nonexistent", 1), "Remove nonexistent should fail")


func _test_remove_clears_entry() -> void:
	var inv = PlayerInv.new()
	inv.add("flare_decoy", 1)
	inv.remove("flare_decoy", 1)
	_expect(inv.get_quantity("flare_decoy") == 0, "Should be 0 after removing all")
	var all = inv.get_all()
	_expect(not all.has("flare_decoy"), "Entry should be erased when quantity hits 0")


func _test_has_item() -> void:
	var inv = PlayerInv.new()
	inv.add("scanner_probe", 3)
	_expect(inv.has_item("scanner_probe"), "has_item with default min=1 should be true")
	_expect(inv.has_item("scanner_probe", 3), "has_item with exact qty should be true")
	_expect(not inv.has_item("scanner_probe", 4), "has_item exceeding qty should be false")
	_expect(not inv.has_item("nonexistent"), "has_item for missing item should be false")


func _test_get_all_returns_copy() -> void:
	var inv = PlayerInv.new()
	inv.add("repair_kit", 2)
	var snapshot = inv.get_all()
	snapshot["repair_kit"] = 999
	_expect(inv.get_quantity("repair_kit") == 2, "Modifying snapshot should not affect inventory")


func _test_clear() -> void:
	var inv = PlayerInv.new()
	inv.add("repair_kit", 5)
	inv.add("shield_cell", 3)
	inv.clear()
	_expect(inv.get_quantity("repair_kit") == 0, "Should be empty after clear")
	_expect(inv.get_all().is_empty(), "get_all should be empty after clear")


func _test_save_load_roundtrip() -> void:
	var inv = PlayerInv.new()
	inv.add("repair_kit", 3)
	inv.add("emp_charge", 1)
	var data = inv.to_dict()
	var restored = PlayerInv.from_dict(data)
	_expect(restored.get_quantity("repair_kit") == 3, "repair_kit should roundtrip")
	_expect(restored.get_quantity("emp_charge") == 1, "emp_charge should roundtrip")
	_expect(restored.get_quantity("shield_cell") == 0, "absent item should be 0")


func _test_signal_emitted() -> void:
	var inv = PlayerInv.new()
	var captured = ["",-1]
	inv.item_changed.connect(func(id: String, qty: int):
		captured[0] = id
		captured[1] = qty
	)
	inv.add("repair_kit", 2)
	_expect(captured[0] == "repair_kit", "Signal should fire with correct item_id")
	_expect(captured[1] == 2, "Signal should fire with new quantity 2")
	inv.remove("repair_kit", 1)
	_expect(captured[1] == 1, "Signal should fire with new quantity 1 after remove")


func _test_slot_limit() -> void:
	var inv = PlayerInv.new()
	inv.max_slots = 3
	inv.add("item_a")
	inv.add("item_b")
	inv.add("item_c")
	_expect(not inv.add("item_d"), "4th distinct item should fail with 3 slots")
	_expect(inv.get_quantity("item_d") == 0, "item_d should not exist")
	_expect(inv.add("item_a", 2), "Stacking existing item should succeed even when full")
	_expect(inv.get_quantity("item_a") == 3, "item_a should have 3 after stacking")
	_expect(inv.is_full(), "Should report full at 3/3")
	inv.remove("item_c", 1)
	_expect(not inv.is_full(), "Should not be full after removing a slot")
	_expect(inv.add("item_d"), "Should accept new item after freeing a slot")


func _test_stack_max() -> void:
	var inv = PlayerInv.new()
	_expect(inv.add("repair_kit", 3, 5), "Add 3 with stack_max 5 should succeed")
	_expect(inv.add("repair_kit", 2, 5), "Add 2 more (total 5) should succeed")
	_expect(not inv.add("repair_kit", 1, 5), "Add 1 more (would be 6) should fail")
	_expect(inv.get_quantity("repair_kit") == 5, "Should stay at 5")
	_expect(inv.can_add("repair_kit", 1, 5) == false, "can_add should return false at stack_max")
	_expect(inv.add("shield_cell", 1, -1), "stack_max -1 means unlimited")


func _test_save_load_max_slots() -> void:
	var inv = PlayerInv.new()
	inv.max_slots = 12
	inv.add("repair_kit", 2)
	var data = inv.to_dict()
	var restored = PlayerInv.from_dict(data)
	_expect(restored.max_slots == 12, "max_slots should survive save/load roundtrip")
	_expect(restored.get_quantity("repair_kit") == 2, "items should survive roundtrip")
