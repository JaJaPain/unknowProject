class_name MissionConversationController
extends RefCounted

const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")


static func start(
	conversation_plan: Dictionary,
	bundle: Dictionary
) -> Dictionary:
	var state := {
		"conversation_plan": conversation_plan.duplicate(true),
		"bundle": bundle.duplicate(true),
		"asked_intents": [],
		"learned_fact_ids": [],
		"mode": "opening",
		"current_intent_id": "",
		"complete": false,
		"terminal_choice_id": "",
		"terminal_choice": {},
	}
	return _screen(state)


static func select_intent(
	state: Dictionary,
	intent_id: String
) -> Dictionary:
	var next_state := state.duplicate(true)
	var clean_intent_id := intent_id.strip_edges()
	if bool(next_state.get("complete", false)):
		return _screen(next_state)
	var intent := _intent_by_id(
		next_state.get("conversation_plan", {}),
		clean_intent_id
	)
	if intent.is_empty():
		next_state["mode"] = "invalid"
		next_state["current_intent_id"] = clean_intent_id
		return _screen(next_state)
	if str(intent.get("kind", "")) == "question":
		var asked: Array = next_state.get("asked_intents", []).duplicate()
		if clean_intent_id not in asked:
			asked.append(clean_intent_id)
		next_state["asked_intents"] = asked
		next_state["learned_fact_ids"] = _merged_strings(
			next_state.get("learned_fact_ids", []),
			intent.get("fact_ids", [])
		)
		next_state["mode"] = "answer"
		next_state["current_intent_id"] = clean_intent_id
		return _screen(next_state)
	next_state["mode"] = "terminal"
	next_state["current_intent_id"] = clean_intent_id
	next_state["complete"] = true
	next_state["terminal_choice_id"] = _terminal_choice_id(clean_intent_id)
	next_state["terminal_choice"] = _terminal_choice(
		intent,
		next_state.get("bundle", {}),
		next_state
	)
	return _screen(next_state)


static func _screen(state: Dictionary) -> Dictionary:
	var bundle: Dictionary = state.get("bundle", {}) \
		if state.get("bundle", {}) is Dictionary else {}
	var mode := str(state.get("mode", "opening"))
	var current_intent_id := str(state.get("current_intent_id", ""))
	var text := str(bundle.get("opening", "")).strip_edges()
	if mode == "answer":
		text = str(bundle.get("%s_response" % current_intent_id, "")).strip_edges()
	elif mode == "terminal":
		text = str(bundle.get("%s_response" % current_intent_id, "")).strip_edges()
	elif mode == "invalid":
		text = "That response is unavailable."
	var choices := _choices_for_state(state)
	return {
		"ok": true,
		"state": state,
		"mode": mode,
		"text": text,
		"choices": choices,
		"complete": bool(state.get("complete", false)),
		"terminal_choice_id": str(state.get("terminal_choice_id", "")),
		"terminal_choice": state.get("terminal_choice", {}),
		"selected_intent_id": current_intent_id,
	}


static func _choices_for_state(state: Dictionary) -> Array[Dictionary]:
	if bool(state.get("complete", false)):
		return []
	var plan: Dictionary = state.get("conversation_plan", {}) \
		if state.get("conversation_plan", {}) is Dictionary else {}
	var bundle: Dictionary = state.get("bundle", {}) \
		if state.get("bundle", {}) is Dictionary else {}
	var asked: Array = state.get("asked_intents", []) \
		if state.get("asked_intents", []) is Array else []
	var choices: Array[Dictionary] = []
	for intent in _intents(plan):
		var intent_id := str(intent.get("id", ""))
		if intent_id.is_empty():
			continue
		if str(intent.get("kind", "")) == "question" and intent_id in asked:
			continue
		var label := str(
			bundle.get("%s_player" % intent_id, intent.get("label", intent_id))
		).strip_edges()
		if label.is_empty():
			continue
		choices.append({
			"intent_id": intent_id,
			"kind": str(intent.get("kind", "")),
			"text": label,
			"choice_id": _terminal_choice_id(intent_id)
				if str(intent.get("kind", "")) == "terminal" else "",
		})
	return choices


static func _intent_by_id(
	conversation_plan: Dictionary,
	intent_id: String
) -> Dictionary:
	for intent in _intents(conversation_plan):
		if str(intent.get("id", "")) == intent_id:
			return intent
	return {}


static func _intents(conversation_plan: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_intents: Array = conversation_plan.get("intents", []) \
		if conversation_plan.get("intents", []) is Array else []
	for raw_intent in raw_intents:
		if raw_intent is Dictionary:
			result.append((raw_intent as Dictionary).duplicate(true))
	return result


static func _terminal_choice_id(intent_id: String) -> String:
	match intent_id:
		PlanType.INTENT_ACCEPT_STANDARD:
			return "choice.accept_standard"
		PlanType.INTENT_REQUEST_ADVANCE:
			return "choice.request_advance"
		PlanType.INTENT_REQUEST_HAZARD_PAY:
			return "choice.request_hazard_pay"
		PlanType.INTENT_DECLINE:
			return "choice.decline"
		_:
			return ""


static func _terminal_choice(
	intent: Dictionary,
	bundle: Variant,
	state: Dictionary
) -> Dictionary:
	var intent_id := str(intent.get("id", "")).strip_edges()
	var choice_id := _terminal_choice_id(intent_id)
	var bundle_data: Dictionary = {}
	if bundle is Dictionary:
		bundle_data = bundle
	var text := str(
		bundle_data.get("%s_player" % intent_id, intent.get("label", intent_id))
	).strip_edges()
	var consequence: Dictionary = intent.get("consequence", {}) \
		if intent.get("consequence", {}) is Dictionary else {}
	return {
		"choice_id": choice_id,
		"text": text,
		"consequence": consequence.duplicate(true),
		"conversation_intent_id": intent_id,
		"asked_intents": _string_array(state.get("asked_intents", [])),
		"learned_fact_ids": _string_array(state.get("learned_fact_ids", [])),
	}


static func _merged_strings(left: Variant, right: Variant) -> Array[String]:
	var result := _string_array(left)
	for item in _string_array(right):
		if item not in result:
			result.append(item)
	return result


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array):
		return result
	for item in (value as Array):
		var text := str(item).strip_edges()
		if not text.is_empty() and text not in result:
			result.append(text)
	return result
