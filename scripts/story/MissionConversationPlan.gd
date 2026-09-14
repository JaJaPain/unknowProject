class_name MissionConversationPlan
extends RefCounted

const QuestChoicePolicyType := preload("res://scripts/story/QuestChoicePolicy.gd")
const QuestCausalContractType := preload(
	"res://scripts/domain/QuestCausalContract.gd"
)

const INTENT_CLARIFY_TERM := "clarify_term"
const INTENT_ASK_WHY := "ask_why"
const INTENT_ASK_RISK := "ask_risk"
const INTENT_ASK_CONNECTION := "ask_connection"
const INTENT_ACCEPT_STANDARD := "accept_standard"
const INTENT_REQUEST_ADVANCE := "request_advance"
const INTENT_REQUEST_HAZARD_PAY := "request_hazard_pay"
const INTENT_DECLINE := "decline"
const INTENT_INFORMED_FOLLOWUP := "informed_followup"

const QUESTION_INTENTS := [
	INTENT_CLARIFY_TERM,
	INTENT_ASK_WHY,
	INTENT_ASK_RISK,
	INTENT_ASK_CONNECTION,
	INTENT_INFORMED_FOLLOWUP,
]

const TERMINAL_INTENTS := [
	INTENT_ACCEPT_STANDARD,
	INTENT_REQUEST_ADVANCE,
	INTENT_REQUEST_HAZARD_PAY,
	INTENT_DECLINE,
]


static func intent_registry() -> Dictionary:
	return {
		INTENT_CLARIFY_TERM: {
			"id": INTENT_CLARIFY_TERM,
			"kind": "question",
			"label": "Clarify the term",
		},
		INTENT_ASK_WHY: {
			"id": INTENT_ASK_WHY,
			"kind": "question",
			"label": "Ask why this matters",
		},
		INTENT_ASK_RISK: {
			"id": INTENT_ASK_RISK,
			"kind": "question",
			"label": "Ask about the risk",
		},
		INTENT_ASK_CONNECTION: {
			"id": INTENT_ASK_CONNECTION,
			"kind": "question",
			"label": "Ask how this connects",
		},
		INTENT_ACCEPT_STANDARD: {
			"id": INTENT_ACCEPT_STANDARD,
			"kind": "terminal",
			"label": "Accept the contract",
		},
		INTENT_REQUEST_ADVANCE: {
			"id": INTENT_REQUEST_ADVANCE,
			"kind": "terminal",
			"label": "Request an advance",
		},
		INTENT_REQUEST_HAZARD_PAY: {
			"id": INTENT_REQUEST_HAZARD_PAY,
			"kind": "terminal",
			"label": "Request hazard pay",
		},
		INTENT_DECLINE: {
			"id": INTENT_DECLINE,
			"kind": "terminal",
			"label": "Decline",
		},
		INTENT_INFORMED_FOLLOWUP: {
			"id": INTENT_INFORMED_FOLLOWUP,
			"kind": "question",
			"label": "Ask an informed follow-up",
		},
	}


static func build_plan(
	mission_plan: Dictionary,
	knowledge_candidates: Array = [],
	relationship: Dictionary = {},
	mechanical: Dictionary = {}
) -> Dictionary:
	var intents: Array[Dictionary] = []
	var used: Dictionary = {}
	for question in _question_intents(mission_plan, knowledge_candidates):
		_add_intent(intents, used, question)
	for terminal in _terminal_intents(mission_plan, relationship, mechanical):
		_add_intent(intents, used, terminal)
	var policy := _apply_choice_policy(intents, mission_plan, mechanical)
	return {
		"ok": true,
		"intents": policy["intents"],
		"intent_ids": _intent_ids(policy["intents"]),
		"policy_dropped": policy["dropped"],
		"policy_branches": policy["branches"],
		"single_path": policy["single_path"],
	}


