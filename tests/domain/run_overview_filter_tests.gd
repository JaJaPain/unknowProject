extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect overview filter controls.")
	if file != null:
		var source := file.get_as_text()
		_expect(
			source.contains("func _on_overview_mission_targets_pressed()")
				and source.contains("func _on_overview_ships_pressed()")
				and source.contains("func _on_overview_asteroids_pressed()")
				and source.contains("Mission hostiles first"),
			"The overview header does not expose all three requested quick controls."
		)
		_expect(
			source.contains("func _should_show_overview_entity")
				and source.contains("_overview_show_ships")
				and source.contains("_overview_show_asteroids"),
			"Ship and asteroid controls do not filter their overview rows."
		)
		_expect(
			source.contains("func _is_overview_mission_target")
				and source.contains("btn.set_meta(\"is_mission_target\"")
				and source.contains("if _overview_prioritize_mission_targets:"),
			"Mission-hostile control does not move active hunt targets to the top."
		)
	if _failures.is_empty():
		print("[PASS] Overview filter tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
