extends SceneTree

const PolicyType := preload("res://scripts/story/QuestChoicePolicy.gd")
const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")
const Fixtures := preload("res://tests/fixtures/QuestContractFixtures.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_courier_stays_one_path()
	_test_justified_investigation_keeps_both_options()
	_test_unjustified_option_is_removed()
	_test_equivalent_buttons_collapse()
	_test_ineligible_and_unsupported_branches_drop()
	_test_no_mandatory_question_trio()
	_test_risk_question_needs_a_recorded_risk()
	_test_question_dropped_when_opening_already_answers_it()
	_test_plan_without_contract_is_unchanged()

	if _failures.is_empty():
		print("[PASS] Quest choice policy tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


## Vertical example 1: a straightforward job. Nothing may push it into growing
## a menu, and single_path must be reported as the normal outcome it is.
func _test_courier_stays_one_path() -> void:
	var report := PolicyType.filter_branches(Fixtures.courier_one_path())
	_expect(
		(report["branches"] as Array).is_empty(),
		"The one-path courier job grew branches out of nowhere."
	)
	_expect(bool(report["single_path"]), "A one-path courier job was not reported as single path.")
	_expect(
		(report["dropped"] as Array).is_empty(),
		"The courier job dropped options it never had."
	)


## Vertical example 2: a real decision survives intact.
func _test_justified_investigation_keeps_both_options() -> void:
	var report := PolicyType.filter_branches(
		Fixtures.investigation_one_choice(),
		{"known_fact_ids": ["fact.claim_denied", "fact.office_pays_finders"]}
	)
	var branches: Array = report["branches"]
	_expect(branches.size() == 2, "A justified two-option decision lost an option.")
	_expect(not bool(report["single_path"]), "A genuine decision was reported as single path.")
	var ids: Array[String] = []
	for branch in branches:
		ids.append(str((branch as Dictionary).get("id", "")))
	_expect("branch.return_log" in ids, "The honest option was dropped.")
	_expect("branch.sell_log" in ids, "The self-interested option was dropped.")


## Vertical example 3: the menu filler is removed, and what is left is a valid
## quest -- NOT a generation failure and NOT a prompt to invent a replacement.
func _test_unjustified_option_is_removed() -> void:
	var report := PolicyType.filter_branches(
		Fixtures.investigation_unjustified_option(),
		{"known_fact_ids": ["fact.claim_denied", "fact.office_pays_finders"]}
	)
	var branches: Array = report["branches"]
	var ids: Array[String] = []
	for branch in branches:
		ids.append(str((branch as Dictionary).get("id", "")))
	_expect(
		"branch.hand_over_quietly" not in ids,
		"An option with no grounded motive was published."
	)
	_expect(branches.size() == 2, "Removing the filler option damaged the real ones.")
	var dropped_reasons: Array[String] = []
	for entry in (report["dropped"] as Array):
		dropped_reasons.append(str((entry as Dictionary).get("reason", "")))
	_expect(
		PolicyType.DROP_NO_MOTIVE in dropped_reasons,
		"The filler option was dropped without recording why."
	)


func _test_equivalent_buttons_collapse() -> void:
	var contract := Fixtures.investigation_one_choice()
	var branches: Array = contract["branch_contracts"]
	# Same action, same outcome, same effects, different label. One button.
	var clone: Dictionary = (branches[0] as Dictionary).duplicate(true)
	clone["id"] = "branch.return_log_but_politely"
	branches.append(clone)
	contract["branch_contracts"] = branches
	var report := PolicyType.filter_branches(contract)
	_expect(
		(report["branches"] as Array).size() == 2,
		"Two buttons doing exactly the same thing were both published."
	)
	var reasons: Array[String] = []
	for entry in (report["dropped"] as Array):
		reasons.append(str((entry as Dictionary).get("reason", "")))
	_expect(
		PolicyType.DROP_EQUIVALENT in reasons,
		"The duplicate button was not reported as equivalent."
	)


func _test_ineligible_and_unsupported_branches_drop() -> void:
	var contract := Fixtures.investigation_one_choice()
	var unsupported := PolicyType.filter_branches(
		contract,
		{"supported_action_ids": ["action.deliver_evidence.requester"]}
	)
	_expect(
		(unsupported["branches"] as Array).size() == 1,
		"A branch whose action this build cannot execute was published."
	)
	var ineligible := PolicyType.filter_branches(
		contract,
		{"satisfied_predicates": ["evidence.something_else"]}
	)
	_expect(
		(ineligible["branches"] as Array).is_empty(),
		"Branches were published while their eligibility predicates were unmet."
	)
	# The player cannot pick what they have not been told about.
	var uninformed := PolicyType.filter_branches(
		contract,
		{"known_fact_ids": ["fact.convoy_lost"]}
	)
	var ids: Array[String] = []
	for branch in (uninformed["branches"] as Array):
		ids.append(str((branch as Dictionary).get("id", "")))
	_expect(
		"branch.sell_log" not in ids,
		"An option was offered that the player had no information to understand."
	)


## The failure Abe named directly: the same why/risk/connection menu on every
## single mission. Run through the REAL plan builder, not the policy alone.
func _test_no_mandatory_question_trio() -> void:
	var plan := PlanType.build_plan(
		_mission_plan_for(Fixtures.courier_one_path()),
		[],
		{"respect": 0},
		{"can_accept": true, "can_decline": true}
	)
	var ids: Array = plan["intent_ids"]
	_expect(
		PlanType.INTENT_ASK_RISK not in ids,
		"A risk question appeared on a job with no recorded risk."
	)
	_expect(
		PlanType.INTENT_ASK_CONNECTION not in ids,
		"A connection question appeared with no known connection."
	)
	_expect(
		PlanType.INTENT_ACCEPT_STANDARD in ids and PlanType.INTENT_DECLINE in ids,
		"Filtering questions wrongly removed the accept/decline controls."
	)
	_expect(bool(plan["single_path"]), "The courier plan was not reported as single path.")


func _test_risk_question_needs_a_recorded_risk() -> void:
	var contract := Fixtures.courier_one_path()
	var source := _mission_plan_for(contract)
	source["objective_type"] = "KILL_SHIPS"
	var without_facts := PlanType.build_plan(source, [], {}, {})
	_expect(
		PlanType.INTENT_ASK_RISK in (without_facts["intent_ids"] as Array),
		"A combat objective is a supported risk and its question was removed."
	)
	# ...and a recorded risk fact justifies it on a non-combat job too.
	contract["facts"]["fact.yard_disputed"] = {
		"text": "Two crews claim the same berth and the handover has turned physical twice.",
		"visibility": "public",
		"kind": "risk",
	}
	var courier_source := _mission_plan_for(contract)
	var with_fact := PlanType.build_plan(courier_source, [], {}, {})
	_expect(
		PlanType.INTENT_ASK_RISK in (with_fact["intent_ids"] as Array),
		"A recorded risk fact did not enable the risk question."
	)


## If the opening already said it, asking again only produces a restatement.
func _test_question_dropped_when_opening_already_answers_it() -> void:
	var contract := Fixtures.courier_one_path()
	var source := _mission_plan_for(contract)
	source["opening_text"] = (
		"The yard's number two transfer pump seized four days ago. "
		+ "The only spare coupling in the system is sitting in primary station bond, "
		+ "and Marn Dable signs for yard parts and can fit the coupling himself."
	)
	var plan := PlanType.build_plan(source, [], {}, {})
	_expect(
		PlanType.INTENT_ASK_WHY not in (plan["intent_ids"] as Array),
		"A 'why does this matter' button survived an opening that already answered it."
	)
	var dropped_reasons: Array[String] = []
	for entry in (plan["policy_dropped"] as Array):
		dropped_reasons.append(str((entry as Dictionary).get("reason", "")))
	_expect(
		PolicyType.DROP_NOTHING_TO_ADD in dropped_reasons,
		"The redundant question was dropped without recording why."
	)
	# The same plan with a terse opening keeps the question.
	source["opening_text"] = "Run this out to the yard for me."
	var terse := PlanType.build_plan(source, [], {}, {})
	_expect(
		PlanType.INTENT_ASK_WHY in (terse["intent_ids"] as Array),
		"A question with real explanation left to give was removed."
	)


## Existing saved offers carry no causal contract. They must keep the exact menu
## they were published with -- a later policy must not silently remove a
## resolution the player was already promised.
func _test_plan_without_contract_is_unchanged() -> void:
	var legacy := {
		"title": "Legacy Job",
		"objective_type": "KILL_SHIPS",
		"public_because": "The lane has gone quiet and nobody will say why.",
		"stake": "The convoy schedule collapses.",
		"cause_id": "cause.legacy.combat",
		"story_thread_id": "thread.legacy",
	}
	var plan := PlanType.build_plan(legacy, [], {"respect": 0}, {})
	var ids: Array = plan["intent_ids"]
	for expected in [
		PlanType.INTENT_ASK_WHY,
		PlanType.INTENT_ASK_RISK,
		PlanType.INTENT_ASK_CONNECTION,
		PlanType.INTENT_ACCEPT_STANDARD,
		PlanType.INTENT_DECLINE,
	]:
		_expect(
			expected in ids,
			"Legacy offer without a causal contract lost its '%s' option." % expected
		)
	_expect(
		(plan["policy_dropped"] as Array).is_empty(),
		"A legacy offer reported policy drops it should not have been subject to."
	)


func _mission_plan_for(contract: Dictionary) -> Dictionary:
	var objective: Dictionary = contract.get("objective_binding", {})
	return {
		"title": "Fixture Job",
		"objective_type": str(objective.get("type", "")),
		"objective_summary": "Fixture objective",
		"reward_credits": int(objective.get("reward_credits", 0)),
		"public_because": "Recorded in the causal contract.",
		"stake": "Recorded in the causal contract.",
		"cause_id": str(contract.get("triggering_event_id", "")),
		"causal_contract": contract,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
