extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var tts = root.get_node("TTSInterface")
	tts.cache_queue.clear()
	tts.tts_audio_cache.clear()
	tts.tts_connected = false
	var text := "Captain, tutorial speech is ready."
	# Exercise the real enqueue and playback paths without a running server.
	for delivery in [[1.0, 1.0], [0.92, 1.0], [1.0, 1.2]]:
		var speed: float = delivery[0]
		var style: float = delivery[1]
		tts.cache_dialogue_audio(text, "af_bella", speed, style)
	_expect(tts.cache_queue.size() == 3, "Distinct deliveries must not deduplicate.")
	var clips: Array[AudioStreamWAV] = []
	for item in tts.cache_queue:
		var clip := AudioStreamWAV.new()
		clip.mix_rate = 24000
		clip.format = AudioStreamWAV.FORMAT_16_BITS
		clip.data = PackedByteArray([0, 0, 1, 0, 0, 0, 1, 0])
		clips.append(clip)
		# Background completion stores its stream using this queued key.
		tts.tts_audio_cache[item.key] = clip
	var index := 0
	for delivery in [[1.0, 1.0], [0.92, 1.0], [1.0, 1.2]]:
		tts.play_dialogue_audio(text, "af_bella", delivery[0], delivery[1])
		_expect(not tts.is_requesting, "Prepared speech must not request synthesis.")
		_expect(tts.audio_player.stream == clips[index], "Playback must select the matching delivery.")
		_expect(
			tts.cache_dialogue_audio(text, "af_bella", delivery[0], delivery[1]) == "already_cached",
			"Repeated precaching must reuse the matching delivery."
		)
		index += 1
	tts.play_dialogue_audio("")
	if _failures.is_empty():
		print("[PASS] TTS prepared-cache playback tests")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
