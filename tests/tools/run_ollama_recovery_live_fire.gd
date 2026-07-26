extends SceneTree

# Exercises the same startup/watchdog recovery path used by the game after the
# Ollama health endpoint disappears. Run only after intentionally stopping the
# local Ollama service; this script never kills or launches it itself.

const ARTIFACT_PATH := "res://logs/ollama_recovery_live_fire.json"
const MAX_WAIT_SECONDS := 35.0

var _llm: Node = null
var _started_msec := 0


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
	await process_frame
	_llm = get_root().get_node_or_null("LLMInterface")
	if _llm == null:
		_finish(false, "LLMInterface autoload unavailable")
		return
	var deadline := Time.get_ticks_msec() + int(MAX_WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if await _ping_once():
			_finish(true, "Ollama health endpoint recovered through game watchdog startup flow")
			return
		await create_timer(1.0, true, false, true).timeout
	_finish(false, "Ollama health endpoint did not recover within %ds" % int(MAX_WAIT_SECONDS))


func _ping_once() -> bool:
	var finished := false
	var up := false
	_llm.call("_ollama_ping", func(is_up: bool) -> void:
		up = is_up
		finished = true
	)
	var deadline := Time.get_ticks_msec() + 4000
	while not finished and Time.get_ticks_msec() < deadline:
		await process_frame
	return up


func _finish(ok: bool, detail: String) -> void:
	var artifact := {
		"ok": ok,
		"detail": detail,
		"elapsed_seconds": float(Time.get_ticks_msec() - _started_msec) / 1000.0,
		"game_launched_ollama_pid": int(_llm.get("_ollama_start_pid")) if _llm != null else -1,
		"llm_connected": bool(_llm.get("llm_connected")) if _llm != null else false,
	}
	var file := FileAccess.open(ARTIFACT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(artifact, "\t"))
		file.close()
	print("[OllamaRecoveryLiveFire] %s: %s" % ["PASS" if ok else "FAIL", detail])
	quit(0 if ok else 1)
