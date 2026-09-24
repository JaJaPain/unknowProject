extends SceneTree

## The comms bus: exists, is band-limited, feeds the Voice bus (so the voice
## volume applies), and is used for exactly one line at a time.
##   Godot --headless --path . --script res://tests/story/run_comms_bus_tests.gd --log-file <path> -- --baseline-offline

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var tts := root.get_node_or_null("TTSInterface")
	_check(tts != null, "TTSInterface autoload is present")
	if tts != null:
		var idx := AudioServer.get_bus_index(tts.COMMS_BUS)
		_check(idx != -1, "the comms bus exists")
		if idx != -1:
			_check(AudioServer.get_bus_send(idx) == &"Voice", "the comms bus feeds the Voice bus")
			var has_band := false
			for i in AudioServer.get_bus_effect_count(idx):
				if AudioServer.get_bus_effect(idx, i) is AudioEffectBandPassFilter:
					has_band = true
			_check(has_band, "the comms bus is band-limited")
		var speech := root.get_node_or_null("SpeechService")
		_check(speech != null, "SpeechService autoload is present")
		if speech != null:
			speech.play_on_comms("", "voice.neutral.v1")
			_check(tts.next_dialogue_bus == "Voice", "an empty comms line does not leave the comms bus armed")
			tts.next_dialogue_bus = tts.COMMS_BUS
			tts.play_dialogue_audio("Radio check.", "voice.neutral.v1")
			_check(tts.audio_player.bus == &"Comms" and tts.next_dialogue_bus == "Voice", "one line uses comms, then it resets")
			tts.play_dialogue_audio("Normal line.", "voice.neutral.v1")
			_check(tts.audio_player.bus == &"Voice", "the next ordinary line is back on Voice")
	if _failures.is_empty():
		print("[PASS] Comms bus tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
