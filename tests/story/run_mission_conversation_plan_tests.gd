extends SceneTree

const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")
const KnowledgeLedgerType := preload("res://scripts/story/KnowledgeLedger.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_registry_contains_required_intents()
	_test_plan_uses_knowledge_questions_and_mission_context()
	_test_plan_questions_change_with_knowledge_state()
	_test_mechanical_and_relationship_gates_terminal_intents()
	_test_terminal_intents_carry_code_owned_consequences()

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


func _test_plan_questions_change_with_knowledge_state() -> void:
	var story_state := {"knowledge_revision": 0, "knowledge_states": {}}
	var ledger := KnowledgeLedgerType.new(story_state)
	var mission_plan := {
		"objective_type": "DELIVERY_COURIER",
		"question_fact_ids": ["fact.convoy_loss.rumor"],
		"fact_aliases": {
			"fact.convoy_loss.rumor": "the lost convoy",
		},
	}
	var unknown_plan: Dictionary = PlanType.build_plan(
		mission_plan,
		ledger.question_candidates(mission_plan),
		{},
		{}
	)
	_expect(
		unknown_plan.get("intent_ids", []).has("clarify_term")
			and not unknown_plan.get("intent_ids", []).has("informed_followup"),
		"Unknown player state did not produce a grounding clarify question."
	)
	ledger.promote(
		"fact.convoy_loss.rumor",
		"rumored",
		"lounge_rumor",
		12
	)
	_expect(
		ledger.state_for("fact.convoy_loss.rumor") == "rumored",
		"Test setup failed to promote fact to rumored."
	)
	var rumored_plan: Dictionary = PlanType.build_plan(
		mission_plan,
		ledger.question_candidates(mission_plan),
		{},
		{}
	)
	_expect(
		rumored_plan.get("intent_ids", []).has("informed_followup")
			and not rumored_plan.get("intent_ids", []).has("clarify_term"),
		"Rumored player state did not produce an informed follow-up."
	)
	ledger.promote(
		"fact.convoy_loss.rumor",
		"known",
		"briefing",
		13
	)
	var known_plan: Dictionary = PlanType.build_plan(
		mission_plan,
		ledger.question_candidates(mission_plan),
		{},
		{}
	)
	var followup := _intent_by_id(known_plan, "informed_followup")
	_expect(
		not followup.is_empty()
			and str(followup.get("label", "")).begins_with("Why"),
		"Known player state did not preserve a deeper follow-up question."
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


func _test_terminal_intents_carry_code_owned_consequences() -> void:
	var plan: Dictionary = PlanType.build_plan(
		{
			"objective_type": "RECOVER_COMBAT_DROP",
			"risk_text": "The wreck is still being watched.",
			"story_beat_id": "beat.convoy.evidence",
		},
		[],
		{"respect": 2},
		{
			"can_request_advance": true,
			"advance_credits": 75,
			"hazard_pay_multiplier": 1.25,
			"decline_relationship_delta": -2,
		}
	)
	var accept_consequence: Dictionary = _intent_by_id(plan, "accept_standard").get("consequence", {})
	var advance_consequence: Dictionary = _intent_by_id(plan, "request_advance").get("consequence", {})
	var hazard_consequence: Dictionary = _intent_by_id(plan, "request_hazard_pay").get("consequence", {})
	var decline_consequence: Dictionary = _intent_by_id(plan, "decline").get("consequence", {})
	_expect(
		str(accept_consequence.get("mission_action", "")) == "accept"
			and int(accept_consequence.get("credits_immediate", -1)) == 0,
		"Accept consequence was not code-owned."
	)
	_expect(
		str(advance_consequence.get("mission_action", "")) == "accept"
			and int(advance_consequence.get("credits_immediate", 0)) == 75
			and bool(advance_consequence.get("advance_requested", false)),
		"Advance consequence did not carry code-owned advance terms."
	)
	_expect(
		str(hazard_consequence.get("mission_action", "")) == "accept"
			and is_equal_approx(float(hazard_consequence.get("reward_credits_multiplier", 0.0)), 1.25)
			and bool(hazard_consequence.get("hazard_pay_requested", false)),
		"Hazard-pay consequence did not carry code-owned reward terms."
	)
	_expect(
		str(decline_consequence.get("mission_action", "")) == "decline"
			and bool(decline_consequence.get("leaves_mission_lane_empty", false))
			and int(decline_consequence.get("relationship_delta", 0)) == -2
			and str(decline_consequence.get("declined_story_beat_id", "")) == "beat.convoy.evidence",
		"Decline consequence did not carry code-owned decline effects."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _intent_by_id(plan: Dictionary, intent_id: String) -> Dictionary:
	for raw_intent in plan.get("intents", []):
		if raw_intent is Dictionary and str((raw_intent as Dictionary).get("id", "")) == intent_id:
			return raw_intent as Dictionary
	return {}
