extends SceneTree

## Gate classes and Ship Rating (scripts/domain/GateClass.gd; plan
## docs/core_loop_plan_2026_10_01.md Section 2).
##   Godot --headless --path . --script res://tests/domain/run_gate_class_tests.gd --log-file <path>

const GateClass := preload("res://scripts/domain/GateClass.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	# Classes by destination depth, including past the hand-tuned table.
	var classes := {-1: 1, 0: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 3, 7: 4, 9: 4, 10: 5, 12: 5, 13: 6, 15: 6, 16: 7, 18: 7, 19: 8, 40: 15}
	for depth in classes:
		_check(GateClass.class_for_depth(depth) == classes[depth],
			"depth %d is class %d (got %d)" % [depth, classes[depth], GateClass.class_for_depth(depth)])
	var ratings := {1: 5, 2: 6, 3: 8, 4: 11, 5: 15, 6: 20, 7: 25, 8: 30}
	for c in ratings:
		_check(GateClass.rating_for_class(c) == ratings[c], "class %d needs rating %d" % [c, ratings[c]])

	# Ship Rating with the breadth rule.
	var stock := _tiers(1, 1, 1, 1, 1)
	_check(GateClass.ship_rating(stock) == 5, "a stock ship rates 5")
	var tall := _tiers(1, 1, 5, 1, 1)
	_check(GateClass.ship_rating(tall) == 7, "Shields Mk V alone counts only to Mk III: 7")
	_check(GateClass.limiting_system(tall) == "weapons", "and the weakest system is named")
	var lifted := _tiers(1, 1, 5, 1, 2)
	_check(GateClass.ship_rating(lifted) == 8, "cargo Mk II doesn't lift the cap while weapons is Mk I: 8")
	var even := _tiers(3, 3, 3, 3, 3)
	_check(GateClass.ship_rating(even) == 15, "an even Mk III ship rates 15")
	_check(GateClass.limiting_system(even) == "", "nothing limits an even ship")
	# One path alone never carries the ship forward (Abe).
	var one_path := _tiers(20, 1, 1, 1, 1)
	_check(not bool(GateClass.check(4, 5, one_path)["ok"]), "maxing one system can't pass Class III")
	_check(GateClass.ship_rating(_tiers(30, 30, 30, 30, 30)) == 150, "no top tier: ratings keep counting")

	# Gate checks.
	_check(bool(GateClass.check(0, 2, stock)["ok"]), "Class I is free")
	var c2: Dictionary = GateClass.check(2, 3, stock)
	_check(not bool(c2["ok"]) and bool(c2["needs_shields_mk2"]), "Class II wants Shields Mk II")
	_check(not bool(GateClass.check(2, 3, _tiers(2, 1, 1, 1, 1))["ok"]), "weapons Mk II isn't hardened shields")
	_check(bool(GateClass.check(2, 3, _tiers(1, 1, 2, 1, 1))["ok"]), "Shields Mk II opens Class II")
	var c3: Dictionary = GateClass.check(4, 5, _tiers(1, 1, 2, 1, 1))
	_check(not bool(c3["ok"]) and int(c3["needs_rating"]) == 8 and int(c3["rating"]) == 6, "Class III wants rating 8")
	_check(bool(GateClass.check(4, 5, _tiers(2, 1, 2, 2, 1))["ok"]), "rating 8 opens Class III")
	# Back is always open; deeper always checks, even somewhere visited.
	_check(bool(GateClass.check(9, 3, stock)["ok"]), "going back is always open, even stock")
	_check(bool(GateClass.check(5, 5, stock)["ok"]), "sideways at the same depth is open")
	_check(not bool(GateClass.check(3, 5, _tiers(1, 1, 2, 1, 1))["ok"]), "going deeper checks every time")

	if _failures.is_empty():
		print("[PASS] Gate class and Ship Rating")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _tiers(weapons: int, engine: int, shields: int, mining: int, cargo: int) -> Dictionary:
	return {"weapons": weapons, "engine": engine, "shields": shields, "mining": mining, "cargo": cargo}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
