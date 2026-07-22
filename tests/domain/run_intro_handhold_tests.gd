extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_test_dock_command_hides_intro_arrow_until_docking()
	_test_kaelen_intro_wording()
	_test_kaelen_briefing_scrolls_at_speech_midpoint()
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


func _test_kaelen_briefing_scrolls_at_speech_midpoint() -> void:
	var ui_file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	var speech_file := FileAccess.open("res://scripts/speech/SpeechService.gd", FileAccess.READ)
	_expect(
		ui_file != null and speech_file != null,
		"Could not inspect Kaelen briefing auto-scroll wiring."
	)
	if ui_file == null or speech_file == null:
		return
	var ui_source := ui_file.get_as_text()
	var speech_source := speech_file.get_as_text()
	_expect(
		ui_source.contains("func _scroll_kaelen_briefing_to_bottom")
			and ui_source.contains("line_index == ceili(float(total_lines) / 2.0)")
			and ui_source.contains("_kaelen_briefing_auto_scroll_done")
			and ui_source.contains("scroll_vertical")
			and speech_source.contains("line_started: Callable = Callable()")
			and speech_source.contains("_sequential_line_started.call(line_index, _sequential_total_lines)"),
		"Kaelen briefing no longer performs one midpoint auto-scroll before returning control to the player."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
