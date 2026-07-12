extends SceneTree

const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")
const CompilerType := preload("res://scripts/story/MissionConversationCompiler.gd")
const ValidatorType := preload("res://scripts/story/DialogueBundleValidator.gd")
const ControllerType := preload("res://scripts/story/MissionConversationController.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_pure_mission_conversation_flow()

	if _failures.is_empty():
		print("[PASS] Mission conversation flow tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_pure_mission_conversation_flow() -> void:
	var mission_plan := {
		"title": "Relay Evidence Run",
		"objective_type": "RECOVER_COMBAT_DROP",
		"objective_summary": "Recover blackbox shard from hostile wreckage.",
		"reward_credits": 240,
		"public_because": "The convoy case needs evidence before the report is buried.",
		"stake": "Dock crews lose hazard coverage if the report stalls.",
		"risk_text": "Raiders are stripping the wreckage.",
	}
	var conversation_plan: Dictionary = PlanType.build_plan(
		mission_plan,
		[
			{
				"intent_id": "grounding:fact.convoy.visible",
				"kind": "grounding",
				"label": "What convoy case?",
				"fact_ids": ["fact.convoy.visible"],
				"answer_anchors": ["convoy case"],
			},
		],
		{"respect": 1},
		{"can_request_advance": true}
	)
	var bundle := CompilerType.fallback_bundle(mission_plan, conversation_plan)
	bundle["clarify_term_response"] = "The convoy case needs evidence before the report is buried."
	bundle["ask_why_response"] = "The convoy case decides whether dock crews keep hazard coverage."
	var validation: Dictionary = ValidatorType.validate_bundle(
		bundle,
		conversation_plan,
		_speaker_card()
	)
	_expect(bool(validation.get("ok", false)), "Compiled fallback bundle did not validate.")
	var opening: Dictionary = ControllerType.start(conversation_plan, bundle)
	_expect(
		str(opening.get("text", "")).contains("Relay Evidence Run"),
		"Controller opening did not expose compiled bundle opening."
	)
	var answer: Dictionary = ControllerType.select_intent(
		opening.get("state", {}),
		"clarify_term"
	)
	_expect(
		str(answer.get("text", "")).contains("convoy case")
			and not bool(answer.get("complete", false)),
		"Question intent did not show anchored cached answer without completing."
	)
	var terminal: Dictionary = ControllerType.select_intent(
		answer.get("state", {}),
		"accept_standard"
	)
	var selected_choice: Dictionary = terminal.get("terminal_choice", {})
	_expect(
		bool(terminal.get("complete", false))
			and str(selected_choice.get("choice_id", "")) == "choice.accept_standard",
		"Terminal intent did not produce a QuestManager-ready accept choice."
	)


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
