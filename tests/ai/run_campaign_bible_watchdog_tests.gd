extends SceneTree

## Playtest 2026-10-04 b finding 2: the campaign bible request sat ten minutes
## inside Ollama with the story model never loading. The bible now cancels the
## small model's warm-up first, watches the story model load, and on a stall
## cancels the request and calls for a restart; the game owns Ollama.
##   Godot --headless --path . --script res://tests/ai/run_campaign_bible_watchdog_tests.gd --log-file <path> -- --baseline-offline

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var llm: Node = root.get_node("LLMInterface")
	_check(bool(llm.ollama_auto_restart_allowed), "the game owns Ollama: restarts allowed by default")

	# A warm-up in flight is cancelled when the bible starts.
	var warm := HTTPRequest.new()
	llm.add_child(warm)
	llm._small_model_http.append(warm)
	llm._models_warm_started = true
	llm._cancel_small_model_warmup()
	_check(llm._small_model_http.is_empty() and warm.is_queued_for_deletion(), "the small model's warm-up is cancelled")
	_check(not bool(llm._models_warm_started), "and it will warm again after the story gate")

	# A request whose model never loads is cancelled as stalled.
	llm.campaign_bible_load_stall_s = 4.0
	var bible := HTTPRequest.new()
	llm.add_child(bible)
	var stalled := [false]
	llm._watch_campaign_bible_load(bible, "no-such-model:none", func() -> void: stalled[0] = true)
	_check(str(llm.campaign_bible_stage) == "loading_model", "the loading screen hears: loading the story model")
	var waited := 0.0
	while not stalled[0] and waited < 20.0:
		await create_timer(0.5).timeout
		waited += 0.5
	_check(stalled[0], "a model that never loads is called a stall (%.1f s)" % waited)
	_check(not is_instance_valid(bible) or bible.is_queued_for_deletion(), "the stuck request is cancelled")

	# A request that completes on its own ends the watch quietly.
	var done := HTTPRequest.new()
	llm.add_child(done)
	var fired := [false]
	llm._watch_campaign_bible_load(done, "no-such-model:none", func() -> void: fired[0] = true)
	done.queue_free()
	await create_timer(6.0).timeout
	_check(not fired[0], "an answered request isn't treated as a stall")

	# The story model is loaded on the title screen (Abe, 2026-10-04); while it
	# holds the GPU the small model waits, and passing the story gate releases it.
	llm._models_warm_started = false
	llm._story_preload_state = "ready"
	llm.set_campaign_bible_priority_active(false)
	llm._ollama_warm_models()
	_check(not bool(llm._models_warm_started), "the small model waits while the story model is loaded")
	llm.warm_small_model_after_story_gate()
	_check(str(llm._story_preload_state) == "released", "past the story gate the story model makes way")
	var src := FileAccess.get_file_as_string("res://scripts/LLMInterface.gd")
	_check(src.contains("[small_model] if _story_preload_holds_gpu() else [small_model, model_name]"), "a preloaded story model isn't cleared before the story request")
	_check(src.contains("_preload_story_model()\n\t\t_discover_ollama_model()") or src.contains("_preload_story_model()\r\n\t\t_discover_ollama_model()"), "the preload starts before the small model warms")

	var ui_text := FileAccess.get_file_as_string("res://scripts/UIManager.gd")
	_check(ui_text.contains("Loading the story model") and ui_text.contains("_tick_story_status()"), "the loading screen shows the real stage and a clock")
	if _failures.is_empty():
		print("[PASS] Campaign bible watchdog")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
