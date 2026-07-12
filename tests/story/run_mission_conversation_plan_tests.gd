extends SceneTree

const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_registry_contains_required_intents()
	_test_plan_uses_knowledge_questions_and_mission_context()
	_test_mechanical_and_relationship_gates_terminal_intents()

	if _failures.is_empty():
		print("[PASS] Mission conversation plan tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_registry_contains_required_intents() -> void:
	var registry := PlanType.intent_registry()
	for intent_id in [
		"clarify_term",
		"ask_why",
		"ask_risk",
		"ask_connection",
		"accept_standard",
		"request_advance",
		"request_hazard_pay",
		"decline",
		"informed_followup",
	]:
		_expect(
			registry.has(intent_id),
			"Mission conversation intent registry is missing %s." % intent_id
		)


func _test_plan_uses_knowledge_questions_and_mission_context() -> void:
	var plan: Dictionary = PlanType.build_plan(
		{
			"objective_type": "RECOVER_COMBAT_DROP",
			"public_because": "The station needs evidence before the convoy case goes cold.",
			"stake": "The dock crew loses hazard coverage if the report stalls.",
			"story_thread_id": "thread.convoy_shortage",
			"offer_fact_ids": ["fact.convoy_shortage.visible"],
		},
		[
			{
				"intent_id": "grounding:fact.convoy_shortage.visible",
				"kind": "grounding",
				"label": "What convoy case?",
				"fact_ids": ["fact.convoy_shortage.visible"],
				"answer_anchors": ["convoy case", "missing convoy"],
			},
			{
				"intent_id": "deeper:fact.convoy_shortage.visible",
				"kind": "deeper",
				"label": "Who benefits if it stalls?",
				"fact_ids": ["fact.convoy_shortage.visible"],
			},
		],
		{"respect": 1},
		{"can_request_advance": true}
	)
	var ids: Array = plan.get("intent_ids", [])
	_expect(ids.has("clarify_term"), "Plan did not include grounding clarify intent.")
	_expect(ids.has("ask_why"), "Plan did not include why intent.")
	_expect(ids.has("ask_risk"), "Plan did not include risk intent.")
	_expect(ids.has("ask_connection"), "Plan did not include connection intent.")
	_expect(ids.has("informed_followup"), "Plan did not include deeper follow-up intent.")
	_expect(ids.has("accept_standard"), "Plan did not include accept intent.")
	_expect(ids.has("request_advance"), "Plan did not include available advance intent.")
	_expect(ids.has("request_hazard_pay"), "Plan did not include available hazard-pay intent.")
	_expect(ids.has("decline"), "Plan did not include decline intent.")
	var clarify := _intent_by_id(plan, "clarify_term")
	_expect(
		(clarify.get("answer_anchors", []) as Array).has("convoy case"),
		"Plan did not carry knowledge answer anchors into clarify intent."
	)


func _test_mechanical_and_relationship_gates_terminal_intents() -> void:
	var plan: Dictionary = PlanType.build_plan(
		{
			"objective_type": "KILL_SHIPS",
			"risk_text": "The target patrol is baiting escorts.",
		},
		[],
		{"respect": -7},
		{
			"can_accept": false,
			"can_decline": true,
			"can_request_advance": false,
			"can_request_hazard_pay": true,
		}
	)
	var ids: Array = plan.get("intent_ids", [])
	_expect(not ids.has("accept_standard"), "Plan offered accept when mechanics disabled it.")
	_expect(not ids.has("request_advance"), "Plan offered advance when mechanics disabled it.")
	_expect(
		not ids.has("request_hazard_pay"),
		"Plan offered hazard pay despite hostile relationship gate."
	)
	_expect(ids.has("decline"), "Plan should still offer decline when enabled.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _intent_by_id(plan: Dictionary, intent_id: String) -> Dictionary:
	for raw_intent in plan.get("intents", []):
		if raw_intent is Dictionary and str((raw_intent as Dictionary).get("id", "")) == intent_id:
			return raw_intent as Dictionary
	return {}
