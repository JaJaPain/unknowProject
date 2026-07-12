class_name DialogueBundleValidator
extends RefCounted

const CompilerType := preload("res://scripts/story/MissionConversationCompiler.gd")

const MIN_TEXT_LENGTH := 2
const MAX_OPENING_LENGTH := 420
const MAX_LINE_LENGTH := 220


static func validate_bundle(
	bundle: Dictionary,
	conversation_plan: Dictionary,
	speaker_card: Dictionary = {}
) -> Dictionary:
	var errors: Array[String] = []
	var required := CompilerType.required_output_keys(conversation_plan)
	var required_lookup := {}
	for key in required:
		required_lookup[key] = true
		var text := str(bundle.get(key, "")).strip_edges()
		if text.length() < MIN_TEXT_LENGTH:
			errors.append("missing_or_short:%s" % key)
			continue
		var max_length := MAX_OPENING_LENGTH if key == "opening" else MAX_LINE_LENGTH
		if text.length() > max_length:
			errors.append("too_long:%s" % key)
	for key in bundle.keys():
		if not required_lookup.has(str(key)):
			errors.append("unexpected_key:%s" % str(key))
	var banned := _banned_tics(speaker_card)
	for key in required:
		var text := str(bundle.get(key, ""))
		for tic in banned:
			if _contains_wordish(text, tic):
				errors.append("banned_tic:%s:%s" % [key, tic])
	for intent in _intents(conversation_plan):
		if str(intent.get("kind", "")) != "question":
			continue
		var intent_id := str(intent.get("id", "")).strip_edges()
		if intent_id.is_empty():
			continue
		var anchors := _string_array(intent.get("answer_anchors", []))
		if anchors.is_empty():
			continue
		var response := str(bundle.get("%s_response" % intent_id, ""))
		if not _contains_any_anchor(response, anchors):
			errors.append("missing_answer_anchor:%s" % intent_id)
	if errors.is_empty():
		return {"ok": true, "errors": []}
	return {"ok": false, "errors": errors}


static func _banned_tics(speaker_card: Dictionary) -> Array[String]:
	var voice_rules: Dictionary = speaker_card.get("voice_rules", {}) \
		if speaker_card.get("voice_rules", {}) is Dictionary else {}
	var result: Array[String] = []
	var raw: Variant = voice_rules.get("banned_tics", [])
	if not (raw is Array):
		return result
	for item in (raw as Array):
		var tic := str(item).strip_edges()
		if not tic.is_empty():
			result.append(tic)
	return result


static func _contains_wordish(text: String, needle: String) -> bool:
	var clean_needle := needle.strip_edges().to_lower()
	if clean_needle.is_empty():
		return false
	return text.to_lower().contains(clean_needle)


static func _contains_any_anchor(text: String, anchors: Array[String]) -> bool:
	for anchor in anchors:
		if _contains_wordish(text, anchor):
			return true
	return false


static func _intents(conversation_plan: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_intents: Array = conversation_plan.get("intents", []) \
		if conversation_plan.get("intents", []) is Array else []
	for raw_intent in raw_intents:
		if raw_intent is Dictionary:
			result.append((raw_intent as Dictionary).duplicate(true))
	return result


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array):
		return result
	for item in (value as Array):
		var text := str(item).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result
