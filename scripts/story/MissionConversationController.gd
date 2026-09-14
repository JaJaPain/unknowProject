class_name MissionConversationController
extends RefCounted

const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")

const NAV_MORE_OPTIONS := "__more_options"


static func start(
	conversation_plan: Dictionary,
	bundle: Dictionary,
	mechanical: Dictionary = {}
) -> Dictionary:
	var state := {
		"conversation_plan": conversation_plan.duplicate(true),
		"bundle": bundle.duplicate(true),
		# What is currently true, for click-time eligibility rechecks. Empty
		# means unknown, and unknown never revokes a promised option.
		"mechanical": mechanical.duplicate(true),
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
	if clean_intent_id == NAV_MORE_OPTIONS:
		next_state["mode"] = "options"
		next_state["current_intent_id"] = clean_intent_id
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
	# Re-check a branch option at CLICK time. The world moves between rendering an
	# option and choosing it. An option that has become unavailable is EXPLAINED,
	# not silently dropped: the player was already shown it, and a promised
	# resolution disappearing without a word reads as a bug.
	var eligibility := PlanType.check_branch_eligibility(
		intent, next_state.get("mechanical", {})
	)
	if not bool(eligibility.get("eligible", true)):
		next_state["mode"] = "unavailable"
		next_state["current_intent_id"] = clean_intent_id
		next_state["unavailable_reason"] = str(eligibility.get("reason", ""))
		next_state["unavailable_predicate"] = str(eligibility.get("missing_predicate", ""))
		# Deliberately NOT complete: the conversation stays open so the player
		# can pick something else instead of being dead-ended.
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
	# A branch terminal carries the executable action forward. Without this the
	# policy's surviving branch would render as a button that commits nothing.
	var branch_id := str(intent.get("branch_id", "")).strip_edges()
	if not branch_id.is_empty():
		next_state["selected_branch_id"] = branch_id
		next_state["selected_action_id"] = str(intent.get("action_id", ""))
		var terminal: Dictionary = next_state["terminal_choice"]
		terminal["branch_id"] = branch_id
		terminal["action_id"] = str(intent.get("action_id", ""))
		terminal["effect_ids"] = intent.get("effect_ids", [])
		terminal["outcome_id"] = str(intent.get("outcome_id", ""))
		next_state["terminal_choice"] = terminal
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
	elif mode == "options":
		text = "What do you want to ask or change?"
	elif mode == "invalid":
		text = "That response is unavailable."
	elif mode == "unavailable":
		# Explained, not silently removed. The player was already shown this.
		text = "That is not possible yet."
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
		# Branch execution and the unavailability explanation must be readable
		# from the SCREEN, not only from the internal state, or a UI consumer
		# would have to reach into state to find out what it just committed.
		"selected_branch_id": str(state.get("selected_branch_id", "")),
		"selected_action_id": str(state.get("selected_action_id", "")),
		"unavailable_reason": str(state.get("unavailable_reason", "")),
		"unavailable_predicate": str(state.get("unavailable_predicate", "")),
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
	if str(state.get("mode", "opening")) == "opening":
		return _opening_choices(plan, bundle)
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


static func _opening_choices(
	plan: Dictionary,
	bundle: Dictionary
) -> Array[Dictionary]:
	var all_choices := _all_unasked_choices(plan, bundle, [])
	var choices: Array[Dictionary] = []
	var primary_question := _first_choice_of_kind(all_choices, "question")
	if not primary_question.is_empty():
		choices.append(primary_question)
	var accept := _choice_by_intent_id(all_choices, PlanType.INTENT_ACCEPT_STANDARD)
	if not accept.is_empty():
		choices.append(accept)
	var decline := _choice_by_intent_id(all_choices, PlanType.INTENT_DECLINE)
	if not decline.is_empty():
		choices.append(decline)
	if all_choices.size() > choices.size():
		choices.append({
			"intent_id": NAV_MORE_OPTIONS,
			"kind": "navigation",
			"text": "Terms / other questions",
			"choice_id": "",
		})
	return choices


static func _all_unasked_choices(
	plan: Dictionary,
	bundle: Dictionary,
	asked: Array
) -> Array[Dictionary]:
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


static func _first_choice_of_kind(
	choices: Array[Dictionary],
	kind: String
) -> Dictionary:
	for choice in choices:
		if str(choice.get("kind", "")) == kind:
			return choice
	return {}


static func _choice_by_intent_id(
	choices: Array[Dictionary],
	intent_id: String
) -> Dictionary:
	for choice in choices:
		if str(choice.get("intent_id", "")) == intent_id:
			return choice
	return {}


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
