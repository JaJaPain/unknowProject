extends SceneTree

# Proves a taunt can be spoken with NO TTS server running. That is the whole
# point of pre-baking, and it is the one property a render script cannot check
# for itself.

const CauseType := preload("res://scripts/combat/TauntCause.gd")
const MANIFEST := "res://assets/audio/taunts/manifest.json"

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var tts: Node = get_root().get_node_or_null("TTSInterface")
	if tts == null:
		push_error("[FAIL] TTSInterface autoload unavailable.")
		quit(1)
		return
	if not FileAccess.file_exists(MANIFEST):
		# Not a failure: the bake is a build step, and the game must run without
		# it by falling back to live TTS.
		print("[SKIP] No baked manifest yet - run tools/bake_taunt_audio.py.")
		quit(0)
		return
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	var doc = JSON.parse_string(file.get_as_text())
	file.close()
	var clips: Dictionary = (doc as Dictionary).get("clips", {})
	_expect(not clips.is_empty(), "Manifest lists no clips.")

	# Every authored line must be resolvable in at least one voice, or that line
	# still costs a live round trip in combat.
	var missing: Array[String] = []
	var checked := 0
	for cause in CauseType.ALL:
		for line in (CauseType.authored_lines(str(cause)) as Array):
			var text := str(line)
			checked += 1
			# Keys carry the DELIVERY, so a lookup must match speed and pause too.
			# A bare voice|text key would be coarser than the file identity and
			# could serve a re-timed line its old audio.
			var delivery: Dictionary = CauseType.delivery_for(text)
			var speed: float = float(delivery.get("speed", -1.0))
			if speed <= 0.0:
				speed = 1.10
			var pause: float = float(delivery.get("pause", -1.0))
			var found := false
			for lead in ["am_onyx", "am_adam", "am_fenrir", "am_liam",
					"bm_george", "am_puck", "am_eric", "am_echo"]:
				var voice := "%s[0.7]+am_michael[0.3]" % lead
				if clips.has("%s|%s|%.2f|%.2f" % [voice, text, speed, pause]):
					found = true
					break
			if not found:
				missing.append(text)
	_expect(
		missing.is_empty(),
		"%d of %d authored lines have no baked clip, e.g. '%s'" % [
			missing.size(), checked, missing[0] if not missing.is_empty() else ""
		]
	)

	# The decisive check: resolve an actual stream. No server is running in a
	# headless test, so a non-null stream can only have come from disk.
	var sample := str(CauseType.authored_lines(CauseType.PIRATE_PREDATION)[0])
	var sample_delivery: Dictionary = CauseType.delivery_for(sample)
	var sample_speed: float = float(sample_delivery.get("speed", -1.0))
	if sample_speed <= 0.0:
		sample_speed = 1.10
	var stream = tts.call(
		"baked_stream_for", "am_onyx[0.7]+am_michael[0.3]", sample,
		sample_speed, float(sample_delivery.get("pause", -1.0))
	)
	_expect(stream != null, "Could not load a baked stream for: %s" % sample)
	if stream != null:
		_expect(
			stream is AudioStream and float(stream.get_length()) > 0.3,
			"Baked stream is empty or too short: %.2fs" % (
				float(stream.get_length()) if stream is AudioStream else 0.0
			)
		)
	# A line that was never baked must return null rather than erroring, so the
	# runtime can fall back to live TTS.
	_expect(
		tts.call("baked_stream_for", "am_onyx[0.7]+am_michael[0.3]", "never baked line", 1.10, -1.0) == null,
		"An unbaked line must resolve to null, not a stream."
	)

	if _failures.is_empty():
		print("[PASS] Baked taunt audio (%d lines covered)" % checked)
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
