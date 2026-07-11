class_name ChapterNarrativeDirector
extends RefCounted

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
