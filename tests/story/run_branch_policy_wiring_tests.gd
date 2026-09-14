extends SceneTree

## Proves the choice policy has an actual gameplay consumer.
##
## Before this, surviving branches were computed and stored as `policy_branches`
## and nothing ever rendered or executed them. The chain under test is:
##   contract -> policy -> plan intents -> controller choices -> terminal action.

const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")
const ControllerType := preload("res://scripts/story/MissionConversationController.gd")
const PolicyType := preload("res://scripts/story/QuestChoicePolicy.gd")
const Fixtures := preload("res://tests/fixtures/QuestContractFixtures.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_surviving_branches_become_selectable_actions()
	_test_dropped_branch_never_becomes_an_action()
	_test_single_path_does_not_render_a_one_item_menu()
	_test_branch_selection_carries_an_executable_action()
	_test_ineligible_branch_is_explained_not_removed()
	_test_unknown_eligibility_does_not_revoke_an_option()

	if _failures.is_empty():
		print("[PASS] Branch policy wiring tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _plan_for(contract: Dictionary, mechanical: Dictionary = {}) -> Dictionary:
	var objective: Dictionary = contract.get("objective_binding", {})
	var source := {
		"title": "Fixture Job",
		"objective_type": str(objective.get("type", "")),
		"objective_summary": "Fixture objective",
		"reward_credits": int(objective.get("reward_credits", 0)),
		"public_because": "Recorded in the causal contract.",
		"cause_id": str(contract.get("triggering_event_id", "")),
		"causal_contract": contract,
	}
	var merged := {"can_accept": true, "can_decline": true}
	merged.merge(mechanical, true)
	return PlanType.build_plan(source, [], {"respect": 0}, merged)


func _intent_ids(plan: Dictionary) -> Array:
	return plan.get("intent_ids", [])


func _all_rendered_intent_ids(state: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for choice in (state.get("choices", []) as Array):
		ids.append(str((choice as Dictionary).get("intent_id", "")))
	# Open the full options screen too; the opening screen is deliberately short.
	var opened := ControllerType.select_intent(state.get("state", {}), ControllerType.NAV_MORE_OPTIONS)
	for choice in (opened.get("choices", []) as Array):
		var opened_id := str((choice as Dictionary).get("intent_id", ""))
		if opened_id not in ids:
			ids.append(opened_id)
	return ids


func _test_surviving_branches_become_selectable_actions() -> void:
	var plan := _plan_for(
		Fixtures.investigation_one_choice(),
		{"known_fact_ids": ["fact.claim_denied", "fact.office_pays_finders"]}
	)
	var ids: Array = _intent_ids(plan)
	_expect(
		"branch.branch.return_log" in ids,
		"A surviving branch did not become a selectable action: %s" % str(ids)
	)
	_expect(
		"branch.branch.sell_log" in ids,
		"The second surviving branch did not become a selectable action: %s" % str(ids)
	)
	var state := ControllerType.start(plan, {"opening": "Four hulls went quiet."})
	var rendered := _all_rendered_intent_ids(state)
	for expected in ["branch.branch.return_log", "branch.branch.sell_log"]:
		_expect(
			expected in rendered,
			"The controller never rendered '%s'." % expected
		)


## The menu filler from fixture 3 must not reach the player as a button.
func _test_dropped_branch_never_becomes_an_action() -> void:
	var plan := _plan_for(
		Fixtures.investigation_unjustified_option(),
		{"known_fact_ids": ["fact.claim_denied", "fact.office_pays_finders"]}
	)
	var ids: Array = _intent_ids(plan)
	_expect(
		"branch.branch.hand_over_quietly" not in ids,
		"An option the policy dropped was rendered anyway: %s" % str(ids)
	)
	_expect(
		"branch.branch.return_log" in ids and "branch.branch.sell_log" in ids,
		"Removing the filler option damaged the real ones."
	)


## One completion path must not look like a decision.
func _test_single_path_does_not_render_a_one_item_menu() -> void:
	var plan := _plan_for(Fixtures.courier_one_path())
	for id in _intent_ids(plan):
		_expect(
			not str(id).begins_with("branch."),
			"A one-path courier job rendered a branch menu: %s" % str(id)
		)
	_expect(bool(plan["single_path"]), "The courier plan was not reported as single path.")

	# A contract with exactly ONE surviving branch also renders no menu -- that
	# branch is simply how the job ends.
	var one_branch := Fixtures.investigation_one_choice()
	var branches: Array = one_branch["branch_contracts"]
	one_branch["branch_contracts"] = [branches[0]]
	var single := _plan_for(one_branch, {"known_fact_ids": ["fact.claim_denied"]})
	for single_id in _intent_ids(single):
		_expect(
			not str(single_id).begins_with("branch."),
			"A single surviving branch was rendered as a one-item menu: %s" % str(single_id)
		)


func _test_branch_selection_carries_an_executable_action() -> void:
	var plan := _plan_for(
		Fixtures.investigation_one_choice(),
		{"known_fact_ids": ["fact.claim_denied", "fact.office_pays_finders"]}
	)
	var state := ControllerType.start(plan, {"opening": "Four hulls went quiet."})
	var chosen := ControllerType.select_intent(state.get("state", {}), "branch.branch.sell_log")
	_expect(bool(chosen.get("complete", false)), "Choosing a branch did not complete the conversation.")
	_expect(
		str(chosen.get("selected_branch_id", "")) == "branch.sell_log",
		"The chosen branch id was not carried forward."
	)
	var terminal: Dictionary = chosen.get("terminal_choice", {})
	_expect(
		str(terminal.get("action_id", "")) == "action.deliver_evidence.claims_office",
		"The branch committed no executable action: %s" % str(terminal)
	)
	_expect(
		"desire_setback.desire.a1.f1" in (terminal.get("effect_ids", []) as Array),
		"The branch carried no effects to apply."
	)
	_expect(
		str(terminal.get("outcome_id", "")) == "outcome.log_sold",
		"The branch recorded no outcome."
	)


## An option already shown to the player must be EXPLAINED when it becomes
## unavailable, never silently withdrawn.
func _test_ineligible_branch_is_explained_not_removed() -> void:
	var plan := _plan_for(
		Fixtures.investigation_one_choice(),
		{"known_fact_ids": ["fact.claim_denied", "fact.office_pays_finders"]}
	)
	# Evidence has NOT been recovered, so neither branch is eligible yet.
	var state := ControllerType.start(
		plan,
		{"opening": "Four hulls went quiet."},
		{"satisfied_predicates": ["some.other.thing"]}
	)
	var attempted := ControllerType.select_intent(state.get("state", {}), "branch.branch.return_log")
	_expect(
		str(attempted.get("mode", "")) == "unavailable",
		"An ineligible branch was executed anyway: mode=%s" % str(attempted.get("mode", ""))
	)
	_expect(
		not bool(attempted.get("complete", false)),
		"An unavailable option dead-ended the conversation instead of leaving it open."
	)
	_expect(
		not str(attempted.get("unavailable_reason", "")).is_empty(),
		"The unavailable option gave the player no reason."
	)
	_expect(
		str(attempted.get("unavailable_predicate", "")) == "evidence.flight_log_recovered",
		"The explanation did not name what is still missing."
	)
	# Once the evidence exists, the same click commits.
	var ready := ControllerType.start(
		plan,
		{"opening": "Four hulls went quiet."},
		{"satisfied_predicates": ["evidence.flight_log_recovered"]}
	)
	var committed := ControllerType.select_intent(ready.get("state", {}), "branch.branch.return_log")
	_expect(
		bool(committed.get("complete", false)),
		"An eligible branch was still refused."
	)


## Missing information is not the same as a failed predicate. An empty snapshot
## must not revoke an option the player was promised.
func _test_unknown_eligibility_does_not_revoke_an_option() -> void:
	var intent := {
		"id": "branch.branch.return_log",
		"kind": "terminal",
		"branch_id": "branch.return_log",
		"action_id": "action.deliver_evidence.requester",
		"eligibility_predicates": ["evidence.flight_log_recovered"],
	}
	var unknown := PlanType.check_branch_eligibility(intent, {})
	_expect(
		bool(unknown.get("eligible", false)),
		"An unknown world snapshot revoked a promised option."
	)
	var refused := PlanType.check_branch_eligibility(
		intent, {"satisfied_predicates": ["something.else"]}
	)
	_expect(
		not bool(refused.get("eligible", true)),
		"A genuinely unmet predicate was allowed through."
	)
	# A branch with no predicates is always eligible.
	var unconditional := PlanType.check_branch_eligibility(
		{"id": "branch.x", "action_id": "action.x"},
		{"satisfied_predicates": ["anything"]}
	)
	_expect(
		bool(unconditional.get("eligible", false)),
		"A branch with no predicates was refused."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
