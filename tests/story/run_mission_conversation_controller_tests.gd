extends SceneTree

const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")
const ControllerType := preload("res://scripts/story/MissionConversationController.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_opening_shows_all_available_choices()
	_test_opening_uses_more_options_navigation_for_extra_intents()
	_test_question_answer_returns_to_remaining_choices_without_terminal()
	_test_terminal_choice_completes_with_stable_choice_id()
	_test_decline_completes_with_decline_consequence()
	_test_terminal_choice_carries_asked_questions_and_learned_facts()

	if _failures.is_empty():
		print("[PASS] Mission conversation controller tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_opening_shows_all_available_choices() -> void:
	var screen := ControllerType.start(_conversation_plan(), _bundle())
	var choices: Array = screen.get("choices", [])
	_expect(str(screen.get("text", "")) == "The convoy case needs a pilot.", "Opening text was wrong.")
	_expect(choices.size() == 3, "Opening should expose one question and two terminals.")
	_expect(_choice_ids(choices).has("clarify_term"), "Opening did not expose clarify question.")
	_expect(_choice_ids(choices).has("accept_standard"), "Opening did not expose accept terminal.")
	_expect(_choice_ids(choices).has("decline"), "Opening did not expose decline terminal.")


func _test_opening_uses_more_options_navigation_for_extra_intents() -> void:
	var screen := ControllerType.start(_expanded_conversation_plan(), _expanded_bundle())
	var choices: Array = screen.get("choices", [])
	_expect(_choice_ids(choices).has("clarify_term"), "Opening did not expose primary grounding question.")
	_expect(_choice_ids(choices).has("accept_standard"), "Opening did not expose standard acceptance.")
	_expect(_choice_ids(choices).has("decline"), "Opening did not expose decline.")
	_expect(_choice_ids(choices).has("__more_options"), "Opening did not expose more-options navigation.")
	_expect(not _choice_ids(choices).has("ask_why"), "Opening exposed extra question before navigation.")
	var options := ControllerType.select_intent(screen.get("state", {}), "__more_options")
	var option_choices: Array = options.get("choices", [])
	_expect(str(options.get("mode", "")) == "options", "More-options navigation did not enter options mode.")
	_expect(_choice_ids(option_choices).has("ask_why"), "Options view did not expose hidden question.")
	_expect(_choice_ids(option_choices).has("request_hazard_pay"), "Options view did not expose hidden terminal.")


func _test_question_answer_returns_to_remaining_choices_without_terminal() -> void:
	var screen := ControllerType.start(_conversation_plan(), _bundle())
	var answer := ControllerType.select_intent(screen.get("state", {}), "clarify_term")
	var choices: Array = answer.get("choices", [])
	_expect(str(answer.get("mode", "")) == "answer", "Question did not enter answer mode.")
	_expect(str(answer.get("text", "")).contains("reserve bins"), "Question did not show cached answer.")
	_expect(not bool(answer.get("complete", false)), "Question should not complete the conversation.")
	_expect(not _choice_ids(choices).has("clarify_term"), "Asked question should not be offered again.")
	_expect(_choice_ids(choices).has("accept_standard"), "Terminal accept should remain after answer.")
	_expect(str(answer.get("terminal_choice_id", "")).is_empty(), "Question should not produce a QuestManager choice ID.")


func _test_terminal_choice_completes_with_stable_choice_id() -> void:
	var screen := ControllerType.start(_conversation_plan(), _bundle())
	var terminal := ControllerType.select_intent(screen.get("state", {}), "accept_standard")
	_expect(str(terminal.get("mode", "")) == "terminal", "Accept did not enter terminal mode.")
	_expect(bool(terminal.get("complete", false)), "Terminal intent should complete the conversation.")
	_expect(
		str(terminal.get("terminal_choice_id", "")) == "choice.accept_standard",
		"Terminal intent did not return stable QuestManager choice ID."
	)
	var selected_choice: Dictionary = terminal.get("terminal_choice", {})
	var consequence: Dictionary = selected_choice.get("consequence", {})
	_expect(
		str(selected_choice.get("choice_id", "")) == "choice.accept_standard"
			and str(selected_choice.get("text", "")) == "I’ll take it."
			and str(selected_choice.get("conversation_intent_id", "")) == "accept_standard"
			and int(consequence.get("credits_immediate", -1)) == 0,
		"Terminal intent did not return a QuestManager-ready selected choice."
	)
	_expect((terminal.get("choices", []) as Array).is_empty(), "Completed conversation should expose no choices.")


func _test_decline_completes_with_decline_consequence() -> void:
	var screen := ControllerType.start(_conversation_plan(), _bundle())
	var terminal := ControllerType.select_intent(screen.get("state", {}), "decline")
	var selected_choice: Dictionary = terminal.get("terminal_choice", {})
	var consequence: Dictionary = selected_choice.get("consequence", {})
	_expect(
		str(terminal.get("terminal_choice_id", "")) == "choice.decline",
		"Decline did not return a stable QuestManager choice ID."
	)
	_expect(
		str(selected_choice.get("choice_id", "")) == "choice.decline"
			and str(selected_choice.get("conversation_intent_id", "")) == "decline"
			and str(consequence.get("mission_action", "")) == "decline"
			and bool(consequence.get("leaves_mission_lane_empty", false))
			and int(consequence.get("relationship_delta", 0)) == -1,
		"Decline did not return a QuestManager-ready decline consequence."
	)


func _test_terminal_choice_carries_asked_questions_and_learned_facts() -> void:
	var screen := ControllerType.start(_conversation_plan(), _bundle())
	var answer := ControllerType.select_intent(screen.get("state", {}), "clarify_term")
	var terminal := ControllerType.select_intent(answer.get("state", {}), "accept_standard")
	var selected_choice: Dictionary = terminal.get("terminal_choice", {})
	var asked_intents: Array = selected_choice.get("asked_intents", [])
	var learned_fact_ids: Array = selected_choice.get("learned_fact_ids", [])
	_expect(
		asked_intents == ["clarify_term"],
		"Terminal choice did not preserve asked question IDs."
	)
	_expect(
		learned_fact_ids == ["fact.convoy.visible"],
		"Terminal choice did not preserve learned fact IDs."
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
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {},
					"reward_credits_multiplier": 1.0,
				},
			},
			{
				"id": PlanType.INTENT_DECLINE,
				"kind": "terminal",
				"label": "Decline",
				"fact_ids": [],
				"consequence": {
					"mission_action": "decline",
					"leaves_mission_lane_empty": true,
					"relationship_delta": -1,
				},
			},
		],
	}


