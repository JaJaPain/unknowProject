class_name FixedCastStateMachine
extends RefCounted

# The model receives the selected state, never the transition rules. States are
# intentionally compact and are selected only from gameplay events.
const CHARACTER_IDS := ["kaelen", "nova"]
const DEFAULT_STATES := {"kaelen": "broker_neutral", "nova": "observant"}
const VALID_STATES := {
	"kaelen": ["broker_neutral", "guarded", "quietly_relieved", "wary"],
	"nova": ["observant", "protective", "cautious", "earned_resolve"],
}


static func default_ledger() -> Dictionary:
	return {"kaelen": _entry("kaelen", "broker_neutral"), "nova": _entry("nova", "observant")}


static func normalize_ledger(source: Dictionary) -> Dictionary:
	var ledger := default_ledger()
	for character_id in CHARACTER_IDS:
		var raw: Dictionary = source.get(character_id, {}) if source.get(character_id, {}) is Dictionary else {}
		var state_id := str(raw.get("state_id", DEFAULT_STATES[character_id]))
		if not (VALID_STATES[character_id] as Array).has(state_id):
			state_id = str(DEFAULT_STATES[character_id])
		var entry := _entry(character_id, state_id)
		entry["revision"] = maxi(0, int(raw.get("revision", 0)))
		entry["last_event"] = str(raw.get("last_event", ""))
		entry["last_changed_minute"] = maxi(0, int(raw.get("last_changed_minute", 0)))
		ledger[character_id] = entry
	return ledger


static func apply_event(ledger: Dictionary, event_type: String, context: Dictionary, attachment_ledger: Dictionary, minute: int) -> Dictionary:
	var next := normalize_ledger(ledger)
	for character_id in CHARACTER_IDS:
		var next_state := _state_for_event(character_id, event_type.strip_edges(), context, attachment_ledger)
		if next_state.is_empty():
			continue
		var entry: Dictionary = next.get(character_id, {})
		if str(entry.get("state_id", "")) != next_state:
			entry["state_id"] = next_state
			entry["revision"] = int(entry.get("revision", 0)) + 1
			entry["last_changed_minute"] = maxi(0, minute)
		entry["last_event"] = event_type
		next[character_id] = entry
	return next


static func state_for(character_id: String, ledger: Dictionary) -> String:
	var normalized := normalize_ledger(ledger)
	var entry: Dictionary = normalized.get(character_id, {})
	return str(entry.get("state_id", DEFAULT_STATES.get(character_id, "")))


static func _state_for_event(character_id: String, event_type: String, context: Dictionary, attachments: Dictionary) -> String:
	if character_id == "kaelen":
		match event_type:
			"mission_completed":
				if bool(context.get("public_board", false)): return "broker_neutral"
				return "quietly_relieved"
			"mission_declined": return "guarded"
			"mission_abandoned", "mission_expired", "mission_failed": return "wary"
			"system_arrived", "docked": return "broker_neutral"
	elif character_id == "nova":
		match event_type:
			"mission_accepted":
				if _is_known_tough(context): return "protective"
			"mission_declined":
				if _is_known_tough(context): return "cautious"
			"mission_abandoned", "mission_expired", "mission_failed": return "cautious"
			"system_arrived", "docked":
				if _earned_change_completed("nova", attachments): return "earned_resolve"
				return "observant"
			"mission_completed":
				if _is_known_tough(context): return "cautious"
				return "observant"
	return ""


static func _earned_change_completed(character_id: String, attachments: Dictionary) -> bool:
	var arc: Dictionary = attachments.get(character_id, {}) if attachments.get(character_id, {}) is Dictionary else {}
	var completed: Array = arc.get("completed_beat_ids", []) if arc.get("completed_beat_ids", []) is Array else []
	return completed.has("earned_change")


static func _is_known_tough(context: Dictionary) -> bool:
	if bool(context.get("known_tough", false)):
		return true
	var metadata: Dictionary = context.get("narrative_metadata", {}) if context.get("narrative_metadata", {}) is Dictionary else {}
	var snapshot: Dictionary = metadata.get("outcome_snapshot", {}) if metadata.get("outcome_snapshot", {}) is Dictionary else {}
	var budget: Dictionary = snapshot.get("challenge_budget", {}) if snapshot.get("challenge_budget", {}) is Dictionary else {}
	return str(context.get("difficulty_band", budget.get("difficulty_band", ""))) in ["dangerous", "story_climax"]


static func _entry(_character_id: String, state_id: String) -> Dictionary:
	return {"state_id": state_id, "revision": 0, "last_event": "", "last_changed_minute": 0}
