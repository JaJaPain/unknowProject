extends SceneTree

const ValidatorType := preload("res://scripts/story/FixedCastLineValidator.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_runtime_kaelen_wiring()
	var fixtures: Array[Dictionary] = [
		_fixture("kaelen", "quietly_relieved", "turn_in", "Ore delivered. My margin cleared, and you got paid.", {"task_anchors": ["ore", "delivered"]}, true),
		_fixture("kaelen", "quietly_relieved", "turn_in", "They are safe now, Shiny.", {"task_anchors": ["ore"]}, false, "generic_safety_claim"),
		_fixture("kaelen", "quietly_relieved", "turn_in", "Clean work, Shiny. The credits cleared.", {"task_anchors": ["ore"]}, false, "missing_turn_in_anchor"),
		_fixture("kaelen", "quietly_relieved", "turn_in", "Ore delivered. DIRECTOR_SALT is pleased.", {"task_anchors": ["ore"], "forbidden_tokens": ["DIRECTOR_SALT"]}, false, "forbidden_fact:DIRECTOR_SALT"),
		_fixture("kaelen", "quietly_relieved", "turn_in", "Ore delivered. This is an emotionally confessional speeches test.", {"task_anchors": ["ore"]}, false, "banned_tic:emotionally confessional speeches"),
		_fixture("kaelen", "wary", "abandonment", "Contract is closed. My fee did not enjoy the experience.", {}, true),
		_fixture("kaelen", "wary", "abandonment", "You owe me for this. Pay the fee.", {}, false, "fictional_or_followup_consequence"),
		_fixture("kaelen", "wary", "abandonment", "N.O.V.A. would never leave a contract behind.", {}, false, "cross_character_voice:nova_name"),
		_fixture("nova", "protective", "combat", "Captain, target weapons are cycling. The next firing window favors us.", {}, true),
		_fixture("nova", "protective", "combat", "That was exciting. Let us celebrate the kill.", {}, false, "missing_actionable_combat_detail"),
		_fixture("nova", "protective", "combat", "Shiny, their weapons are cycling.", {}, false, "cross_character_address:shiny"),
		_fixture("nova", "protective", "repair_warning", "Hull integrity is compromised. I recommend repairs before departure.", {}, true),
		_fixture("nova", "protective", "repair_warning", "Captain, the station has a pleasant atmosphere.", {}, false, "missing_repair_condition"),
		_fixture("nova", "observant", "arrival", "Sensors show uneven traffic in this system.", {}, true),
		_fixture("nova", "observant", "arrival", "Welcome, Captain. It is nice here.", {}, false, "missing_arrival_grounding"),
		_fixture("nova", "observant", "arrival", "Arrival complete. The local star is behaving itself; I have logged the occasion.", {}, false, "copied_curated_reference"),
		_fixture("nova", "observant", "arrival", "Sensors show uneven traffic in this system.", {"recent_lines": ["Sensors show uneven traffic in this system!"]}, false, "recent_repeat"),
		_fixture("nova", "missing", "arrival", "Sensors are clear.", {}, false, "unknown_soul_state:nova:missing"),
		_fixture("kaelen", "broker_neutral", "combat", "The terms are unpleasant.", {}, false, "unknown_soul_situation:kaelen:combat"),
		_fixture("nova", "protective", "combat", "Hull pressure is climbing. I recommend the target exploding before our repair bill does.", {}, false, "copied_curated_reference"),
	]
	_expect(fixtures.size() == 20, "Focused audit must keep exactly 20 curated scenarios.")
	for index in range(fixtures.size()):
		var fixture: Dictionary = fixtures[index]
		var result := ValidatorType.validate_line(
			str(fixture.get("character", "")),
			str(fixture.get("state", "")),
			str(fixture.get("situation", "")),
			str(fixture.get("line", "")),
			fixture.get("context", {})
		)
		var expected_ok := bool(fixture.get("ok", false))
		_expect(bool(result.get("ok", false)) == expected_ok, "Fixture %d returned %s: %s" % [index + 1, str(result.get("ok", false)), str(result)])
		var expected_error := str(fixture.get("error", ""))
		if not expected_error.is_empty():
			_expect((result.get("errors", []) as Array).has(expected_error), "Fixture %d missed %s: %s" % [index + 1, expected_error, str(result)])
	if _failures.is_empty():
		print("[PASS] Fixed-cast line validator 20-scenario audit")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_runtime_kaelen_wiring() -> void:
	var llm_file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	var nova_file := FileAccess.open("res://scripts/ai/Nova.gd", FileAccess.READ)
	_expect(llm_file != null and nova_file != null, "Could not inspect fixed-cast runtime wiring.")
	if llm_file == null:
		return
	var source := llm_file.get_as_text()
	_expect(
		source.contains("FixedCastLineValidatorType.validate_line") and source.contains("_kaelen_reaction_task_anchors"),
		"Kaelen completion generation does not run through the fixed-cast validator."
	)
	if nova_file != null:
		var nova_source := nova_file.get_as_text()
		_expect(
			nova_source.contains("FixedCastLineValidatorType.validate_line") and nova_source.contains("_fixed_cast_situation_for_bank_kind"),
			"N.O.V.A. generated line-bank delivery does not run through the fixed-cast validator."
		)


func _fixture(character: String, state: String, situation: String, line: String, context: Dictionary, ok: bool, error: String = "") -> Dictionary:
	return {"character": character, "state": state, "situation": situation, "line": line, "context": context, "ok": ok, "error": error}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