func _bundle() -> Dictionary:
	return {
		"opening": "The convoy case needs a pilot.",
		"clarify_term_player": "What convoy case?",
		"clarify_term_response": "The reserve bins are empty, and the report is getting buried.",
		"accept_standard_player": "I’ll take it.",
		"accept_standard_response": "Logged. Keep your transponder honest.",
		"decline_player": "Not my problem.",
		"decline_response": "Then I will find someone with fewer survival instincts.",
	}


func _expanded_conversation_plan() -> Dictionary:
	var plan := _conversation_plan()
	var intents: Array = plan.get("intents", [])
	intents.insert(1, {
		"id": PlanType.INTENT_ASK_WHY,
		"kind": "question",
		"label": "Why now?",
		"fact_ids": ["fact.convoy.visible"],
	})
	intents.insert(3, {
		"id": PlanType.INTENT_REQUEST_HAZARD_PAY,
		"kind": "terminal",
		"label": "Ask for hazard pay",
		"fact_ids": [],
		"consequence": {
			"mission_action": "accept",
			"reward_credits_multiplier": 1.15,
		},
	})
	plan["intents"] = intents
	return plan


func _expanded_bundle() -> Dictionary:
	var bundle := _bundle()
	bundle["ask_why_player"] = "Why now?"
	bundle["ask_why_response"] = "Because the reserve bins finally ran out."
	bundle["request_hazard_pay_player"] = "This needs hazard pay."
	bundle["request_hazard_pay_response"] = "Fine. Hazard terms are noted."
	return bundle


func _choice_ids(choices: Array) -> Array[String]:
	var ids: Array[String] = []
	for raw_choice in choices:
		if raw_choice is Dictionary:
			ids.append(str((raw_choice as Dictionary).get("intent_id", "")))
	return ids


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
