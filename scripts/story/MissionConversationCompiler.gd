class_name MissionConversationCompiler
extends RefCounted

const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")


## Slicing (plan P4) ────────────────────────────────────────────────────────────
##
## The whole bundle used to be one request: opening plus a player label and a
## response for EVERY intent. One malformed field discarded all of it, including
## the parts that were fine, and the retry paid for the good work again.
##
## A slice is one opening, or up to two intent responses. Slices are validated
## and retained independently, so a failure costs one slice instead of the
## conversation.
const MAX_INTENTS_PER_SLICE := 2

const SLICE_OPENING := "opening"
const SLICE_INTENTS := "intents"


## Break a conversation plan into the slices to request, in priority order. The
## opening comes first because it is what the player sees before anything else --
## if only one slice ever completes, it should be that one.
static func plan_slices(conversation_plan: Dictionary) -> Array[Dictionary]:
	var slices: Array[Dictionary] = []
	slices.append({"kind": SLICE_OPENING, "intent_ids": []})
	var batch: Array[String] = []
	for intent in _intents(conversation_plan):
		var intent_id := str(intent.get("id", "")).strip_edges()
		if intent_id.is_empty():
			continue
		batch.append(intent_id)
		if batch.size() >= MAX_INTENTS_PER_SLICE:
			slices.append({"kind": SLICE_INTENTS, "intent_ids": batch.duplicate()})
			batch.clear()
	if not batch.is_empty():
		slices.append({"kind": SLICE_INTENTS, "intent_ids": batch.duplicate()})
	return slices


## Keys one slice must return.
##
## Note there is NO `*_player` key here. Button labels are machine-owned: they
## come from the code-approved intent list, which already has them. Asking a
## model to restate a label it was handed spends inference to introduce a chance
## of getting it wrong. Legacy full bundles still carry `*_player` and remain
## readable; only new slices drop it.
static func required_output_keys_for_slice(slice: Dictionary) -> Array[String]:
	if str(slice.get("kind", "")) == SLICE_OPENING:
		return ["opening"] as Array[String]
	var keys: Array[String] = []
	for intent_id in slice.get("intent_ids", []):
		var clean := str(intent_id).strip_edges()
		if not clean.is_empty():
			keys.append("%s_response" % clean)
	return keys


## Merge a validated slice result into the bundle assembled so far.
##
## Existing keys are NEVER overwritten: an already-validated slice has passed the
## checks, and a later response has no standing to replace it. That is what makes
## a partial failure cheap -- the good work stays good.
static func merge_slice(bundle: Dictionary, slice_result: Dictionary) -> Dictionary:
	var merged := bundle.duplicate(true)
	for key in slice_result:
		var text := str(slice_result[key]).strip_edges()
		if text.is_empty():
			continue
		if merged.has(key) and not str(merged[key]).strip_edges().is_empty():
			continue
		merged[key] = text
	return merged


