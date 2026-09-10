class_name FixedCastLineValidator
extends RefCounted

const SoulRegistryType := preload("res://scripts/story/FixedCastSoulRegistry.gd")
const VoiceBankType := preload("res://scripts/story/FixedCastVoiceBank.gd")

const MAX_LINE_LENGTH := 220


# Pure player-facing validation for one fixed-cast line. Code owns the selected
# character/state/situation and the permitted facts; the model only supplies
# wording inside that contract.
static func validate_line(
	character_id: String,
	state_id: String,
	situation: String,
	line: String,
	context: Dictionary = {}
) -> Dictionary:
	var errors: Array[String] = []
	var projection := SoulRegistryType.public_prompt_projection(
		character_id, state_id, situation
	)
	if not bool(projection.get("ok", false)):
		return {"ok": false, "errors": [str(projection.get("reason", "invalid_projection"))]}
	var clean := line.strip_edges()
	if clean.is_empty():
		errors.append("empty_line")
	if clean.length() > MAX_LINE_LENGTH:
		errors.append("too_long")
	var lower := clean.to_lower()
	for token in _string_array(context.get("forbidden_tokens", [])):
		if lower.contains(token.to_lower()):
			errors.append("forbidden_fact:%s" % token)
	for tic in _banned_tics(projection):
		if lower.contains(tic.to_lower()):
			errors.append("banned_tic:%s" % tic)
	if character_id == "nova" and lower.contains("shiny"):
		errors.append("cross_character_address:shiny")
	if character_id == "kaelen" and lower.contains("n.o.v.a."):
		errors.append("cross_character_voice:nova_name")
	if VoiceBankType.matches_curated_line(character_id, situation, clean):
		errors.append("copied_curated_reference")
	if _repeats_recent(clean, context.get("recent_lines", [])):
		errors.append("recent_repeat")
	errors.append_array(_situation_errors(character_id, situation, lower, context))
	return {"ok": errors.is_empty(), "errors": errors}


static func _situation_errors(
	character_id: String,
	situation: String,
	lower: String,
	context: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	if character_id == "kaelen" and situation == "turn_in":
		if _contains_any(lower, ["they are safe now", "they're safe now", "saved them"]):
			errors.append("generic_safety_claim")
		var anchors := _string_array(context.get("task_anchors", []))
		anchors.append_array(_string_array(context.get("visible_effect_terms", [])))
		if not anchors.is_empty() and not _contains_any(lower, anchors):
			errors.append("missing_turn_in_anchor")
	elif character_id == "kaelen" and situation == "abandonment":
		if _contains_any(lower, ["you owe", "pay the fee", "refund", "cover the loss", "go back and", "fix the "]):
			errors.append("fictional_or_followup_consequence")
	elif character_id == "nova" and situation == "combat":
		if not _contains_any(lower, ["weapon", "target", "lock", "hull", "damage", "pressure", "shield", "engine"]):
			errors.append("missing_actionable_combat_detail")
	elif character_id == "nova" and situation == "repair_warning":
		if not _contains_any(lower, ["repair", "hull", "damage", "integrity", "dent"]):
			errors.append("missing_repair_condition")
	elif character_id == "nova" and situation == "arrival":
		if not _contains_any(lower, ["system", "sensor", "traffic", "route", "arrival", "star"]):
			errors.append("missing_arrival_grounding")
	return errors


static func _banned_tics(projection: Dictionary) -> Array[String]:
	var voice: Dictionary = projection.get("voice_controls", {}) \
		if projection.get("voice_controls", {}) is Dictionary else {}
	return _string_array(voice.get("banned_tics", []))


static func _repeats_recent(line: String, recent_lines: Variant) -> bool:
	if not recent_lines is Array:
		return false
	var normalized := _normalize(line)
	for raw_recent in recent_lines:
		var recent := _normalize(str(raw_recent))
		if not recent.is_empty() and recent == normalized:
			return true
	return false


static func _contains_any(text: String, terms: Array[String]) -> bool:
	for term in terms:
		if not term.strip_edges().is_empty() and text.contains(term.to_lower()):
			return true
	return false


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for raw in value:
		var text := str(raw).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


static func _normalize(line: String) -> String:
	var clean := line.to_lower().strip_edges()
	for punctuation in [".", ",", "!", "?", ";", ":", "'", "\"", "’", "—", "-", "…"]:
		clean = clean.replace(punctuation, " ")
	return " ".join(clean.split(" ", false))