## Abe's rule, enforced at the one place every offer builder passes through: a
## question only survives if it can add something, and a branch only survives if
## it is supported, motivated, understandable and genuinely different.
##
## Without a causal contract there is nothing to judge against, so the plan is
## returned untouched -- existing saved offers keep exactly the menu they had.
static func _apply_choice_policy(
	intents: Array[Dictionary],
	mission_plan: Dictionary,
	mechanical: Dictionary
) -> Dictionary:
	var contract: Variant = mission_plan.get("causal_contract", {})
	if not QuestCausalContractType.is_present(contract):
		return {
			"intents": intents,
			"dropped": [],
			"branches": [],
			"single_path": true,
		}
	var candidate_ids: Array[String] = []
	for intent in intents:
		if str(intent.get("kind", "")) == "question":
			candidate_ids.append(str(intent.get("id", "")))
	var question_report := QuestChoicePolicyType.filter_questions(
		contract,
		candidate_ids,
		{
			"opening_text": str(mission_plan.get("opening_text", "")),
			"has_supported_risk": _has_risk(mission_plan),
			"has_known_connection": bool(mechanical.get("has_known_connection", false)),
		}
	)
	var branch_report := QuestChoicePolicyType.filter_branches(
		contract,
		{
			"supported_action_ids": mechanical.get("supported_action_ids", []),
			"satisfied_predicates": mechanical.get("satisfied_predicates", []),
			"known_fact_ids": mechanical.get("known_fact_ids", []),
		}
	)
	var kept_question_ids: Array = question_report.get("intent_ids", [])
	var surviving: Array[Dictionary] = []
	for intent in intents:
		if str(intent.get("kind", "")) != "question":
			surviving.append(intent)
			continue
		if str(intent.get("id", "")) in kept_question_ids:
			surviving.append(intent)
	var dropped: Array = (question_report.get("dropped", []) as Array).duplicate(true)
	for entry in (branch_report.get("dropped", []) as Array):
		dropped.append(entry)
	# A surviving branch is a real thing the player can DO, so it becomes a
	# selectable terminal intent. Branches the policy dropped never become one at
	# all -- that is the whole point of dropping them. Previously the surviving
	# set was computed, stored as `policy_branches`, and never rendered, so the
	# policy had no gameplay consumer.
	var branches: Array = branch_report.get("branches", [])
	_append_branch_intents(surviving, branches)
	return {
		"intents": surviving,
		"dropped": dropped,
		"branches": branches,
		"single_path": bool(branch_report.get("single_path", true)),
	}


## Turn surviving branch contracts into terminal intents the controller renders.
##
## A single surviving branch is NOT a choice -- it is simply how the quest ends,
## and it stays folded into the ordinary accept path rather than becoming a
## one-item menu. That is Abe's rule enforced at render time, not just at policy
## time: one completion path must not look like a decision.
static func _append_branch_intents(
	intents: Array[Dictionary],
	branches: Array
) -> void:
	if branches.size() < 2:
		return
	for raw_branch in branches:
		if not (raw_branch is Dictionary):
			continue
		var branch: Dictionary = raw_branch
		var branch_id := str(branch.get("id", "")).strip_edges()
		var action_id := str(branch.get("action_id", "")).strip_edges()
		if branch_id.is_empty() or action_id.is_empty():
			continue
		intents.append({
			"id": "branch.%s" % branch_id,
			"kind": "terminal",
			"label": str(branch.get("label", _branch_label(branch))),
			"fact_ids": [],
			"branch_id": branch_id,
			"action_id": action_id,
			"eligibility_predicates": branch.get("eligibility_predicates", []),
			"effect_ids": branch.get("effect_ids", []),
			"outcome_id": str(branch.get("outcome_id", "")),
			"consequence": {
				"mission_action": "branch",
				"branch_id": branch_id,
				"action_id": action_id,
				"effect_ids": branch.get("effect_ids", []),
				"outcome_id": str(branch.get("outcome_id", "")),
			},
		})


## A readable label from the action when the contract did not supply one. Uses
## the action's own last segment rather than inventing dramatic wording.
static func _branch_label(branch: Dictionary) -> String:
	var action_id := str(branch.get("action_id", ""))
	var segments := action_id.split(".", false)
	if segments.is_empty():
		return "Take this option"
	var tail := str(segments[segments.size() - 1]).replace("_", " ").strip_edges()
	if tail.is_empty():
		return "Take this option"
	return tail.substr(0, 1).to_upper() + tail.substr(1)


## Re-check one branch's eligibility at CLICK time. The world moves between the
## moment an option is rendered and the moment it is chosen.
##
## Returns {eligible, reason}. An ineligible option is explained rather than
## silently removed: the player was already shown it, and a promised resolution
## vanishing without a word reads as a bug.
static func check_branch_eligibility(
	intent: Dictionary,
	mechanical: Dictionary
) -> Dictionary:
	var predicates := QuestChoicePolicyType.branch_predicates(intent)
	if predicates.is_empty():
		return {"eligible": true, "reason": ""}
	var satisfied: Array = mechanical.get("satisfied_predicates", []) \
		if mechanical.get("satisfied_predicates", []) is Array else []
	# An empty snapshot means the caller did not tell us what is true. Unknown is
	# not the same as false: do not revoke a promised option on missing input.
	if satisfied.is_empty():
		return {"eligible": true, "reason": ""}
	for predicate in predicates:
		if predicate not in satisfied:
			return {
				"eligible": false,
				"reason": "not_yet_available",
				"missing_predicate": predicate,
			}
	return {"eligible": true, "reason": ""}


