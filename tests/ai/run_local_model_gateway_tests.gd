extends SceneTree

const GatewayType := preload("res://scripts/ai/LocalModelGateway.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_prefers_qwen_3b_for_small_dialogue()
	_test_prefers_large_story_model_for_bible()
	_test_builds_generation_body_from_capability()
	_test_unknown_capability_uses_small_profile()
	_test_routes_new_capabilities_to_expected_profiles()

	if _failures.is_empty():
		print("[PASS] Local model gateway tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_prefers_qwen_3b_for_small_dialogue() -> void:
	var selected: String = GatewayType.select_installed_model(
		[
			"qwen2.5:1.5b-instruct-q4_K_M",
			"qwen2.5:3b-instruct-q4_K_M",
			"gemma4:12b",
		],
		"mechanic_line"
	)
	_expect(
		selected == "qwen2.5:3b-instruct-q4_K_M",
		"Small dialogue profile did not prefer Qwen 2.5 3B."
	)


func _test_prefers_large_story_model_for_bible() -> void:
	var selected: String = GatewayType.select_installed_model(
		[
			"qwen2.5:3b-instruct-q4_K_M",
			"gemma4:12b",
		],
		"campaign_bible"
	)
	_expect(
		selected == "gemma4:12b",
		"Large story profile did not prefer Gemma 12B."
	)


func _test_builds_generation_body_from_capability() -> void:
	var body: Dictionary = GatewayType.generation_body(
		"public_board",
		"Write one board posting.",
		"qwen2.5:3b-instruct-q4_K_M",
		"json",
		{"temperature": 0.8, "num_predict": 220}
	)
	_expect(
		str(body.get("model", "")) == "qwen2.5:3b-instruct-q4_K_M",
		"Generation body did not include active small model."
	)
	_expect(
		str(body.get("format", "")) == "json",
		"Generation body did not keep JSON format."
	)
	_expect(
		int((body.get("options", {}) as Dictionary).get("num_predict", 0)) == 220,
		"Generation body did not preserve options."
	)
	_expect(
		str(body.get("keep_alive", "")) == GatewayType.MODEL_KEEP_ALIVE,
		"Generation body did not set keep_alive to keep the model resident."
	)
	_expect(
		not body.has("think"),
		"Small dialogue generation should not force a thinking-model setting."
	)
	var large_body: Dictionary = GatewayType.generation_body(
		"campaign_bible",
		"Write the campaign bible.",
		"qwen2.5:3b-instruct-q4_K_M",
		"json",
		{"temperature": 0.95, "num_predict": 900},
		"gemma4:12b"
	)
	_expect(
		bool(large_body.get("think", true)) == false,
		"Large story generation should disable thinking output for Ollama."
	)
	_expect(
		int(large_body.get("keep_alive", -1)) == GatewayType.LARGE_MODEL_KEEP_ALIVE,
		"Large story generation should unload after each request to protect VRAM."
	)


func _test_unknown_capability_uses_small_profile() -> void:
	_expect(
		GatewayType.profile_for_capability("future_small_task") == "small_dialogue",
		"Unknown capabilities should default to small dialogue profile."
	)


func _test_routes_new_capabilities_to_expected_profiles() -> void:
	_expect(
		GatewayType.profile_for_capability("background_chatter") == "small_dialogue",
		"Background chatter should use the small dialogue profile."
	)
	_expect(
		GatewayType.profile_for_capability("partial_delivery_line") == "small_dialogue",
		"Partial delivery lines should use the small dialogue profile."
	)
	_expect(
		GatewayType.profile_for_capability("system_names") == "large_story",
		"System names should use the large story profile."
	)
	_expect(
		is_equal_approx(GatewayType.request_timeout("system_names"), 30.0),
		"System name generation should keep its longer timeout."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
