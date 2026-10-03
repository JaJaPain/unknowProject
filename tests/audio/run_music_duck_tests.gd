extends SceneTree

## Playtest 2026-10-03 findings 1 and 2: stingers duck the music and it fades
## back in (never snaps); quick music-state flips never leave it silent.
##   Godot --headless --path . --script res://tests/audio/run_music_duck_tests.gd --log-file <path>

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var am: Node = root.get_node("AudioManager")
	# Finding 2: explore -> tension -> explore inside the crossfade time.
	am.set_music_state("tension")
	await create_timer(0.5).timeout
	am.set_music_state("explore")
	await create_timer(0.4).timeout
	am.set_music_state("tension")
	await create_timer(3.0).timeout
	_check(am.bgm_player.playing and am.bgm_player.volume_db > -1.0, "after quick flips the music is playing at full (%s, %.1f dB)" % [am.bgm_player.playing, am.bgm_player.volume_db])
	_check(not am._bgm_alt.playing or am._bgm_alt.volume_db < -30.0, "the other player is faded out")
	# The watchdog: everything stopped, it comes back by itself.
	am.bgm_player.stop()
	am._bgm_alt.stop()
	await create_timer(am.MUSIC_WATCHDOG_S + 1.0).timeout
	_check(am.bgm_player.playing or am._bgm_alt.playing, "silence is noticed and the music restarts")
	_check(am.bgm_player.bus == am.MUSIC_BED_BUS and am._stinger_player.bus == "Music", "tracks on the bed, stingers above it")

	# Finding 1: a stinger ducks the bed, holds, then fades back in slowly.
	am.play_stinger("victory")
	var length: float = am._stinger_player.stream.get_length()
	await create_timer(0.4).timeout
	_check(am.music_bed_db() <= am.STINGER_DUCK_DB + 0.5, "ducked under the stinger (%.1f dB)" % am.music_bed_db())
	await create_timer(maxf(0.1, length - 0.6)).timeout
	_check(am.music_bed_db() <= am.STINGER_DUCK_DB + 1.0, "still ducked until the stinger ends (%.1f dB)" % am.music_bed_db())
	var last: float = am.music_bed_db()
	var biggest_step := 0.0
	var samples := 0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int((am.STINGER_RESTORE_S + 1.0) * 1000.0):
		await process_frame
		var now: float = am.music_bed_db()
		_check(now >= last - 0.01, "the fade never dips back down")
		biggest_step = maxf(biggest_step, now - last)
		last = now
		samples += 1
	_check(absf(last) < 0.05, "back to full at the end (%.2f dB)" % last)
	_check(biggest_step < 2.0, "a gentle fade, no jump (largest step %.2f dB over %d frames)" % [biggest_step, samples])
	if _failures.is_empty():
		print("[PASS] Music duck and crossfades")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
