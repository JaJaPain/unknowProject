extends SceneTree

## Subtitles: spoken lines are captioned, the fixed cast is named, strangers
## never borrow Kaelen's name, and the setting switches it all off.
##   Godot --headless --path . --script res://tests/story/run_subtitle_tests.gd --log-file <path> -- --baseline-offline

const OverlayType := preload("res://scripts/ui/SubtitleOverlay.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GlobalState")
	var speech: Node = root.get_node("SpeechService")
	var original: bool = gs.subtitles_enabled  # the player's real preference; restored below
	var overlay = OverlayType.new()
	root.add_child(overlay)
	gs.subtitles_enabled = true

	speech.play("Shiny, your shields are about to go.", "voice.kaelen.v1")
	_check(overlay.current_text() == "Kaelen: Shiny, your shields are about to go.", "Kaelen is named: %s" % overlay.current_text())
	speech.play("Course plotted to the gate.", "voice.nova.v1")
	_check(overlay.current_text() == "N.O.V.A.: Course plotted to the gate.", "N.O.V.A. is named: %s" % overlay.current_text())
	speech.play("Dock seven is closed until further notice.", "")
	_check(overlay.current_text() == "Dock seven is closed until further notice.", "an unset voice is never captioned as Kaelen: %s" % overlay.current_text())
	speech.play_on_comms("I need that cargo moved before the shift change.", "voice.neutral.v1", "Dara Holt")
	_check(overlay.current_text() == "Dara Holt: I need that cargo moved before the shift change.", "comms lines carry the poster's name: %s" % overlay.current_text())
	speech.play("Nothing to see here.", "voice.neutral.v1")
	_check(not overlay.current_text().begins_with("Dara Holt"), "a comms name is used for one line only")
	overlay.show_line("A line with no name.", "", 5.0)
	_check(overlay.current_text() == "A line with no name.", "baked moments can show an unnamed line")

	gs.subtitles_enabled = false
	_check(overlay.current_text() == "", "switching subtitles off hides the current line")
	speech.play("You should not see this.", "voice.nova.v1")
	_check(overlay.current_text() == "", "switched off, nothing is captioned")

	speech.stop()
	gs.subtitles_enabled = original
	overlay.free()
	if _failures.is_empty():
		print("[PASS] Subtitle tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
