extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_test_dock_command_hides_intro_arrow_until_docking()
	_test_station_welcome_holds_dock_interaction()
	_test_broken_gate_storm_mix_contract()
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
	var docking_start := source.find("func begin_docking_procedure")
	var docking_end := source.find("func _play_dock_clearance", docking_start)
	var docking_source := source.substr(docking_start, docking_end - docking_start) \
		if docking_start >= 0 and docking_end > docking_start else ""
	_expect(
		source.contains("var _intro_dock_command_issued: bool = false")
			and source.contains("if mode == \"DOCK\" and target == _intro_primary_station():")
			and source.contains("_intro_dock_command_issued = true")
			and source.contains("not _intro_dock_command_issued")
			and source.contains("_clear_intro_handhold_arrow()"),
		"Dock command does not latch the starter tutorial arrow off during approach."
	)
	_expect(
		not docking_source.contains("_intro_dock_command_issued = false"),
		"Starting the docking procedure resets the accepted dock command and revives the old tutorial arrow."
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


func _test_station_welcome_holds_dock_interaction() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect station-welcome wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("const STATION_WELCOME_HOLD_SECONDS := 2.5")
			and source.contains("func _show_station_welcome")
			and source.contains("WELCOME TO\\n%s")
			and source.contains("OUTPOST ARRIVAL")
			and source.contains("_show_station_welcome(station, is_outpost)")
			and source.contains("func _reveal_dock_panel"),
		"Fresh station and outpost docks do not show a reusable welcome hold before services."
	)
	_expect(
		source.contains("_docking_procedure_active or _station_welcome_active")
			and source.contains("station_welcome_overlay.mouse_filter = Control.MOUSE_FILTER_STOP")
			and source.contains("_update_intro_handhold()"),
		"Station welcome does not block click-through or suppress the tutorial handhold until services appear."
	)


func _test_broken_gate_storm_mix_contract() -> void:
	var audio_file := FileAccess.open("res://scripts/AudioManager.gd", FileAccess.READ)
	var intro_file := FileAccess.open("res://scripts/story/IntroCinematic.gd", FileAccess.READ)
	_expect(
		audio_file != null and intro_file != null,
		"Could not inspect broken-gate ambience wiring."
	)
	if audio_file == null or intro_file == null:
		return
	var audio_source := audio_file.get_as_text()
	var intro_source := intro_file.get_as_text()
	_expect(
		audio_source.contains("BROKEN_GATE_RAIN_PATH")
			and audio_source.contains("BROKEN_GATE_THUNDER_PATH")
			and audio_source.contains("func begin_broken_gate_ambience")
			and audio_source.contains("func stop_broken_gate_ambience")
			and audio_source.contains("_dialogue_duck_sfx_db = 4.0"),
		"Broken-gate ambience does not run both storm tracks with lighter dialogue ducking."
	)
	_expect(
		intro_source.contains("AudioManager.begin_broken_gate_ambience()")
			and intro_source.contains("AudioManager.stop_broken_gate_ambience()")
			and intro_source.contains("warp_drop_player.finished.connect(AudioManager.resume_music_after_broken_gate"),
		"Broken-gate music does not wait for the return-to-normal-space effect before resuming."
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
