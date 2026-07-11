class_name ChapterNarrativeDirector
extends RefCounted

const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

# Builds large-model prompts for chapter narrative packets. This director does
# not fetch campaign state directly: callers must pass already-validated,
# ownership-correct context so the prompt boundary stays easy to audit.


static func build_chapter_plan_prompt(
	director_context: String,
	validated_entities: Array,
	available_mission_capabilities: Array,
	recent_player_choices: Array,
	unresolved_story_state: Dictionary,
	correction_notes: Array = []
) -> String:
	var lines: Array[String] = []
	lines.append("You are the large local story model for a procedural space game.")
	lines.append("Create one append-only chapter narrative packet.")
	lines.append("Use only the labeled inputs below. Do not invent unavailable entities, mechanics, factions, NPCs, stores, gates, or mission types.")
	lines.append("Never reveal hidden facts in player-facing fields; keep facts marked hidden/secret inside fact records only.")
	lines.append("")
	_append_block(lines, "director_context", director_context.strip_edges())
	_append_json_block(lines, "validated_entities", validated_entities)
	_append_json_block(lines, "available_mission_capabilities", available_mission_capabilities)
	_append_json_block(lines, "recent_player_choices", recent_player_choices)
	_append_json_block(lines, "unresolved_story_state", unresolved_story_state)
	if not correction_notes.is_empty():
		_append_json_block(lines, "correction_notes", correction_notes)
	lines.append("@@output_contract")
	lines.append("Return only JSON. No markdown. No comments.")
	lines.append("Shape:")
	lines.append(JSON.stringify(_output_contract(), "\t"))
	return "\n".join(lines)


static func _append_block(lines: Array[String], label: String, body: String) -> void:
	lines.append("@@%s" % label)
	lines.append(body if not body.is_empty() else "(none)")


static func _append_json_block(lines: Array[String], label: String, value: Variant) -> void:
	lines.append("@@%s" % label)
	lines.append(JSON.stringify(value, "\t"))


static func _output_contract() -> Dictionary:
	return {
		"packet_id": "chapter_packet.<chapter_number>",
		"chapter": 1,
		"premise": "player-safe one-line chapter pressure",
		"threads": [
			{
				"thread_id": "thread.<snake_case>",
				"public_ref": "thread:<short_hash_or_slug>",
				"privacy": "public|private|secret",
				"summary": "short thread summary",
			},
		],
		"facts": [
			{
				"fact_id": "fact.<snake_case>",
				"privacy": "public|private|secret",
				"public_text": "empty unless player-safe",
				"answer_anchor": "short answer anchor for paired questions",
			},
		],
		"beats": [
			{
				"beat_id": "beat.<snake_case>",
				"thread_id": "thread.<snake_case>",
				"cause_id": "cause.<snake_case>",
				"supported_objective_types": ["KILL_SHIPS"],
				"eligible_entity_ids": ["npc.or.faction.or.location.id"],
				"stake": "why this matters now",
				"disclosure_fact_ids": ["fact.<snake_case>"],
				"completion_fact_ids": ["fact.<snake_case>"],
				"decline_consequence": "visible consequence or alternate approach",
			},
		],
		"next_packet_trigger": {
			"start_when_consumed_ratio_at_least": 0.6,
			"reason": "why generation should begin before this packet is exhausted",
		},
	}


static func parse_chapter_plan_response(
	envelope_text: String,
	available_objective_types: Array = [],
	valid_entity_ids: Array = [],
	model_name: String = ""
) -> Dictionary:
	var response_text := _extract_response_text(envelope_text)
	if response_text.is_empty():
		var missing := ValidationResultType.new()
		missing.add_error(
			"chapter_plan_missing_response",
			"Chapter plan response envelope did not include text to parse."
		)
		return _failure("chapter_plan_missing_response", missing, model_name)
	var parsed := DomainJsonType.parse_object(
		response_text,
		"chapter_plan_response"
	)
	var validation := parsed["validation"] as ValidationResult
	if not validation.is_valid():
		return _failure("chapter_plan_json_parse_failed", validation, model_name)
	var repaired := _repair_packet_shape(parsed["data"])
	var result := _validate_packet(
		repaired,
		available_objective_types,
		valid_entity_ids
	)
	if not result.is_valid():
		return _failure("chapter_plan_validation_failed", result, model_name)
	return {
		"ok": true,
		"packet": repaired,
		"model": model_name,
		"status": "ready",
	}


static func _extract_response_text(envelope_text: String) -> String:
	var envelope := DomainJsonType.parse_object(
		envelope_text,
		"chapter_plan_envelope"
	)
	var validation := envelope["validation"] as ValidationResult
	if validation.is_valid():
		var data: Dictionary = envelope["data"]
		if data.has("response"):
			return str(data.get("response", "")).strip_edges()
		if data.has("packet") or data.has("beats") or data.has("story_beats"):
			return JSON.stringify(data)
	return envelope_text.strip_edges()


