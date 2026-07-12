extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var llm := root.get_node_or_null("LLMInterface")
	_expect(llm != null, "LLMInterface autoload is unavailable.")
	if llm != null:
		_test_non_kaelen_speaker_leaks_are_repaired(llm)
		_test_kaelen_speaker_keeps_shiny(llm)

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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
