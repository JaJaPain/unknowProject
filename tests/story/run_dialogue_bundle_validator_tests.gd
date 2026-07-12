extends SceneTree

const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")
const CompilerType := preload("res://scripts/story/MissionConversationCompiler.gd")
const ValidatorType := preload("res://scripts/story/DialogueBundleValidator.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_valid_bundle_passes()
	_test_missing_and_extra_keys_fail()
	_test_banned_speaker_tics_fail()
	_test_question_answers_require_declared_anchor()
	_test_degrade_bundle_repairs_bad_optional_answer()

	if _failures.is_empty():
		print("[PASS] Dialogue bundle validator tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_valid_bundle_passes() -> void:
	var plan := _conversation_plan()
	var bundle := CompilerType.fallback_bundle(_mission_plan(), plan)
	var result: Dictionary = ValidatorType.validate_bundle(bundle, plan, _speaker_card())
	_expect(bool(result.get("ok", false)), "Valid fallback bundle did not pass validation.")


func _test_missing_and_extra_keys_fail() -> void:
	var plan := _conversation_plan()
	var bundle := CompilerType.fallback_bundle(_mission_plan(), plan)
	bundle.erase("accept_standard_response")
	bundle["surprise_choice"] = "Invented by the model."
	var result: Dictionary = ValidatorType.validate_bundle(bundle, plan, _speaker_card())
	var errors: Array = result.get("errors", [])
	_expect(not bool(result.get("ok", false)), "Invalid bundle unexpectedly passed.")
	_expect(
		errors.has("missing_or_short:accept_standard_response"),
		"Validator did not flag missing required response."
	)
	_expect(
		errors.has("unexpected_key:surprise_choice"),
		"Validator did not flag unexpected model-owned key."
	)


func _test_banned_speaker_tics_fail() -> void:
	var plan := _conversation_plan()
	var bundle := CompilerType.fallback_bundle(_mission_plan(), plan)
	bundle["opening"] = "Listen, Shiny, I have work."
	var result: Dictionary = ValidatorType.validate_bundle(bundle, plan, _speaker_card())
	var errors: Array = result.get("errors", [])
	_expect(not bool(result.get("ok", false)), "Banned tic bundle unexpectedly passed.")
	_expect(
		errors.has("banned_tic:opening:Shiny"),
		"Validator did not flag speaker banned tic."
	)


func _test_question_answers_require_declared_anchor() -> void:
	var plan := _conversation_plan()
	var bundle := CompilerType.fallback_bundle(_mission_plan(), plan)
	bundle["clarify_term_response"] = "That is complicated. Trust me."
	var result: Dictionary = ValidatorType.validate_bundle(bundle, plan, _speaker_card())
	var errors: Array = result.get("errors", [])
	_expect(not bool(result.get("ok", false)), "Vague question answer unexpectedly passed.")
	_expect(
		errors.has("missing_answer_anchor:clarify_term"),
		"Validator did not flag missing question answer anchor."
	)
	bundle["clarify_term_response"] = "The convoy case needs evidence before the report is buried."
	result = ValidatorType.validate_bundle(bundle, plan, _speaker_card())
	_expect(bool(result.get("ok", false)), "Anchored question answer did not pass validation.")


func _test_degrade_bundle_repairs_bad_optional_answer() -> void:
	var plan := _conversation_plan()
	var bundle := CompilerType.fallback_bundle(_mission_plan(), plan)
	bundle["opening"] = "Mara keeps the tablet angled away from station cameras."
	bundle["clarify_term_player"] = "What convoy case?"
	bundle["clarify_term_response"] = "That is complicated. Trust me."
	bundle["accept_standard_response"] = "Keep the wreckage intact and we are square."
	bundle["model_invented_choice"] = "Pay me in secrets."
	var result: Dictionary = ValidatorType.degrade_bundle(
		bundle,
		_mission_plan(),
		plan,
		_speaker_card()
	)
	var repaired: Dictionary = result.get("bundle", {})
	var degraded_fields: Array = result.get("degraded_fields", [])
	_expect(bool(result.get("ok", false)), "Degraded bundle did not validate.")
	_expect(
		degraded_fields.has("clarify_term_response"),
		"Bad optional answer was not marked as degraded."
	)
	_expect(
		not repaired.has("model_invented_choice"),
		"Invented model key survived degradation."
	)
	_expect(
		str(repaired.get("opening", "")) == "Mara keeps the tablet angled away from station cameras.",
		"Valid opening was not preserved during degradation."
	)
	_expect(
		str(repaired.get("accept_standard_response", "")) == "Keep the wreckage intact and we are square.",
		"Valid terminal response was not preserved during degradation."
	)
	_expect(
		str(repaired.get("clarify_term_response", "")).to_lower().contains("convoy case"),
		"Degraded answer did not use anchored fallback text."
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
				"answer_anchors": ["convoy case", "evidence"],
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
	}


func _speaker_card() -> Dictionary:
	return {
		"name": "Mara Venn",
		"voice_rules": {
			"banned_tics": ["Shiny"],
		},
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