static func _question_intents(
	mission_plan: Dictionary,
	knowledge_candidates: Array
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var grounding := _first_knowledge_candidate(knowledge_candidates, "grounding")
	var deeper := _first_knowledge_candidate(knowledge_candidates, "deeper")
	if not grounding.is_empty():
		result.append(_intent(
			INTENT_CLARIFY_TERM,
			str(grounding.get("label", "What does that mean?")),
			grounding.get("fact_ids", []),
			{
				"source_intent_id": str(grounding.get("intent_id", "")),
				"answer_anchors": _candidate_answer_anchors(grounding),
			}
		))
	elif deeper.is_empty() \
			and _has_any(mission_plan, ["question_fact_ids", "clarify_fact_ids"]):
		result.append(_intent(
			INTENT_CLARIFY_TERM,
			"What needs clarifying?",
			_join_arrays(
				mission_plan.get("question_fact_ids", []),
				mission_plan.get("clarify_fact_ids", [])
			),
			{
				"answer_anchors": _mission_answer_anchors(mission_plan),
			}
		))
	if _has_text(mission_plan, ["public_because", "stake", "cause_id"]):
		result.append(_intent(
			INTENT_ASK_WHY,
			"Why does this matter?",
			_as_string_array(mission_plan.get("offer_fact_ids", [])),
			{
				"answer_anchors": _mission_answer_anchors(mission_plan),
			}
		))
	if _has_risk(mission_plan):
		result.append(_intent(INTENT_ASK_RISK, "What can go wrong?"))
	if _has_text(mission_plan, ["story_thread_id", "story_beat_id", "cause_id"]):
		result.append(_intent(INTENT_ASK_CONNECTION, "How is this connected?"))
	if not deeper.is_empty():
		result.append(_intent(
			INTENT_INFORMED_FOLLOWUP,
			str(deeper.get("label", "What follows from that?")),
			deeper.get("fact_ids", []),
			{
				"source_intent_id": str(deeper.get("intent_id", "")),
				"answer_anchors": _candidate_answer_anchors(deeper),
			}
		))
	return result


static func _terminal_intents(
	mission_plan: Dictionary,
	relationship: Dictionary,
	mechanical: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if bool(mechanical.get("can_accept", true)):
		result.append(_terminal_intent(
			INTENT_ACCEPT_STANDARD,
			"Accept the contract",
			mission_plan,
			relationship,
			mechanical
		))
	if bool(mechanical.get("can_request_advance", false)):
		result.append(_terminal_intent(
			INTENT_REQUEST_ADVANCE,
			"Ask for an advance",
			mission_plan,
			relationship,
			mechanical
		))
	if bool(mechanical.get("can_request_hazard_pay", true)) \
			and _has_risk(mission_plan) \
			and int(relationship.get("respect", 0)) >= -4:
		result.append(_terminal_intent(
			INTENT_REQUEST_HAZARD_PAY,
			"Ask for hazard pay",
			mission_plan,
			relationship,
			mechanical
		))
	if bool(mechanical.get("can_decline", true)):
		result.append(_terminal_intent(
			INTENT_DECLINE,
			"Decline",
			mission_plan,
			relationship,
			mechanical
		))
	return result


static func _terminal_intent(
	intent_id: String,
	label: String,
	mission_plan: Dictionary,
	relationship: Dictionary,
	mechanical: Dictionary
) -> Dictionary:
	return _intent(
		intent_id,
		label,
		[],
		{
			"consequence": _terminal_consequence(
				intent_id,
				mission_plan,
				relationship,
				mechanical
			),
		}
	)


static func _terminal_consequence(
	intent_id: String,
	mission_plan: Dictionary,
	relationship: Dictionary,
	mechanical: Dictionary
) -> Dictionary:
	var base := {
		"mission_action": "accept",
		"credits_immediate": 0,
		"reward_credits_multiplier": 1.0,
		"reputation_change": {},
	}
	match intent_id:
		INTENT_REQUEST_ADVANCE:
			base["credits_immediate"] = int(mechanical.get("advance_credits", 0))
			base["advance_requested"] = true
		INTENT_REQUEST_HAZARD_PAY:
			base["reward_credits_multiplier"] = float(
				mechanical.get("hazard_pay_multiplier", 1.15)
			)
			base["hazard_pay_requested"] = true
		INTENT_DECLINE:
			base["mission_action"] = "decline"
			base["leaves_mission_lane_empty"] = true
			base["relationship_delta"] = int(
				mechanical.get("decline_relationship_delta", -1)
			)
			base["respect_at_decline"] = int(relationship.get("respect", 0))
			base["declined_story_beat_id"] = str(
				mission_plan.get("story_beat_id", "")
			)
		_:
			pass
	return base


static func _intent(
	intent_id: String,
	label: String,
	fact_ids: Array = [],
	extra: Dictionary = {}
) -> Dictionary:
	var registry := intent_registry()
	var base: Dictionary = registry.get(intent_id, {}).duplicate(true)
	base["label"] = label
	base["fact_ids"] = _as_string_array(fact_ids)
	for key in extra.keys():
		base[key] = extra[key]
	return base


static func _add_intent(
	intents: Array[Dictionary],
	used: Dictionary,
	intent: Dictionary
) -> void:
	var intent_id := str(intent.get("id", "")).strip_edges()
	if intent_id.is_empty() or used.has(intent_id):
		return
	used[intent_id] = true
	intents.append(intent)


static func _intent_ids(intents: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for intent in intents:
		ids.append(str(intent.get("id", "")))
	return ids


static func _first_knowledge_candidate(
	knowledge_candidates: Array,
	kind: String
) -> Dictionary:
	for raw_candidate in knowledge_candidates:
		if not (raw_candidate is Dictionary):
			continue
		var candidate: Dictionary = raw_candidate
		if str(candidate.get("kind", "")).strip_edges() == kind:
			return candidate
	return {}


static func _has_any(source: Dictionary, keys: Array) -> bool:
	for key in keys:
		var value: Variant = source.get(key, [])
		if value is Array and not (value as Array).is_empty():
			return true
	return false


static func _has_text(source: Dictionary, keys: Array) -> bool:
	for key in keys:
		if not str(source.get(key, "")).strip_edges().is_empty():
			return true
	return false


static func _has_risk(mission_plan: Dictionary) -> bool:
	if _has_text(mission_plan, ["risk", "risk_text", "tone_pressure"]):
		return true
	# A contract that records an actual hazard justifies the question even on a
	# job whose objective type is not inherently dangerous.
	if QuestChoicePolicyType.contract_records_risk(
		mission_plan.get("causal_contract", {})
	):
		return true
	var objective_type := str(mission_plan.get("objective_type", "")).to_upper()
	if objective_type in ["KILL_SHIPS", "RECOVER_COMBAT_DROP", "TARGET_WITH_COMMS_REVERSAL"]:
		return true
	return int(mission_plan.get("urgency", 0)) >= 4


static func _join_arrays(left: Variant, right: Variant) -> Array:
	var result: Array = []
	if left is Array:
		result.append_array(left as Array)
	if right is Array:
		result.append_array(right as Array)
	return result


static func _as_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item in (value as Array):
		var text := str(item).strip_edges()
		if not text.is_empty() and text not in result:
			result.append(text)
	return result


static func _candidate_answer_anchors(candidate: Dictionary) -> Array[String]:
	var explicit := _as_string_array(candidate.get("answer_anchors", []))
	if not explicit.is_empty():
		return explicit
	var anchors: Array[String] = []
	for key in ["alias", "label"]:
		var text := str(candidate.get(key, "")).strip_edges()
		if not text.is_empty() and text not in anchors:
			anchors.append(text)
	return anchors


static func _mission_answer_anchors(mission_plan: Dictionary) -> Array[String]:
	var anchors: Array[String] = []
	for key in ["public_because", "stake", "risk_text", "risk", "cause_id"]:
		var text := str(mission_plan.get(key, "")).strip_edges()
		if text.is_empty():
			continue
		for piece in text.split(" ", false):
			var clean := str(piece).strip_edges().trim_suffix(".").trim_suffix(",")
			if clean.length() >= 6 and clean.to_lower() not in ["because", "before"]:
				anchors.append(clean)
				break
		if not anchors.is_empty():
			break
	return anchors
