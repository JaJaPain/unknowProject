class_name FixedCastAttachmentLedger
extends RefCounted

# Campaign-persistent attachment progress. This is a small authored sequence of
# shared events, not a relationship meter: it never changes rewards, mission
# availability, or player agency.
const CHARACTER_IDS := ["kaelen", "nova"]

const ARC_DEFINITIONS := {
	"kaelen": [
		{"id": "first_impression", "event": "tutorial_completed", "player_agency_point": "Completes Kaelen's first contract.", "visible_payoff": "Kaelen is established as useful before asking for trust.", "memory_callback": "The Captain closed the first job.", "next_unresolved_hook": "What does Kaelen notice once the Captain keeps choosing to return?"},
		{"id": "private_texture", "event": "system_arrived", "player_agency_point": "Chooses to travel after the tutorial.", "visible_payoff": "A quiet practical detail can enter later approved dialogue.", "memory_callback": "The Captain kept moving instead of waiting for certainty.", "next_unresolved_hook": "Which terms matter to Kaelen when work stops being routine?"},
		{"id": "mutual_reliance", "event": "profitable_completion", "player_agency_point": "Follows through on a paying contract.", "visible_payoff": "Kaelen can acknowledge reliable follow-through without sentimentality.", "memory_callback": "The Captain made a difficult contract pay cleanly.", "next_unresolved_hook": "What cost will make profit and principle pull in different directions?"},
		{"id": "remembered_consequence", "event": "mission_completed", "player_agency_point": "Completes another contract after earning reliability.", "visible_payoff": "A later line may make one restrained callback to the earned contract history.", "memory_callback": "Kaelen has evidence that the Captain follows through more than once.", "next_unresolved_hook": "How much trust can fit inside a broker's terms?"},
		{"id": "earned_change", "event": "system_arrived", "player_agency_point": "Returns to the wider work after shared success.", "visible_payoff": "Kaelen may use a slightly more open but still businesslike state.", "memory_callback": "The Captain kept flying after the work became personal.", "next_unresolved_hook": "What future pressure tests that earned ease?"},
	],
	"nova": [
		{"id": "first_impression", "event": "tutorial_completed", "player_agency_point": "Completes the first shared flight and contract.", "visible_payoff": "N.O.V.A.'s survival judgment is established through action.", "memory_callback": "The Captain brought the ship home from its first job.", "next_unresolved_hook": "What does N.O.V.A. learn from the Captain's next choice?"},
		{"id": "private_texture", "event": "system_arrived", "player_agency_point": "Chooses a new route after the tutorial.", "visible_payoff": "A small observation or ship habit can appear in approved quiet dialogue.", "memory_callback": "The Captain trusted the ship into unfamiliar space.", "next_unresolved_hook": "Which quiet pattern will N.O.V.A. notice first?"},
		{"id": "mutual_reliance", "event": "known_tough_completion", "player_agency_point": "Knowingly accepts and completes an advertised dangerous contract.", "visible_payoff": "N.O.V.A. can acknowledge that her caution materially helped the Captain return.", "memory_callback": "The Captain came back from a contract that advertised real danger.", "next_unresolved_hook": "How does N.O.V.A. balance caution with confidence after that risk?"},
		{"id": "remembered_consequence", "event": "mission_completed", "player_agency_point": "Keeps working after the difficult shared event.", "visible_payoff": "A later approved line may make one restrained shared-history callback.", "memory_callback": "N.O.V.A. has evidence the Captain hears caution and still chooses deliberately.", "next_unresolved_hook": "What will N.O.V.A. risk saying when the next warning matters?"},
		{"id": "earned_change", "event": "system_arrived", "player_agency_point": "Chooses another route after the shared risk.", "visible_payoff": "N.O.V.A. may enter earned_resolve: warmer confidence without aggression.", "memory_callback": "The Captain kept traveling with clear eyes after the hard run.", "next_unresolved_hook": "Which future threat will test that earned resolve?"},
	],
}


static func default_ledger() -> Dictionary:
	return {
		"version": 1,
		"kaelen": _default_arc("kaelen"),
		"nova": _default_arc("nova"),
	}


static func normalize_ledger(source: Dictionary) -> Dictionary:
	var ledger := default_ledger()
	for character_id in CHARACTER_IDS:
		var raw: Dictionary = source.get(character_id, {}) if source.get(character_id, {}) is Dictionary else {}
		var valid_ids := _beat_ids(character_id)
		var completed: Array[String] = []
		var raw_completed: Array = raw.get("completed_beat_ids", []) if raw.get("completed_beat_ids", []) is Array else []
		for raw_id in raw_completed:
			var beat_id := str(raw_id)
			if valid_ids.has(beat_id) and not completed.has(beat_id):
				completed.append(beat_id)
		ledger[character_id] = {
			"completed_beat_ids": completed,
			"last_completed_beat_id": str(raw.get("last_completed_beat_id", "")),
			"last_changed_minute": maxi(0, int(raw.get("last_changed_minute", 0))),
		}
	return ledger


