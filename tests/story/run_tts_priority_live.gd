extends SceneTree

## LIVE (manual; needs the Kokoro server): a long live line must still play
## while the background cache is busy (Abe's missing Kaelen line, 2026-09-24).
##   Godot --headless --path . --script res://tests/story/run_tts_priority_live.gd --log-file <path>

const LINE := "Someone I know, careful type, doesn't do names, has a Reaver problem. One ship. Been circling his routes, picking off things that weren't theirs to touch. He wants it handled quiet. No trail, no questions. You take the shot, credits come to me, I cut you in."


func _initialize() -> void:
	var tts: Node = root.get_node("TTSInterface")
	var waited := 0.0
	while not tts.tts_connected and waited < 60.0:
		await create_timer(0.5).timeout
		waited += 0.5
	if not tts.tts_connected:
		print("[SKIP] TTS server not reachable")
		quit(0)
		return
	for i in 8:
		tts.cache_dialogue_audio("Background cache line number %d, with a little length to it so it takes a moment to render." % i, "af_aoede")
	await create_timer(0.3).timeout
	var started := Time.get_ticks_msec()
	tts.audio_player.stream = null
	tts.play_dialogue_audio(LINE + " %d" % Time.get_ticks_msec(), "af_bella")
	while tts.is_requesting and (Time.get_ticks_msec() - started) < 70000:
		await create_timer(0.25).timeout
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	if tts.audio_player.stream != null:
		print("[PASS] Live line played after %.1fs with the cache busy (%d cache requests active, %d queued)" % [seconds, tts.active_cache_requests, tts.cache_queue.size()])
		quit(0)
	else:
		push_error("[FAIL] Live line never played (%.1fs)" % seconds)
		quit(1)
