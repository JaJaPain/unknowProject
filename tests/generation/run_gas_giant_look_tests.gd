extends SceneTree

## Playtest 2026-10-02: every gas giant looked like Jupiter. Each one now gets a
## look from its seed: a palette, bands, turbulence, maybe a storm.
##   Godot --headless --path . --script res://tests/generation/run_gas_giant_look_tests.gd --log-file <path>

const Look := preload("res://scripts/generation/GasGiantLook.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_check(Look.PALETTES.size() >= 8, "at least eight palettes")
	_check(Look.look_for(42) == Look.look_for(42), "the same seed, the same planet")
	var palettes := {}
	var three := 0
	for s in 200:
		var look: Dictionary = Look.look_for(s)
		palettes[str(look["palette"])] = true
		_check(float(look["band_count"]) >= 5.0 and float(look["band_count"]) <= 16.0, "band count in range")
		# A few churning storms, the first the biggest (Abe: "think Jupiter's storm").
		var sizes: Vector3 = look["storm_sizes"]
		var count := int(look["storm_count"])
		_check(count >= 2 and count <= 3 and sizes.x > sizes.y and (count == 3) == (sizes.z > 0.0), "two or three storms, the first the biggest: %s" % str(sizes))
		if count == 3:
			three += 1
	_check(palettes.size() == Look.PALETTES.size(), "every palette turns up (%d)" % palettes.size())
	_check(three > 40 and three < 160, "some have three storms (%d/200)" % three)
	var material: ShaderMaterial = Look.material_for(7)
	_check(material.shader == Look.SHADER and material.get_shader_parameter("band_count") == Look.look_for(7)["band_count"], "the material carries the look")
	if _failures.is_empty():
		print("[PASS] Gas giant looks")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
