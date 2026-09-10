extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var llm := root.get_node_or_null("LLMInterface")
	_expect(llm != null, "LLMInterface autoload is unavailable.")
	if llm != null:
		_test_non_kaelen_speaker_leaks_are_repaired(llm)
		_test_kaelen_speaker_keeps_shiny(llm)
	_test_ui_choice_response_fallback_is_speaker_safe()
	_test_quest_generation_uses_single_constrained_bundle_call()

	if _failures.is_empty():
		print("[PASS] Quest speaker rule validation tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_non_kaelen_speaker_leaks_are_repaired(llm: Node) -> void:
	var quest := {
		"agent_name": "Director Voss",
		"agent_voice_profile_id": "voice.neutral.v1",
		"dialogue": "Sit tight, Shiny. I'll fetch the client manifest.",
		"choices": [
			{
				"consequence": {
					"dialogue_response": "My best friend does not wait, Shiny."
				}
			}
		],
	}
	_expect(
		bool(llm.call("_quest_has_speaker_rule_leak", quest)),
		"Non-Kaelen quest text with Shiny/banned phrases should be detected."
	)
	_expect(
		bool(llm.call("_sanitize_quest_speaker_rule_leaks", quest)),
		"Non-Kaelen speaker leak should be repaired."
	)
	var combined := (
		str(quest.get("dialogue", ""))
		+ " "
		+ str(
			((quest.get("choices", []) as Array)[0] as Dictionary)
				.get("consequence", {})
				.get("dialogue_response", "")
		)
	)
	_expect(
		not combined.contains("Shiny")
		and not combined.to_lower().contains("sit tight")
		and not combined.to_lower().contains("my best friend"),
		"Non-Kaelen repaired text still contains banned speaker terms: %s" % combined
	)


func _test_kaelen_speaker_keeps_shiny(llm: Node) -> void:
	var quest := {
		"agent_name": "Broker Kaelen",
		"agent_voice_profile_id": "voice.kaelen.v1",
		"dialogue": "Sit tight, Shiny. My best friend in logistics is expensive.",
		"choices": [
			{
				"consequence": {
					"dialogue_response": "Excellent, Shiny. Credits first, morals never."
				}
			}
		],
	}
	_expect(
		not bool(llm.call("_quest_has_speaker_rule_leak", quest)),
		"Kaelen should be allowed to use Shiny."
	)
	_expect(
		not bool(llm.call("_sanitize_quest_speaker_rule_leaks", quest)),
		"Kaelen text should not be rewritten by non-Kaelen sanitizer."
	)
	_expect(
		str(quest.get("dialogue", "")).contains("Shiny"),
		"Kaelen's Shiny nickname was removed."
	)


func _test_ui_choice_response_fallback_is_speaker_safe() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect UIManager speaker fallback wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("func _choice_response_fallback_for_voice")
			and source.contains("GlobalState.is_kaelen_voice")
			and source.contains(
				"clean_response = _choice_response_fallback_for_voice(response_profile)"
			)
			and source.contains("Logged. The contract terms are recorded."),
		"Choice response fallback is not speaker-safe for non-Kaelen quest givers."
	)


func _test_quest_generation_uses_single_constrained_bundle_call() -> void:
	var file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect LLMInterface quest generation wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("const QUEST_BUNDLE_CALL_COUNT := 1")
			and source.contains("single constrained quest bundle request")
			and source.contains("\"bundle_mode\": \"single_constrained\"")
			and source.contains("\"call_count\": QUEST_BUNDLE_CALL_COUNT")
			and source.contains("_trigger_fallback_with_reason(\"quest_bundle_failed\")")
			and not source.contains("QUEST_CANDIDATE_TARGET_COUNT")
			and not source.contains("Sending best-of"),
		"Quest generation still appears wired to the old sequential best-of-three path."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
