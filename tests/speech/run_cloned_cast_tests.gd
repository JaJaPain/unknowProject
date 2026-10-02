extends SceneTree

## Only N.O.V.A. speaks in her cloned (F5) voice; Kaelen stays on Kokoro at her
## own pace (Abe, 2026-09-24). Playtest 2026-10-02: Kaelen's old cloned takes
## were being served and she spoke ~25% too fast.
##   Godot --headless --path . --script res://tests/speech/run_cloned_cast_tests.gd --log-file <path> -- --baseline-offline

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var tts: Node = root.get_node("TTSInterface")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(tts.CAST_MANIFEST))
	var kaelen_line := ""
	var nova_line := ""
	var flat := {}
	_flatten(manifest, flat)
	for key in flat:
		var parts := str(key).split("|", true, 1)
		if parts.size() < 2:
			continue
		if parts[0] == "kaelen" and kaelen_line.is_empty():
			kaelen_line = parts[1]
		elif parts[0] == "nova" and nova_line.is_empty():
			nova_line = parts[1]
	_check(not kaelen_line.is_empty() and not nova_line.is_empty(), "the manifest has lines for both")
	_check(tts.cast_stream_for("kaelen", kaelen_line) == null, "Kaelen's old cloned take is never used")
	_check(tts.cast_stream_for("nova", nova_line) != null, "N.O.V.A.'s cloned take still is")
	if _failures.is_empty():
		print("[PASS] Cloned cast")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _flatten(value, out: Dictionary) -> void:
	if value is Dictionary:
		for k in value:
			if value[k] is Dictionary:
				_flatten(value[k], out)
			else:
				out[k] = value[k]


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
