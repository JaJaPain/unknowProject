extends SceneTree

const SoulsType := preload("res://scripts/story/FixedCastSoulRegistry.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	var loaded: Dictionary = SoulsType.load_registry()
	_expect(bool(loaded.get("ok", false)), "Fixed-cast soul registry did not load: %s" % str(loaded))
	for soul_id in ["kaelen", "nova"]:
		var soul: Dictionary = (loaded.get("souls", {}) as Dictionary).get(soul_id, {})
		_expect(not soul.is_empty(), "Missing %s soul." % soul_id)
		_expect(not (soul.get("states", {}) as Dictionary).is_empty(), "%s has no state map." % soul_id)
		_expect(not (soul.get("situation_rules", {}) as Dictionary).is_empty(), "%s has no situation rules." % soul_id)
		_expect((soul.get("rapport_tone", {}) as Dictionary).has("infatuated"), "%s is missing the rapport scale." % soul_id)
	var kaelen := SoulsType.public_prompt_projection("kaelen", "quietly_relieved", "turn_in")
	_expect(bool(kaelen.get("ok", false)) and str(kaelen.get("version", "")) == "1.0.0", "Kaelen public projection failed.")
	_expect(not JSON.stringify(kaelen).to_lower().contains("hidden angle"), "Kaelen public projection exposed a private field.")
	var nova := SoulsType.public_prompt_projection("nova", "protective", "repair_warning")
	_expect(bool(nova.get("ok", false)) and JSON.stringify(nova).contains("Captain"), "Nova public projection lost address guidance.")
	_expect(str(SoulsType.public_prompt_projection("nova", "missing", "arrival").get("reason", "")).begins_with("unknown_soul_state"), "Unknown fixed-cast state should fail precisely.")
	var block := SoulsType.prompt_block("kaelen", "broker_neutral", "turn_in", "fond", "The Captain closed the first job.")
	_expect(block.contains("Fixed-cast soul v1.0.0") and block.contains("Situation must do") and block.contains("Current rapport (fond)") and block.contains("Earned shared-memory callback"), "Fixed-cast prompt block lost its state/situation/rapport/memory contract.")
	var llm_file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	var root_file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	_expect(llm_file != null and root_file != null, "Could not inspect fixed-cast prompt wiring.")
	if llm_file != null and root_file != null:
		var llm_source := llm_file.get_as_text()
		var root_source := root_file.get_as_text()
		_expect(llm_source.contains("FixedCastSoulRegistryType.prompt_block(\"kaelen\"") and root_source.contains("FixedCastSoulRegistryType.prompt_block("), "Fixed-cast soul projections are not wired into Kaelen/Nova generation.")
		_expect(llm_source.contains("fixed_cast_rapport_band(\"kaelen\")") and root_source.contains("fixed_cast_rapport_band(\"nova\")"), "Current rapport is not wired into Kaelen/Nova generation.")
		_expect(llm_source.contains("fixed_cast_state(\"kaelen\")") and root_source.contains("fixed_cast_state(\"nova\")"), "Code-owned fixed-cast states are not wired into generation.")
	if _failures.is_empty():
		print("[PASS] Fixed-cast soul tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
