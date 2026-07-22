extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_test_dock_command_hides_intro_arrow_until_docking()
	_test_kaelen_intro_wording()
	if _failures.is_empty():
		print("[PASS] Intro handhold tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_dock_command_hides_intro_arrow_until_docking() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect tutorial handhold wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("var _intro_dock_command_issued: bool = false")
			and source.contains("if mode == \"DOCK\" and target == _intro_primary_station():")
			and source.contains("_intro_dock_command_issued = true")
			and source.contains("not _intro_dock_command_issued")
			and source.contains("_clear_intro_handhold_arrow()"),
		"Dock command does not latch the starter tutorial arrow off during approach."
	)


func _test_kaelen_intro_wording() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("something handled right now. You interested?"),
		"Kaelen's briefing does not use the requested 'You interested?' wording."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