static func _repair_packet_shape(source: Dictionary) -> Dictionary:
	var packet := source.duplicate(true)
	_apply_alias(packet, "id", "packet_id")
	_apply_alias(packet, "chapter_id", "packet_id")
	_apply_alias(packet, "story_threads", "threads")
	_apply_alias(packet, "narrative_threads", "threads")
	_apply_alias(packet, "story_facts", "facts")
	_apply_alias(packet, "story_beats", "beats")
	_apply_alias(packet, "chapter_beats", "beats")
	packet["threads"] = _array_or_empty(packet.get("threads", []))
	packet["facts"] = _array_or_empty(packet.get("facts", []))
	packet["beats"] = _array_or_empty(packet.get("beats", []))
	return packet


static func _apply_alias(packet: Dictionary, alias_key: String, target_key: String) -> void:
	if packet.has(target_key) or not packet.has(alias_key):
		return
	packet[target_key] = packet[alias_key]


static func _array_or_empty(value: Variant) -> Array:
	if value is Array:
		return value
	return []


static func _validate_packet(
	packet: Dictionary,
	available_objective_types: Array,
	valid_entity_ids: Array
) -> ValidationResult:
	var result := ValidationResultType.new()
	if str(packet.get("packet_id", "")).strip_edges().is_empty():
		result.add_error(
			"missing_chapter_packet_id",
			"Chapter packet requires packet_id.",
			"packet_id"
		)
	if int(packet.get("chapter", 0)) < 1:
		result.add_error(
			"invalid_chapter_packet_chapter",
			"Chapter packet chapter must be at least 1.",
			"chapter"
		)
	if str(packet.get("premise", "")).strip_edges().is_empty():
		result.add_error(
			"missing_chapter_packet_premise",
			"Chapter packet requires a player-safe premise.",
			"premise"
		)
	for field in ["threads", "facts", "beats"]:
		if not packet.get(field, []) is Array:
			result.add_error(
				"invalid_chapter_packet_array",
				"Chapter packet field '%s' must be an array." % field,
				field
			)
	var allowed_objectives := {}
	for objective in available_objective_types:
		allowed_objectives[str(objective)] = true
	var known_entities := {}
	for entity_id in valid_entity_ids:
		known_entities[str(entity_id)] = true
	var beats: Array = packet.get("beats", [])
	for index in range(beats.size()):
		if not beats[index] is Dictionary:
			result.add_error(
				"invalid_chapter_beat",
				"Chapter beat must be an object.",
				"beats.%d" % index
			)
			continue
		_validate_beat(
			beats[index] as Dictionary,
			index,
			allowed_objectives,
			known_entities,
			result
		)
	return result


static func _validate_beat(
	beat: Dictionary,
	index: int,
	allowed_objectives: Dictionary,
	known_entities: Dictionary,
	result: ValidationResult
) -> void:
	var prefix := "beats.%d" % index
	if str(beat.get("beat_id", "")).strip_edges().is_empty():
		result.add_error(
			"missing_chapter_beat_id",
			"Chapter beat requires beat_id.",
			"%s.beat_id" % prefix
		)
	if str(beat.get("stake", "")).strip_edges().is_empty():
		result.add_error(
			"missing_chapter_beat_stake",
			"Chapter beat requires a stake.",
			"%s.stake" % prefix
		)
	var objectives: Array = _array_or_empty(
		beat.get("supported_objective_types", [])
	)
	if objectives.is_empty():
		result.add_error(
			"missing_chapter_beat_objectives",
			"Chapter beat requires at least one supported objective type.",
			"%s.supported_objective_types" % prefix
		)
	for objective in objectives:
		if not allowed_objectives.is_empty() \
				and not allowed_objectives.has(str(objective)):
			result.add_error(
				"unsupported_chapter_beat_objective",
				"Chapter beat requested unavailable objective type '%s'." %
					str(objective),
				"%s.supported_objective_types" % prefix
			)
	for entity_id in _array_or_empty(beat.get("eligible_entity_ids", [])):
		if not known_entities.is_empty() and not known_entities.has(str(entity_id)):
			result.add_error(
				"unknown_chapter_beat_entity",
				"Chapter beat references unavailable entity '%s'." %
					str(entity_id),
				"%s.eligible_entity_ids" % prefix
			)


static func _failure(
	reason: String,
	validation: ValidationResult,
	model_name: String
) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"validation": validation,
		"model": model_name,
		"status": "needs_correction_retry",
	}
