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
	var forbidden_terms := _forbidden_terms(conversation_plan)
	for key in required:
		var text := str(bundle.get(key, ""))
		for term in forbidden_terms:
			if _contains_wordish(text, term):
				errors.append("forbidden_fact:%s:%s" % [key, term])
		var speaker_error := _speaker_prefix_error(text, speaker_card)
		if not speaker_error.is_empty():
			errors.append("speaker_prefix:%s:%s" % [key, speaker_error])
	var banned := _banned_tics(speaker_card)
	for key in required:
		var text := str(bundle.get(key, ""))
		for tic in banned:
			if _contains_wordish(text, tic):
				errors.append("banned_tic:%s:%s" % [key, tic])
	var seen_line_fields := {}
	for key in required:
		if str(key).ends_with("_player"):
			continue
		var fingerprint := _line_fingerprint(str(bundle.get(key, "")))
		if fingerprint.is_empty():
			continue
		if seen_line_fields.has(fingerprint):
			errors.append("duplicate_line:%s:%s" % [key, seen_line_fields[fingerprint]])
			continue
		seen_line_fields[fingerprint] = key
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


static func degrade_bundle(
	bundle: Dictionary,
	mission_plan: Dictionary,
	conversation_plan: Dictionary,
	speaker_card: Dictionary = {}
) -> Dictionary:
	var source_result := validate_bundle(bundle, conversation_plan, speaker_card)
	var required := CompilerType.required_output_keys(conversation_plan)
	var fallback := CompilerType.fallback_bundle(
		mission_plan,
		conversation_plan,
		speaker_card
	)
	var repaired := {}
	for key in required:
		repaired[key] = str(bundle.get(key, "")).strip_edges()
	var degraded_fields: Array[String] = []
	if not bool(source_result.get("ok", false)):
		for raw_error in (source_result.get("errors", []) as Array):
			var field := _field_for_error(str(raw_error))
			if field.is_empty() or not repaired.has(field):
				continue
			repaired[field] = str(fallback.get(field, "")).strip_edges()
			if not degraded_fields.has(field):
				degraded_fields.append(field)
	var final_result := validate_bundle(repaired, conversation_plan, speaker_card)
	return {
		"ok": bool(final_result.get("ok", false)),
		"bundle": repaired if bool(final_result.get("ok", false)) else {},
		"degraded_fields": degraded_fields,
		"source_errors": source_result.get("errors", []),
		"errors": final_result.get("errors", []),
	}


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


static func _forbidden_terms(conversation_plan: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in [
		"forbidden_fact_ids",
		"director_only_fact_ids",
		"completion_fact_ids",
		"forbidden_terms",
		"director_only_tokens",
		"completion_only_tokens",
		"secret_leak_tokens",
	]:
		for item in _string_array(conversation_plan.get(key, [])):
			if item not in result:
				result.append(item)
	for key in [
		"kaelen_hidden_angle",
		"kaelen_never_reveal",
		"director_only_summary",
	]:
		var term := str(conversation_plan.get(key, "")).strip_edges()
		if not term.is_empty() and term not in result:
			result.append(term)
	return result


static func _field_for_error(error: String) -> String:
	var parts := error.split(":")
	if parts.size() < 2:
		return ""
	match parts[0]:
		"missing_or_short", "too_long", "banned_tic", "forbidden_fact", \
		"speaker_prefix", "duplicate_line":
			return parts[1]
		"missing_answer_anchor":
			return "%s_response" % parts[1]
		_:
			return ""


static func _speaker_prefix_error(text: String, speaker_card: Dictionary) -> String:
	var clean := text.strip_edges()
	if clean.is_empty():
		return ""
	var lower := clean.to_lower()
	var speaker_name := str(speaker_card.get("name", "")).strip_edges()
	var prefixes: Array[String] = [
		"kaelen",
		"broker kaelen",
		"nova",
		"n.o.v.a.",
		"player",
		"pilot",
	]
	if not speaker_name.is_empty():
		prefixes.append(speaker_name)
	for prefix in prefixes:
		var lowered := prefix.to_lower().strip_edges()
		if lowered.is_empty():
			continue
		if lower.begins_with("%s:" % lowered) \
				or lower.begins_with("%s -" % lowered) \
				or lower.begins_with("%s —" % lowered):
			return prefix
	return ""


static func _line_fingerprint(text: String) -> String:
	var normalized := text.strip_edges().to_lower()
	if normalized.is_empty():
		return ""
	normalized = normalized.replace("\n", " ")
	normalized = normalized.replace("\t", " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	return normalized.sha256_text()


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