static func advance(ledger: Dictionary, event_type: String, context: Dictionary, minute: int) -> Dictionary:
	var next := normalize_ledger(ledger)
	var clean_event := event_type.strip_edges()
	for character_id in CHARACTER_IDS:
		var arc: Dictionary = next.get(character_id, {})
		var completed: Array = arc.get("completed_beat_ids", [])
		var next_beat := _next_beat(character_id, completed)
		if next_beat.is_empty() or not _event_matches(str(next_beat.get("event", "")), clean_event, context):
			continue
		completed.append(str(next_beat.get("id", "")))
		arc["completed_beat_ids"] = completed
		arc["last_completed_beat_id"] = str(next_beat.get("id", ""))
		arc["last_changed_minute"] = maxi(0, minute)
		next[character_id] = arc
	return next


static func current_beat(character_id: String, ledger: Dictionary) -> Dictionary:
	var normalized := normalize_ledger(ledger)
	var arc: Dictionary = normalized.get(character_id, {})
	return _next_beat(character_id, arc.get("completed_beat_ids", []))


# A chapter packet may acknowledge only the next unfinished beat per character.
# Completion remains event-driven in advance(), never model-selected.
static func eligible_chapter_beats(ledger: Dictionary) -> Array[Dictionary]:
	var eligible: Array[Dictionary] = []
	for character_id in CHARACTER_IDS:
		var beat := current_beat(character_id, ledger)
		var beat_id := str(beat.get("id", "")).strip_edges()
		if beat_id.is_empty():
			continue
		eligible.append({
			"character_id": character_id,
			"beat_id": beat_id,
			"event": str(beat.get("event", "")),
			"visible_payoff": str(beat.get("visible_payoff", "")),
		})
	return eligible


static func has_completed(character_id: String, beat_id: String, ledger: Dictionary) -> bool:
	var normalized := normalize_ledger(ledger)
	var arc: Dictionary = normalized.get(character_id, {})
	return (arc.get("completed_beat_ids", []) as Array).has(beat_id)


static func public_memory_callback(character_id: String, ledger: Dictionary) -> String:
	var normalized := normalize_ledger(ledger)
	var arc: Dictionary = normalized.get(character_id, {})
	var last_id := str(arc.get("last_completed_beat_id", ""))
	for beat in ARC_DEFINITIONS.get(character_id, []):
		if str((beat as Dictionary).get("id", "")) == last_id:
			return str((beat as Dictionary).get("memory_callback", ""))
	return ""


static func _default_arc(_character_id: String) -> Dictionary:
	return {"completed_beat_ids": [], "last_completed_beat_id": "", "last_changed_minute": 0}


static func _beat_ids(character_id: String) -> Array[String]:
	var ids: Array[String] = []
	for beat in ARC_DEFINITIONS.get(character_id, []):
		ids.append(str((beat as Dictionary).get("id", "")))
	return ids


static func _next_beat(character_id: String, completed: Array) -> Dictionary:
	for beat in ARC_DEFINITIONS.get(character_id, []):
		var candidate: Dictionary = beat
		if not completed.has(str(candidate.get("id", ""))):
			return candidate.duplicate(true)
	return {}


static func _event_matches(required_event: String, event_type: String, context: Dictionary) -> bool:
	match required_event:
		"tutorial_completed":
			return event_type == "mission_completed" and bool(context.get("is_intro_tutorial", false))
		"system_arrived":
			return event_type == "system_arrived"
		"profitable_completion":
			return event_type == "mission_completed" and int(context.get("reward_credits", 0)) >= 300
		"known_tough_completion":
			return event_type == "mission_completed" and _is_known_tough(context)
		"mission_completed":
			return event_type == "mission_completed"
	return false


static func _is_known_tough(context: Dictionary) -> bool:
	if bool(context.get("known_tough", false)):
		return true
	var metadata: Dictionary = context.get("narrative_metadata", {}) if context.get("narrative_metadata", {}) is Dictionary else {}
	var snapshot: Dictionary = metadata.get("outcome_snapshot", {}) if metadata.get("outcome_snapshot", {}) is Dictionary else {}
	var budget: Dictionary = snapshot.get("challenge_budget", {}) if snapshot.get("challenge_budget", {}) is Dictionary else {}
	return str(context.get("difficulty_band", budget.get("difficulty_band", ""))) in ["dangerous", "story_climax"]
