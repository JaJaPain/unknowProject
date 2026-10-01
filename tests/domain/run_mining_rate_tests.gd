extends SceneTree

## Mining earns a steady value per second (Abe, 2026-10-02): 1.0 SC/s stock,
## 1.2 / 1.4 / 1.6 / 1.8 by Mk V on both laser branches; rarer ore cuts slower
## in proportion to its price; a laser can favour an ore. Also guards the
## upgrade stat names that were silently dropped (cargo never grew, Deep never
## raised its yield).
##   Godot --headless --path . --script res://tests/domain/run_mining_rate_tests.gd --log-file <path>

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GlobalState")
	var saved: Dictionary = gs.current_upgrades.duplicate(true)
	var targets := {1: 1.0, 2: 1.2, 3: 1.4, 4: 1.6, 5: 1.8}
	for path in ["rapid", "deep"]:
		for tier in targets:
			gs.current_upgrades["mining"] = {"tier": tier, "path": path if tier > 1 else "base"}
			gs.apply_upgrade_stats()
			var rate: float = gs.mining_yield / gs.mining_cooldown
			_check(absf(rate - float(targets[tier])) < 0.01, "%s Mk %d earns %.2f SC/s (got %.2f)" % [path, tier, targets[tier], rate])
	# Cargo upgrades grow the hold (they used to set a variable that didn't exist).
	gs.current_upgrades["cargo"] = {"tier": 2, "path": "standard"}
	gs.apply_upgrade_stats()
	_check(is_equal_approx(gs.cargo_max, 150.0), "Cargo Mk II grows the hold to 150 (got %.0f)" % gs.cargo_max)
	gs.current_upgrades = saved
	gs.apply_upgrade_stats()
	_check(is_equal_approx(gs.cargo_max, 100.0) and gs.mining_ore_affinity.is_empty(), "back to stock: hold 100, no ore bonus")
	# Rarer ore cuts slower, same credits per second.
	var Ores = load("res://scripts/economy/OreTypes.gd")
	var asteroid_script = load("res://scripts/Asteroid.gd")
	var saved_affinity: Dictionary = gs.mining_ore_affinity
	for ore in ["silicate", "thorium"]:
		gs.clear_cargo()
		var rock: Node = asteroid_script.new()
		rock.set("ore_type", ore)
		rock.set("resources", 50.0)
		rock.mine()
		var got: float = gs.cargo
		_check(absf(got * Ores.price(ore) - gs.mining_yield) < 0.01, "%s: one cut is worth one cut's credits (%.2f m³)" % [ore, got])
		rock.free()
	gs.mining_ore_affinity = {"thorium": 1.5}
	gs.clear_cargo()
	var favoured: Node = asteroid_script.new()
	favoured.set("ore_type", "thorium")
	favoured.set("resources", 50.0)
	favoured.mine()
	_check(absf(gs.cargo - 1.5 * gs.mining_yield / Ores.price("thorium")) < 0.01, "a thorium-favouring laser cuts thorium 1.5x faster")
	favoured.free()
	gs.mining_ore_affinity = saved_affinity
	gs.clear_cargo()
	# Ore this system doesn't have sells for more (Abe, 2026-10-02).
	var no_thorium := {"silicate": 0.8, "ferrite": 0.2}
	var has_thorium := {"silicate": 0.8, "thorium": 0.2}
	_check(Ores.value({"thorium": 10.0}, 1.0, no_thorium) == int(round(10.0 * Ores.price("thorium") * Ores.IMPORT_PREMIUM)), "thorium sells x1.5 where none is mined")
	_check(Ores.value({"thorium": 10.0}, 1.0, has_thorium) == int(round(10.0 * Ores.price("thorium"))), "and at its normal price where it is")
	_check(Ores.value({"silicate": 10.0}, 1.0, no_thorium) == 10, "silicate never earns the premium")
	_check(Ores.value({"thorium": 10.0}, 1.0, {}) == int(round(10.0 * Ores.price("thorium"))), "no premium when the system's belts are unknown")
	if _failures.is_empty():
		print("[PASS] Mining rates")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
