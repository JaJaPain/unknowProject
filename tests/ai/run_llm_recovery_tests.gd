extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	if file == null:
		_expect(false, "Could not read LLMInterface.gd.")
	else:
		var source := file.get_as_text()
		file.close()
		_test_heartbeat_starts_once_after_service_recovery(source)
		_test_small_transport_failures_trigger_recovery(source)
		_test_failed_probe_keeps_optional_work_deferred(source)
	if _failures.is_empty():
		print("[PASS] LLM recovery tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_heartbeat_starts_once_after_service_recovery(source: String) -> void:
	var after_up := _function_body(source, "func _ollama_after_up")
	_expect(after_up.contains("_start_ollama_heartbeat()"), "Healthy Ollama must start the watchdog.")
	_expect(source.contains("var _ollama_heartbeat_timer: Timer"), "Watchdog must own one reusable Timer.")
	var heartbeat := _function_body(source, "func _run_ollama_heartbeat")
	_expect(not heartbeat.contains("_schedule_ollama_heartbeat"), "Heartbeat must not multiply timer chains.")


func _test_small_transport_failures_trigger_recovery(source: String) -> void:
	var transport := _function_body(source, "func _request_small_inner_text")
	_expect(transport.contains("_handle_small_transport_failure"), "Small-model transport failures must enter recovery.")
	var recovery := _function_body(source, "func _handle_small_transport_failure")
	_expect(
		recovery.contains("attempt_ollama_recovery()") and recovery.contains("_schedule_small_model_probe_retry"),
		"Transport recovery must restore service and retry readiness before optional work resumes."
	)


func _test_failed_probe_keeps_optional_work_deferred(source: String) -> void:
	var probe := _function_body(source, "func _verify_small_model_ready")
	_expect(probe.contains("_schedule_small_model_probe_retry(model_name)"), "Failed readiness probes must schedule a retry.")
	_expect(not probe.contains("_release_small_model_gate(model_name, \"probe_failed\")"), "Failed probes must not falsely open the small-model gate.")
	_expect(probe.contains("\"think\": false"), "The Qwen3 readiness probe must disable reasoning output.")
	var release := _function_body(source, "func _release_small_model_gate")
	_expect(release.contains("--llm-live-fire"), "Live-fire mode must suppress optional chatter refills.")


func _function_body(source: String, marker: String) -> String:
	var start := source.find(marker)
	if start < 0:
		return ""
	var end := source.find("\nfunc ", start + marker.length())
	return source.substr(start, source.length() - start if end < 0 else end - start)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
