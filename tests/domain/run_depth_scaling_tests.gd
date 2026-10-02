extends SceneTree

## Deeper is richer, and harder (core loop step 6): red rocks, board pay and
## enemy strength grow with depth.
##   Godot --headless --path . --script res://tests/domain/run_depth_scaling_tests.gd --log-file <path>

const Scaling := preload("res://scripts/domain/DepthScaling.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	# Loaded once the autoloads exist: Asteroid.gd uses GlobalState.
	await process_frame
	var AsteroidScript = load("res://scripts/Asteroid.gd")
	if AsteroidScript == null or not AsteroidScript.can_instantiate():
		push_error("[FAIL] Asteroid.gd did not load")
		quit(1)
		return
	# Red rocks: ~1% near the start, 3% deep, never past 3%.
	_check(Scaling.tech_seam_permille(0) == 10 and Scaling.tech_seam_permille(2) == 10, "about 1% out to depth 2")
	_check(Scaling.tech_seam_permille(5) > 10 and Scaling.tech_seam_permille(5) < 30, "more by depth 5 (%d)" % Scaling.tech_seam_permille(5))
	_check(Scaling.tech_seam_permille(10) == 30 and Scaling.tech_seam_permille(40) == 30, "3% from depth 10, capped")
	# The share actually changes which rocks are red.
	var saved: int = AsteroidScript.tech_seam_permille
	for permille in [10, 30]:
		AsteroidScript.tech_seam_permille = permille
		var red := 0
		for i in 20000:
			if AsteroidScript.is_tech_seam_id("rock.%d" % i):
				red += 1
		var share := float(red) / 20000.0 * 1000.0
		_check(absf(share - permille) < permille * 0.25, "%d per thousand gives about that many red rocks (%.1f)" % [permille, share])
	AsteroidScript.tech_seam_permille = saved
	# Pay and threat.
	_check(is_equal_approx(Scaling.pay_factor(0), 2.0) and is_equal_approx(Scaling.pay_factor(10), 5.0), "pay x2 at the start, x5 at depth 10")
	_check(is_equal_approx(Scaling.threat_factor(0), 1.0) and is_equal_approx(Scaling.threat_factor(10), 1.8), "threat x1 at the start, x1.8 at depth 10")
	_check(Scaling.pay_factor(-1) == 2.0 and Scaling.threat_factor(-1) == 1.0, "unknown depth counts as the start")
	if _failures.is_empty():
		print("[PASS] Depth scaling")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
