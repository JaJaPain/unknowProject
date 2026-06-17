extends SceneTree

const ConsumableFx = preload("res://scripts/economy/ConsumableEffects.gd")
const PlayerInv = preload("res://scripts/economy/PlayerInventory.gd")

var _failures: Array[String] = []
var _inv = PlayerInv.new()
var _shield_cap: float = 100.0


func _initialize() -> void:
	_test_repair_kit_heals()
	_test_repair_kit_caps_at_max()
	_test_repair_kit_fails_at_full_hp()
	_test_shield_cell_restores()
	_test_shield_cell_fails_at_full()
	_test_cannot_use_without_item()
	_test_use_deducts_from_inventory()
	_test_can_use_known_items()

	if _failures.is_empty():
		print("[PASS] Consumable effects tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _mock_player(hp: float = 100.0, max_hp: float = 100.0, shield: float = 50.0) -> Node3D:
	var s = GDScript.new()
	s.source_code = "extends Node3D\nvar health: float = %f\nvar max_health: float = %f\nvar current_shield: float = %f\n" % [hp, max_hp, shield]
	s.reload()
	var p = Node3D.new()
	p.set_script(s)
	return p


func _setup(items: Dictionary) -> void:
	_inv = PlayerInv.new()
	for item_id in items.keys():
		_inv.add(item_id, int(items[item_id]))


func _test_repair_kit_heals() -> void:
	_setup({"repair_kit": 1})
	var p = _mock_player(60.0, 100.0)
	var ok = ConsumableFx.use("repair_kit", p, _inv, _shield_cap)
	_expect(ok, "Repair kit use should succeed")
	_expect(is_equal_approx(p.health, 85.0), "Health should be 85, got %f" % p.health)
	p.free()


func _test_repair_kit_caps_at_max() -> void:
	_setup({"repair_kit": 1})
	var p = _mock_player(90.0, 100.0)
	ConsumableFx.use("repair_kit", p, _inv, _shield_cap)
	_expect(is_equal_approx(p.health, 100.0), "Health should cap at 100, got %f" % p.health)
	p.free()


func _test_repair_kit_fails_at_full_hp() -> void:
	_setup({"repair_kit": 1})
	var p = _mock_player(100.0, 100.0)
	var ok = ConsumableFx.use("repair_kit", p, _inv, _shield_cap)
	_expect(not ok, "Repair kit should fail at full HP")
	_expect(_inv.get_quantity("repair_kit") == 1, "Item should not be consumed on fail")
	p.free()


func _test_shield_cell_restores() -> void:
	_setup({"shield_cell": 1})
	var p = _mock_player(100.0, 100.0, 20.0)
	var ok = ConsumableFx.use("shield_cell", p, _inv, _shield_cap)
	_expect(ok, "Shield cell use should succeed")
	_expect(is_equal_approx(p.current_shield, 70.0), "Shield should be 70, got %f" % p.current_shield)
	p.free()


func _test_shield_cell_fails_at_full() -> void:
	_setup({"shield_cell": 1})
	var p = _mock_player(100.0, 100.0, 100.0)
	var ok = ConsumableFx.use("shield_cell", p, _inv, _shield_cap)
	_expect(not ok, "Shield cell should fail at full shield")
	p.free()


func _test_cannot_use_without_item() -> void:
	_setup({})
	var p = _mock_player(50.0, 100.0)
	var ok = ConsumableFx.use("repair_kit", p, _inv, _shield_cap)
	_expect(not ok, "Should fail without item in inventory")
	p.free()


func _test_use_deducts_from_inventory() -> void:
	_setup({"repair_kit": 2})
	var p = _mock_player(50.0, 100.0)
	ConsumableFx.use("repair_kit", p, _inv, _shield_cap)
	_expect(_inv.get_quantity("repair_kit") == 1, "Should have 1 left")
	p.health = 50.0
	ConsumableFx.use("repair_kit", p, _inv, _shield_cap)
	_expect(_inv.get_quantity("repair_kit") == 0, "Should have 0 left")
	p.health = 50.0
	var ok = ConsumableFx.use("repair_kit", p, _inv, _shield_cap)
	_expect(not ok, "Third use should fail")
	p.free()


func _test_can_use_known_items() -> void:
	_expect(ConsumableFx.can_use("repair_kit"), "repair_kit should be usable")
	_expect(ConsumableFx.can_use("shield_cell"), "shield_cell should be usable")
	_expect(ConsumableFx.can_use("scanner_probe"), "scanner_probe should be usable")
	_expect(ConsumableFx.can_use("fuel_booster"), "fuel_booster should be consumable")
	_expect(ConsumableFx.can_use("nanite_paste"), "nanite_paste should be consumable")
	_expect(ConsumableFx.can_use("capsuleer_booster"), "capsuleer_booster should be consumable")
	_expect(ConsumableFx.can_use("target_painter"), "target_painter should be consumable")
	_expect(ConsumableFx.can_use("flare_decoy"), "flare_decoy should be consumable")
	_expect(ConsumableFx.can_use("emp_charge"), "emp_charge should be consumable")
	_expect(not ConsumableFx.can_use("kinetic_ammo"), "kinetic_ammo not consumable")
	_expect(not ConsumableFx.can_use("nonexistent"), "nonexistent not usable")