## Which required keys are still missing from a partially assembled bundle, so a
## repair asks only for what is actually absent.
static func missing_keys(bundle: Dictionary, conversation_plan: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for key in required_output_keys(conversation_plan):
		# A legacy bundle satisfies a slice key with its own `*_player` sibling
		# present or not; only the response side is required by the new path.
		if str(key).ends_with("_player"):
			continue
		if not bundle.has(key) or str(bundle[key]).strip_edges().is_empty():
			missing.append(str(key))
	return missing


static func required_output_keys(conversation_plan: Dictionary) -> Array[String]:
	var keys: Array[String] = ["opening"]
	var intents: Array = conversation_plan.get("intents", []) \
		if conversation_plan.get("intents", []) is Array else []
	for raw_intent in intents:
		if not (raw_intent is Dictionary):
			continue
		var intent_id := str((raw_intent as Dictionary).get("id", "")).strip_edges()
		if intent_id.is_empty():
			continue
		keys.append("%s_player" % intent_id)
		keys.append("%s_response" % intent_id)
	return keys


static func build_prompt(
	mission_plan: Dictionary,
	speaker_card: Dictionary,
	conversation_plan: Dictionary,
	safe_context: String = ""
) -> String:
	var lines: Array[String] = []
	lines.append("You are writing a complete mission conversation bundle for a space trading game.")
	lines.append("The model writes prose only. Code owns objectives, rewards, facts, consequences, and which choices exist.")
	lines.append("Do not add, remove, rename, reorder, or redefine any intent.")
	lines.append("No narration, no stage directions, PG-13, grounded, dry humor only if it fits the speaker.")
	lines.append("")
	lines.append("MISSION VALUES (use exactly; no placeholders):")
	lines.append("- Title: %s" % _text(mission_plan, "title", "Untitled Contract"))
	lines.append("- Objective: %s" % _text(mission_plan, "objective_summary", _objective_summary(mission_plan)))
	lines.append("- Reward: %d SC" % int(mission_plan.get("reward_credits", 0)))
	var because := _text(mission_plan, "public_because", "")
	if not because.is_empty():
		lines.append("- Player-safe reason: %s" % because)
	var stake := _text(mission_plan, "stake", "")
	if not stake.is_empty():
		lines.append("- Stake: %s" % stake)
	var risk := _text(mission_plan, "risk_text", _text(mission_plan, "risk", ""))
	if not risk.is_empty():
		lines.append("- Risk: %s" % risk)
	lines.append("")
	lines.append("SPEAKER:")
	lines.append("- Name: %s" % _text(speaker_card, "name", "Local Contact"))
	lines.append("- Role: %s" % _text(speaker_card, "role", "mission giver"))
	var persona: Dictionary = speaker_card.get("persona", {}) \
		if speaker_card.get("persona", {}) is Dictionary else {}
	if not persona.is_empty():
		lines.append("- Drive: %s" % _text(persona, "core_drive", ""))
		lines.append("- Pressure tell: %s" % _text(persona, "pressure_tell", ""))
		lines.append("- Humor mechanism: %s" % _text(persona, "humor_mechanism", ""))
	var voice_rules: Dictionary = speaker_card.get("voice_rules", {}) \
		if speaker_card.get("voice_rules", {}) is Dictionary else {}
	if not voice_rules.is_empty():
		lines.append("- Sentence shape: %s" % _text(voice_rules, "sentence_shape", ""))
		lines.append("- Address rule: %s" % _text(voice_rules, "address_rule", ""))
		lines.append("- Banned tics: %s" % ", ".join(_string_array(voice_rules.get("banned_tics", []))))
	if not safe_context.strip_edges().is_empty():
		lines.append("")
		lines.append("SAFE CONTEXT:")
		lines.append(safe_context.strip_edges())
	lines.append("")
	lines.append("CODE-APPROVED INTENTS:")
	for intent in _intents(conversation_plan):
		var anchors := _string_array(intent.get("answer_anchors", []))
		var anchor_note := ""
		if not anchors.is_empty():
			anchor_note = " Answer must include one of: %s." % ", ".join(anchors)
		lines.append(
			"- %s (%s): %s%s" % [
				str(intent.get("id", "")),
				str(intent.get("kind", "")),
				str(intent.get("label", "")),
				anchor_note,
			]
		)
	lines.append("")
	lines.append("OUTPUT:")
	lines.append("Return only flat JSON with exactly these string keys:")
	lines.append(JSON.stringify(required_output_keys(conversation_plan)))
	lines.append("Each *_player value is what the pilot button says. Each *_response value is the speaker answer or terminal acknowledgement.")
	lines.append("Answers may use only the mission values, speaker card, safe context, and fact IDs attached to that intent.")
	return "\n".join(lines)


## Prompt for ONE slice. Reuses the full prompt's context (speaker card, safe
## context, approved intents) and changes only what is asked for at the end,
## so a sliced conversation cannot drift in voice from a whole one.
static func build_slice_prompt(
	mission_plan: Dictionary,
	speaker_card: Dictionary,
	conversation_plan: Dictionary,
	slice: Dictionary,
	safe_context: String = ""
) -> String:
	var full := build_prompt(mission_plan, speaker_card, conversation_plan, safe_context)
	# Replace the OUTPUT section rather than appending a second one: two sets of
	# instructions is how a model ends up answering the wrong question.
	var cut := full.find("OUTPUT:")
	var head := full.substr(0, cut) if cut >= 0 else full + "
"
	var keys := required_output_keys_for_slice(slice)
	var lines: Array[String] = [head.strip_edges(), "", "OUTPUT:"]
	lines.append("Return only flat JSON with exactly these string keys:")
	lines.append(JSON.stringify(keys))
	if str(slice.get("kind", "")) == SLICE_OPENING:
		lines.append("Write only the opening. Do not write answers to any intent.")
	else:
		lines.append(
			"Write only the answers for these intents: %s."
				% ", ".join(slice.get("intent_ids", []))
		)
		# Said explicitly because the button labels are already decided and the
		# model has just been shown them in CODE-APPROVED INTENTS.
		lines.append("Do not write the pilot button labels. Code owns those.")
	lines.append("Answers may use only the mission values, speaker card, safe context, and fact IDs attached to that intent.")
	return "
".join(lines)


static func fallback_bundle(
	mission_plan: Dictionary,
	conversation_plan: Dictionary,
	speaker_card: Dictionary = {}
) -> Dictionary:
	var speaker_name := _text(speaker_card, "name", "Local Contact")
	var title := _text(mission_plan, "title", "Untitled Contract")
	var objective := _text(
		mission_plan,
		"objective_summary",
		_objective_summary(mission_plan)
	)
	var opening_parts: Array[String] = [
		"%s has a contract: %s." % [speaker_name, title],
		objective,
	]
	var because := _text(mission_plan, "public_because", "")
	if not because.is_empty():
		opening_parts.append(because)
	var stake := _text(mission_plan, "stake", "")
	if not stake.is_empty():
		opening_parts.append(stake)
	var relationship := _text(
		mission_plan,
		"relationship_tier",
		_text(speaker_card, "relationship_tier", "")
	)
	if not relationship.is_empty():
		opening_parts.append("Terms stay %s." % relationship)
	var bundle := {
		"opening": " ".join(opening_parts),
	}
	for intent in _intents(conversation_plan):
		var intent_id := str(intent.get("id", ""))
		var label := str(intent.get("label", intent_id))
		bundle["%s_player" % intent_id] = label
		bundle["%s_response" % intent_id] = _fallback_response_for_intent(
			intent,
			mission_plan
		)
	return bundle


static func _fallback_response_for_intent(
	intent: Dictionary,
	mission_plan: Dictionary
) -> String:
	var intent_id := str(intent.get("id", ""))
	var response := _fallback_response(intent_id, mission_plan)
	var anchors := _string_array(intent.get("answer_anchors", []))
	if anchors.is_empty() or _contains_any(response, anchors):
		return response
	return "%s %s" % [anchors[0], response]


static func parse_bundle(
	inner_json_text: String,
	conversation_plan: Dictionary
) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(inner_json_text.strip_edges()) != OK:
		return {"ok": false, "reason": "parse_failed", "bundle": {}}
	var data: Variant = parser.get_data()
	if not (data is Dictionary):
		return {"ok": false, "reason": "not_an_object", "bundle": {}}
	var source: Dictionary = data
	var required := required_output_keys(conversation_plan)
	var bundle := {}
	for key in required:
		if not source.has(key):
			return {
				"ok": false,
				"reason": "missing_key:%s" % key,
				"bundle": {},
			}
		bundle[key] = str(source.get(key, "")).strip_edges()
	return {"ok": true, "bundle": bundle}


# A contract must give the player footing before they commit. The opening is
# preferred, but a readily available "why" answer is acceptable for a speaker
# who is intentionally terse. This is exact safe-text matching because the
# values are code-owned; it prevents a generated bundle from replacing a real
# consequence with a vague claim that the job is simply important.
static func validate_causal_visibility(
	bundle: Dictionary,
	mission_plan: Dictionary,
	conversation_plan: Dictionary
) -> Dictionary:
	var approved_truths: Array[String] = []
	for key in ["public_because", "stake"]:
		var text := _text(mission_plan, key, "")
		if not text.is_empty() and text not in approved_truths:
			approved_truths.append(text)
	if approved_truths.is_empty():
		return {"ok": false, "reason": "missing_causal_truth"}
	var opening := str(bundle.get("opening", "")).strip_edges()
	if _contains_any(opening, approved_truths):
		return {"ok": true, "source": "opening"}
	for intent in _intents(conversation_plan):
		if str(intent.get("id", "")) != PlanType.INTENT_ASK_WHY:
			continue
		var response := str(bundle.get("%s_response" % PlanType.INTENT_ASK_WHY, "")).strip_edges()
		if _contains_any(response, approved_truths):
			return {"ok": true, "source": "ask_why"}
	return {"ok": false, "reason": "causal_visibility_missing"}


static func _fallback_response(intent_id: String, mission_plan: Dictionary) -> String:
	match intent_id:
		PlanType.INTENT_CLARIFY_TERM:
			return "The short version: %s" % _text(
				mission_plan,
				"public_because",
				"the reason is in the posted contract packet."
			)
		PlanType.INTENT_ASK_WHY:
			return "Because %s" % _text(
				mission_plan,
				"stake",
				"waiting makes the bill worse."
			)
		PlanType.INTENT_ASK_RISK:
			return _text(mission_plan, "risk_text", "The usual kind: bad timing, worse company.")
		PlanType.INTENT_ASK_CONNECTION:
			return "It ties back to this pressure: %s" % _text(
				mission_plan,
				"public_because",
				"everyone is pretending not to notice."
			)
		PlanType.INTENT_REQUEST_ADVANCE:
			return "Advance terms stay in the contract ledger; I do not improvise money."
		PlanType.INTENT_REQUEST_HAZARD_PAY:
			return "Hazard terms stay in the contract ledger; the risk is already priced."
		PlanType.INTENT_DECLINE:
			return "Declined. I will mark the opportunity cold."
		_:
			return "Accepted terms are exactly what the contract states."


static func _intents(conversation_plan: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var intents: Array = conversation_plan.get("intents", []) \
		if conversation_plan.get("intents", []) is Array else []
	for raw_intent in intents:
		if raw_intent is Dictionary:
			result.append((raw_intent as Dictionary).duplicate(true))
	return result


static func _objective_summary(mission_plan: Dictionary) -> String:
	var objective_type := _text(mission_plan, "objective_type", "UNKNOWN")
	match objective_type:
		"DELIVER_ORE":
			return "Deliver %d m³ ore." % int(mission_plan.get("amount_required", 0))
		"KILL_SHIPS":
			return "Destroy %d hostile ships." % int(mission_plan.get("count_required", 0))
		"DELIVERY_COURIER":
			return "Deliver %s." % _text(mission_plan, "item_name", "the courier cargo")
		"PURCHASE_DELIVERY":
			return "Purchase and deliver %s." % _text(mission_plan, "item_name", "the requested goods")
		"RECOVER_COMBAT_DROP":
			return "Recover %s from hostile wreckage." % _text(mission_plan, "item_name", "the data")
		"TARGET_WITH_COMMS_REVERSAL":
			return "Engage the target group and monitor comms before the final kill."
		_:
			return _text(mission_plan, "objective_summary", "Complete the listed objective.")


static func _text(source: Dictionary, key: String, fallback: String) -> String:
	var text := str(source.get(key, fallback)).strip_edges()
	return fallback if text.is_empty() else text


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array):
		return result
	for item in (value as Array):
		var text := str(item).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


static func _contains_any(text: String, needles: Array[String]) -> bool:
	var lower := text.to_lower()
	for needle in needles:
		var clean := needle.strip_edges().to_lower()
		if not clean.is_empty() and lower.contains(clean):
			return true
	return false
