extends SceneTree

const Profile := preload("res://scripts/story/premise/SystemProfile.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_deterministic()
	_test_first_system_is_clean()
	_test_distribution_and_star_bias()
	_test_apply_changes()
	if _failures.is_empty():
		print("[PASS] System profile tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_deterministic() -> void:
	var a := Profile.generate("system.gen_7", 12345, "red")
	var b := Profile.generate("system.gen_7", 12345, "red")
	_check(a == b, "same inputs must give the same profile")


func _test_first_system_is_clean() -> void:
	var p := Profile.generate("system.start", 99, "red", true)
	_check((p["quirks"] as Array).is_empty() and (p["states"] as Array).is_empty(), "the tutorial system must stay plain")


func _test_distribution_and_star_bias() -> void:
	var seen := {}
	var dying_red := 0
	var dying_blue := 0
	var with_quirks := 0
	var max_quirks := 0
	for i in 1500:
		for star in ["red", "blue"]:
			var p := Profile.generate("system.gen_%d" % i, 777, star)
			var quirks: Array = p["quirks"]
			max_quirks = maxi(max_quirks, quirks.size())
			if not quirks.is_empty():
				with_quirks += 1
			for q in quirks:
				seen[q] = true
				_check(q in Profile.QUIRKS, "unknown quirk %s" % q)
			for s in p["states"]:
				_check(s in Profile.STATES, "unknown state %s" % s)
			if "dying_star" in quirks:
				if star == "red":
					dying_red += 1
				else:
					dying_blue += 1
	_check(seen.size() == Profile.QUIRKS.size(), "every quirk should appear somewhere: %s" % str(seen.keys()))
	_check(max_quirks <= 2, "no system should have more than 2 quirks")
	var share := float(with_quirks) / 3000.0
	_check(share > 0.5 and share < 0.7, "about 60%% of systems should have a quirk, got %.2f" % share)
	_check(dying_red > dying_blue * 2, "red stars should be dying far more often than blue (%d vs %d)" % [dying_red, dying_blue])


func _test_apply_changes() -> void:
	var p := {"system_id": "s", "quirks": [], "states": ["festival"]}
	var q := Profile.apply_changes(p, ["strike", "strike", "not_a_state"], ["festival"])
	_check(q["states"] == ["strike"], "apply_changes should add known states once and remove listed ones: %s" % str(q["states"]))
	_check(p["states"] == ["festival"], "apply_changes must not modify its input")
