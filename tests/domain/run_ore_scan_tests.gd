extends SceneTree

## Scan Composition (Abe, playtest 2026-10-04): a pulse reads every ordinary
## rock in range, the overview names them by ore, red rocks stay unread.
##   Godot --headless --path . --script res://tests/domain/run_ore_scan_tests.gd --log-file <path>

const OreScan := preload("res://scripts/domain/OreScan.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var rocks: Array = []
	for spec in [["water_ice", 100.0, false], ["ferrite", 400.0, false], ["silicate", 900.0, false],
			["silicate", 1200.0, false], ["thorium", 300.0, true], ["water_ice", OreScan.RANGE + 50.0, false]]:
		var rock := Node3D.new()
		rock.set_script(_rock_script())
		rock.set("ore_type", spec[0])
		rock.set("tech_seam", spec[2])
		rock.add_to_group("asteroid")
		if spec[2]:
			rock.add_to_group("tech_seam_asteroid")
		root.add_child(rock)
		rock.global_position = Vector3(float(spec[1]), 0, 0)
		rocks.append(rock)

	_check(OreScan.name_for(rocks[0]) == "Asteroid", "an unscanned rock is just an asteroid: %s" % OreScan.name_for(rocks[0]))
	var result := OreScan.scan(Vector3.ZERO, rocks)
	_check(int(result["rocks"]) == 4, "four ordinary rocks in range: %s" % str(result))
	_check(int(result["seams"]) == 1, "the red rock is counted, not read")
	_check(int(result["new"]) == 4, "all four were new")
	_check(OreScan.name_for(rocks[0]) == "Water ice asteroid", "named by its ore: %s" % OreScan.name_for(rocks[0]))
	_check(OreScan.name_for(rocks[1]) == "Ferrite asteroid", "ferrite: %s" % OreScan.name_for(rocks[1]))
	_check(not OreScan.is_scanned(rocks[4]), "a red rock stays unread")
	_check(not OreScan.is_scanned(rocks[5]), "out of range stays unread")
	var line := OreScan.summary(result)
	_check(line.begins_with("Scan: 4 rocks") and line.contains("1 water ice") and line.contains("2 silicate")
		and line.contains("tech-grade seam"), "the feed sums it up: %s" % line)
	_check(line.find("water ice") < line.find("silicate"), "rarer ores first, silicate last: %s" % line)
	# Abe, playtest 2026-10-04 c: the ten or so rocks near the ship, not half
	# the belt. Fifteen around: only the nearest ten are read, and the bubble
	# reaches just past the tenth.
	var many: Array = []
	for i in 15:
		var r := Node3D.new()
		r.set_script(_rock_script())
		r.add_to_group("asteroid")
		root.add_child(r)
		r.global_position = Vector3(0, 0, 5000.0 + 60.0 * float(i + 1))
		many.append(r)
	var near := OreScan.scan(Vector3(0, 0, 5000), many)
	_check(int(near["rocks"]) == OreScan.COUNT, "the nearest ten are read: %s" % str(near["rocks"]))
	_check(OreScan.is_scanned(many[9]) and not OreScan.is_scanned(many[10]), "the eleventh is left alone")
	_check(absf(float(near["radius"]) - (600.0 + OreScan.RADIUS_MARGIN)) < 0.5, "the bubble reaches just past the tenth: %.0f" % float(near["radius"]))
	for r in many:
		r.free()
	_check(int(OreScan.scan(Vector3.ZERO, rocks)["new"]) == 0, "a rescan finds nothing new")
	_check(OreScan.summary(OreScan.scan(Vector3(90000, 0, 0), rocks)).contains("no rocks"), "an empty sky says so")
	_check(FileAccess.get_file_as_string("res://scripts/Asteroid.gd").contains("set_meta(\"ore_scanned\", true)"), "mining a rock reads it too")
	_check(FileAccess.get_file_as_string("res://scripts/UIManager.gd").contains("OreScanType.name_for(rock)"), "the overview uses the scan's names")

	for rock in rocks:
		rock.free()
	if _failures.is_empty():
		print("[PASS] Ore scan")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _rock_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar ore_type := \"silicate\"\nvar tech_seam := false\n"
	s.reload()
	return s


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
