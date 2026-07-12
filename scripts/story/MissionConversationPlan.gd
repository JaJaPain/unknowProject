class_name MissionConversationPlan
extends RefCounted

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
	return {
		"ok": true,
		"intents": intents,
		"intent_ids": _intent_ids(intents),
	}


static func _question_intents(
	mission_plan: Dictionary,
	knowledge_candidates: Array
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var grounding := _first_knowledge_candidate(knowledge_candidates, "grounding")
	if not grounding.is_empty():
		result.append(_intent(
			INTENT_CLARIFY_TERM,
			str(grounding.get("label", "What does that mean?")),
			grounding.get("fact_ids", []),
			{"source_intent_id": str(grounding.get("intent_id", ""))}
		))
	elif _has_any(mission_plan, ["question_fact_ids", "clarify_fact_ids"]):
		result.append(_intent(
			INTENT_CLARIFY_TERM,
			"What needs clarifying?",
			_join_arrays(
				mission_plan.get("question_fact_ids", []),
				mission_plan.get("clarify_fact_ids", [])
			)
		))
	if _has_text(mission_plan, ["public_because", "stake", "cause_id"]):
		result.append(_intent(
			INTENT_ASK_WHY,
			"Why does this matter?",
			_as_string_array(mission_plan.get("offer_fact_ids", []))
		))
	if _has_risk(mission_plan):
		result.append(_intent(INTENT_ASK_RISK, "What can go wrong?"))
	if _has_text(mission_plan, ["story_thread_id", "story_beat_id", "cause_id"]):
		result.append(_intent(INTENT_ASK_CONNECTION, "How is this connected?"))
	var deeper := _first_knowledge_candidate(knowledge_candidates, "deeper")
	if not deeper.is_empty():
		result.append(_intent(
			INTENT_INFORMED_FOLLOWUP,
			str(deeper.get("label", "What follows from that?")),
			deeper.get("fact_ids", []),
			{"source_intent_id": str(deeper.get("intent_id", ""))}
		))
	return result


static func _terminal_intents(
	mission_plan: Dictionary,
	relationship: Dictionary,
	mechanical: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if bool(mechanical.get("can_accept", true)):
		result.append(_intent(INTENT_ACCEPT_STANDARD, "Accept the contract"))
	if bool(mechanical.get("can_request_advance", false)):
		result.append(_intent(INTENT_REQUEST_ADVANCE, "Ask for an advance"))
	if bool(mechanical.get("can_request_hazard_pay", true)) \
			and _has_risk(mission_plan) \
			and int(relationship.get("respect", 0)) >= -4:
		result.append(_intent(INTENT_REQUEST_HAZARD_PAY, "Ask for hazard pay"))
	if bool(mechanical.get("can_decline", true)):
		result.append(_intent(INTENT_DECLINE, "Decline"))
	return result


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
