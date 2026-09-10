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
	var requested_chapter := maxi(
		1,
		int(unresolved_story_state.get(
			"requested_chapter",
			unresolved_story_state.get("chapter", 1)
		))
	)
	lines.append(JSON.stringify(_output_contract(requested_chapter), "\t"))
	return "\n".join(lines)


static func _append_block(lines: Array[String], label: String, body: String) -> void:
	lines.append("@@%s" % label)
	lines.append(body if not body.is_empty() else "(none)")


static func _append_json_block(lines: Array[String], label: String, value: Variant) -> void:
	lines.append("@@%s" % label)
	lines.append(JSON.stringify(value, "\t"))


static func _output_contract(chapter_number: int = 1) -> Dictionary:
	return {
		"packet_id": "chapter_packet.%d" % maxi(1, chapter_number),
		"chapter": maxi(1, chapter_number),
		"premise": "player-safe one-line chapter pressure",
		"opposing_force": _default_opposing_force_dossier(),
		"attachment_beats": [
			{
				"character_id": "kaelen|nova",
				"beat_id": "only an ID listed in unresolved_story_state.eligible_attachment_beats",
			},
		],
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
	model_name: String = "",
	eligible_attachment_beats: Array = []
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
		valid_entity_ids,
		eligible_attachment_beats
	)
	if not result.is_valid():
		return _failure("chapter_plan_validation_failed", result, model_name)
	return {
		"ok": true,
		"packet": repaired,
		"model": model_name,
		"status": "ready",
	}


static func validation_correction_notes(validation: ValidationResult) -> Array[String]:
	if validation == null or validation.is_valid():
		return []
	var notes: Array[String] = []
	for issue in validation.errors:
		var path := str(issue.get("path", "")).strip_edges()
		var code := str(issue.get("code", "")).strip_edges()
		var message := str(issue.get("message", "")).strip_edges()
		var prefix := code if not code.is_empty() else "validation_error"
		if not path.is_empty():
			prefix += " at %s" % path
		notes.append("%s: %s" % [prefix, message])
	return notes


static func fallback_chapter_packet(
	chapter: int,
	available_objective_types: Array = [],
	valid_entity_ids: Array = [],
	reason: String = "chapter_plan_fallback"
) -> Dictionary:
	var chapter_number := maxi(1, chapter)
	var objective_type := _first_available_objective(
		available_objective_types,
		[
			"DELIVERY_COURIER",
			"PURCHASE_DELIVERY",
			"RECOVER_COMBAT_DROP",
			"TARGET_WITH_COMMS_REVERSAL",
			"KILL_SHIPS",
			"DELIVER_ORE",
			"PICKUP_SPECIAL",
		]
	)
	var entity_id := _first_available_entity(valid_entity_ids)
	var suffix := "fallback_chapter_%d" % chapter_number
	return {
		"packet_id": "chapter_packet.%d.fallback" % chapter_number,
		"chapter": chapter_number,
		"premise": "Local pressure is rising while the larger story plan recovers.",
		"opposing_force": _default_opposing_force_dossier(),
		"attachment_beats": [],
		"threads": [
			{
				"thread_id": "thread.%s" % suffix,
				"public_ref": "thread:%s" % suffix,
				"privacy": "public",
				"summary": "A local pressure thread keeps missions grounded until the chapter plan refreshes.",
			},
		],
		"facts": [
			{
				"fact_id": "fact.%s_visible_pressure" % suffix,
				"privacy": "public",
				"public_text": "Local contacts are reacting to unstable conditions.",
				"answer_anchor": "The trouble is local, visible, and safe to ask about.",
			},
		],
		"beats": [
			{
				"beat_id": "beat.%s_stabilize_route" % suffix,
				"thread_id": "thread.%s" % suffix,
				"cause_id": "cause.%s_model_recovery" % suffix,
				"supported_objective_types": [objective_type],
				"eligible_entity_ids": [entity_id],
				"stake": "Contacts need a grounded job while the authored chapter packet is unavailable.",
				"disclosure_fact_ids": ["fact.%s_visible_pressure" % suffix],
				"completion_fact_ids": ["fact.%s_visible_pressure" % suffix],
				"decline_consequence": "The local pressure remains unresolved and another contact may ask for help.",
			},
		],
		"next_packet_trigger": {
			"start_when_consumed_ratio_at_least": 0.6,
			"reason": reason,
		},
		"source": "procedural_fallback",
		"fallback_reason": reason,
	}


static func _first_available_objective(
	available_objective_types: Array,
	preferred_order: Array
) -> String:
	var available := {}
	for objective in available_objective_types:
		available[str(objective)] = true
	for preferred in preferred_order:
		var objective := str(preferred)
		if available.is_empty() or available.has(objective):
			return objective
	for objective in available_objective_types:
		var text := str(objective).strip_edges()
		if not text.is_empty():
			return text
	return "KILL_SHIPS"


static func _first_available_entity(valid_entity_ids: Array) -> String:
	for preferred in ["npc.kaelen", "ai.nova"]:
		if valid_entity_ids.has(preferred):
			return preferred
	for entity_id in valid_entity_ids:
		var text := str(entity_id).strip_edges()
		if not text.is_empty():
			return text
	return "npc.kaelen"


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
	packet["attachment_beats"] = _array_or_empty(packet.get("attachment_beats", []))
	packet["opposing_force"] = _normalized_opposing_force_dossier(
		packet.get("opposing_force", {})
	)
	return packet


static func _apply_alias(packet: Dictionary, alias_key: String, target_key: String) -> void:
	if packet.has(target_key) or not packet.has(alias_key):
		return
	packet[target_key] = packet[alias_key]


