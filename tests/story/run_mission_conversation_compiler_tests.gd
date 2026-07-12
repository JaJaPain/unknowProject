extends SceneTree

const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")
const CompilerType := preload("res://scripts/story/MissionConversationCompiler.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_required_keys_are_flat_and_intent_owned()
	_test_prompt_uses_actual_values_and_code_owned_intents()
	_test_fallback_bundle_covers_required_keys()
	_test_parse_bundle_returns_required_flat_shape()
	_test_parse_bundle_rejects_malformed_or_incomplete_output()

	if _failures.is_empty():
		print("[PASS] Mission conversation compiler tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_required_keys_are_flat_and_intent_owned() -> void:
	var conversation_plan := _conversation_plan()
	var keys: Array[String] = CompilerType.required_output_keys(conversation_plan)
	_expect(keys == [
		"opening",
		"clarify_term_player",
		"clarify_term_response",
		"accept_standard_player",
		"accept_standard_response",
		"decline_player",
		"decline_response",
	], "Compiler required keys were not flat/stable: %s" % JSON.stringify(keys))


func _test_prompt_uses_actual_values_and_code_owned_intents() -> void:
	var prompt: String = CompilerType.build_prompt(
		_mission_plan(),
		_speaker_card(),
		_conversation_plan(),
		"Known fact: freighters stopped arriving on schedule."
	)
	_expect(
		prompt.contains("Relay Evidence Run")
			and prompt.contains("Recover blackbox shard")
			and prompt.contains("240 SC"),
		"Compiler prompt did not include actual mission values."
	)
	_expect(
		prompt.contains("Do not add, remove, rename, reorder, or redefine any intent")
			and prompt.contains("clarify_term")
			and prompt.contains("accept_standard")
			and prompt.contains("decline"),
		"Compiler prompt did not preserve code-owned intent contract."
	)
	_expect(
		not prompt.contains("{ORE_AMOUNT}")
			and not prompt.contains("Slithern")
			and prompt.contains("Return only flat JSON"),
		"Compiler prompt retained placeholder/example artifacts."
	)


func _test_fallback_bundle_covers_required_keys() -> void:
	var conversation_plan := _conversation_plan()
	var bundle: Dictionary = CompilerType.fallback_bundle(_mission_plan(), conversation_plan)
	for key in CompilerType.required_output_keys(conversation_plan):
		_expect(
			bundle.has(key) and not str(bundle.get(key, "")).strip_edges().is_empty(),
			"Fallback bundle missing required key %s." % key
		)


func _test_parse_bundle_returns_required_flat_shape() -> void:
	var parsed: Dictionary = CompilerType.parse_bundle(
		JSON.stringify({
			"opening": "Need a pilot for the relay case.",
			"clarify_term_player": "What relay case?",
			"clarify_term_response": "The convoy report needs evidence.",
			"accept_standard_player": "I’ll take it.",
			"accept_standard_response": "Logged.",
			"decline_player": "Not today.",
			"decline_response": "Then I keep asking.",
			"model_invented_extra": "nope",
		}),
		_conversation_plan()
	)
	_expect(bool(parsed.get("ok", false)), "Valid flat bundle JSON did not parse.")
	var bundle: Dictionary = parsed.get("bundle", {})
	_expect(
		bundle.has("opening")
			and bundle.has("clarify_term_response")
			and not bundle.has("model_invented_extra"),
		"Parsed bundle did not preserve only required flat keys."
	)


func _test_parse_bundle_rejects_malformed_or_incomplete_output() -> void:
	var malformed: Dictionary = CompilerType.parse_bundle(
		"{not valid json",
		_conversation_plan()
	)
	_expect(
		not bool(malformed.get("ok", false))
			and str(malformed.get("reason", "")) == "parse_failed",
		"Malformed bundle JSON should fail with parse_failed."
	)
	var missing: Dictionary = CompilerType.parse_bundle(
		JSON.stringify({
			"opening": "Need a pilot.",
		}),
		_conversation_plan()
	)
	_expect(
		not bool(missing.get("ok", false))
			and str(missing.get("reason", "")).begins_with("missing_key:"),
		"Incomplete bundle JSON should fail with missing_key."
	)


func _conversation_plan() -> Dictionary:
	return {
		"ok": true,
		"intents": [
			{
				"id": PlanType.INTENT_CLARIFY_TERM,
				"kind": "question",
				"label": "What convoy case?",
				"fact_ids": ["fact.convoy.visible"],
			},
			{
				"id": PlanType.INTENT_ACCEPT_STANDARD,
				"kind": "terminal",
				"label": "Accept the contract",
				"fact_ids": [],
			},
			{
				"id": PlanType.INTENT_DECLINE,
				"kind": "terminal",
				"label": "Decline",
				"fact_ids": [],
			},
		],
	}


func _mission_plan() -> Dictionary:
	return {
		"title": "Relay Evidence Run",
		"objective_type": "RECOVER_COMBAT_DROP",
		"objective_summary": "Recover blackbox shard from hostile wreckage.",
		"reward_credits": 240,
		"public_because": "The convoy case needs evidence before the report is buried.",
		"stake": "Dock crews lose hazard coverage if the report stalls.",
		"risk_text": "Raiders are stripping the wreckage.",
	}


func _speaker_card() -> Dictionary:
	return {
		"name": "Mara Venn",
		"role": "station investigator",
		"persona": {
			"core_drive": "Keep dock crews alive by making paperwork tell the truth.",
			"pressure_tell": "Gets clipped and procedural when afraid.",
			"humor_mechanism": "Deadpan bureaucratic understatement.",
		},
		"voice_rules": {
			"sentence_shape": "short, precise, wary",
			"address_rule": "uses pilot rarely",
			"banned_tics": ["Shiny"],
		},
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