static func _array_or_empty(value: Variant) -> Array:
	if value is Array:
		return value
	return []


# This is deliberately a dossier shell, not an antagonist generator. Until a
# campaign premise earns an opposing force, `unformed` prevents the model from
# treating an arbitrary early pressure as settled canon.
static func _default_opposing_force_dossier() -> Dictionary:
	return {
		"status": "unformed",
		"current_footprint": [],
		"identity": {"known": [], "unknown": []},
		"objectives": [],
		"capabilities": [],
		"limits": [],
		"chapter_move": "",
		"local_aftermath": [],
		"evidence_trail": [],
		"escalation_tier": 0,
	}


static func _normalized_opposing_force_dossier(value: Variant) -> Dictionary:
	var dossier := _default_opposing_force_dossier()
	if not value is Dictionary:
		return dossier
	var source: Dictionary = value
	dossier["status"] = str(source.get("status", dossier["status"])).strip_edges()
	if dossier["status"].is_empty():
		dossier["status"] = "unformed"
	for field in [
		"current_footprint",
		"objectives",
		"capabilities",
		"limits",
		"local_aftermath",
		"evidence_trail",
	]:
		dossier[field] = _array_or_empty(source.get(field, []))
	var identity_source: Dictionary = source.get("identity", {}) \
		if source.get("identity", {}) is Dictionary else {}
	dossier["identity"] = {
		"known": _array_or_empty(identity_source.get("known", [])),
		"unknown": _array_or_empty(identity_source.get("unknown", [])),
	}
	dossier["chapter_move"] = str(source.get("chapter_move", "")).strip_edges()
	dossier["escalation_tier"] = clampi(int(source.get("escalation_tier", 0)), 0, 5)
	return dossier


static func _validate_packet(
	packet: Dictionary,
	available_objective_types: Array,
	valid_entity_ids: Array,
	eligible_attachment_beats: Array
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
	_validate_opposing_force_dossier(packet.get("opposing_force", {}), result)
	for field in ["threads", "facts", "beats", "attachment_beats"]:
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
	_validate_attachment_beats(
		_array_or_empty(packet.get("attachment_beats", [])),
		eligible_attachment_beats,
		result
	)
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


static func _validate_attachment_beats(
	selected: Array,
	eligible: Array,
	result: ValidationResult
) -> void:
	var allowed := {}
	for entry in eligible:
		if not entry is Dictionary:
			continue
		var character_id := str((entry as Dictionary).get("character_id", "")).strip_edges()
		var beat_id := str((entry as Dictionary).get("beat_id", "")).strip_edges()
		if not character_id.is_empty() and not beat_id.is_empty():
			allowed["%s|%s" % [character_id, beat_id]] = true
	var selected_characters := {}
	for index in range(selected.size()):
		if not selected[index] is Dictionary:
			result.add_error("invalid_attachment_beat", "Attachment beat must be an object.", "attachment_beats.%d" % index)
			continue
		var selection: Dictionary = selected[index]
		var character_id := str(selection.get("character_id", "")).strip_edges()
		var beat_id := str(selection.get("beat_id", "")).strip_edges()
		var path := "attachment_beats.%d" % index
		if character_id.is_empty() or beat_id.is_empty() or not allowed.has("%s|%s" % [character_id, beat_id]):
			result.add_error("ineligible_attachment_beat", "Chapter packet selected an attachment beat that is not currently eligible.", path)
			continue
		if selected_characters.has(character_id):
			result.add_error("duplicate_attachment_character", "Chapter packet may select at most one attachment beat per character.", path)
			continue
		selected_characters[character_id] = true


static func _validate_opposing_force_dossier(
	value: Variant,
	result: ValidationResult
) -> void:
	if not value is Dictionary:
		result.add_error(
			"invalid_opposing_force_dossier",
			"Chapter packet opposing_force must be an object.",
			"opposing_force"
		)
		return
	var dossier: Dictionary = value
	if not ["unformed", "active"].has(str(dossier.get("status", ""))):
		result.add_error(
			"invalid_opposing_force_status",
			"Opposing-force dossier status must be unformed or active.",
			"opposing_force.status"
		)
	for field in [
		"current_footprint",
		"objectives",
		"capabilities",
		"limits",
		"local_aftermath",
		"evidence_trail",
	]:
		if not dossier.get(field, []) is Array:
			result.add_error(
				"invalid_opposing_force_array",
				"Opposing-force dossier field '%s' must be an array." % field,
				"opposing_force.%s" % field
			)
	var identity: Variant = dossier.get("identity", {})
	if not identity is Dictionary:
		result.add_error(
			"invalid_opposing_force_identity",
			"Opposing-force dossier identity must be an object.",
			"opposing_force.identity"
		)
	else:
		for field in ["known", "unknown"]:
			if not (identity as Dictionary).get(field, []) is Array:
				result.add_error(
					"invalid_opposing_force_identity_array",
					"Opposing-force identity field '%s' must be an array." % field,
					"opposing_force.identity.%s" % field
				)
	if not dossier.get("chapter_move", "") is String:
		result.add_error(
			"invalid_opposing_force_chapter_move",
			"Opposing-force dossier chapter_move must be a string.",
			"opposing_force.chapter_move"
		)
	if int(dossier.get("escalation_tier", -1)) < 0 \
			or int(dossier.get("escalation_tier", 6)) > 5:
		result.add_error(
			"invalid_opposing_force_escalation_tier",
			"Opposing-force escalation_tier must be between 0 and 5.",
			"opposing_force.escalation_tier"
		)


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
