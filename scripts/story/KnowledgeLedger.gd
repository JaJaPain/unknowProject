class_name KnowledgeLedger
extends RefCounted

const DomainIdType := preload("res://scripts/domain/DomainId.gd")

const STATE_UNKNOWN := "unknown"
const STATE_RUMORED := "rumored"
const STATE_KNOWN := "known"
const STATE_CONFIRMED := "confirmed"
const STATE_CONTRADICTED := "contradicted"

const STATE_RANKS := {
	STATE_UNKNOWN: 0,
	STATE_RUMORED: 1,
	STATE_KNOWN: 2,
	STATE_CONFIRMED: 3,
	STATE_CONTRADICTED: 4,
}

var story_state: Dictionary = {}


func _init(source_state: Dictionary = {}) -> void:
	story_state = source_state
	if not story_state.get("knowledge_states", {}) is Dictionary:
		story_state["knowledge_states"] = {}
	if not story_state.get("knowledge_revision", 0) is int \
			and not story_state.get("knowledge_revision", 0) is float:
		story_state["knowledge_revision"] = 0


func state_for(fact_id: String) -> String:
	var record := _record_for(fact_id)
	if record.is_empty():
		return STATE_UNKNOWN
	var state := str(record.get("state", STATE_UNKNOWN))
	if not STATE_RANKS.has(state):
		return STATE_UNKNOWN
	return state


func can_reference(fact_id: String, minimum_state: String = STATE_KNOWN) -> bool:
	if not STATE_RANKS.has(minimum_state):
		return false
	var current_state := state_for(fact_id)
	return int(STATE_RANKS.get(current_state, 0)) >= int(
		STATE_RANKS.get(minimum_state, 0)
	)


func promote(
	fact_id: String,
	next_state: String,
	source: String,
	current_minute: int = 0,
	confidence: String = "direct"
) -> Dictionary:
	var clean_fact_id := fact_id.strip_edges()
	var clean_state := next_state.strip_edges()
	if not DomainIdType.is_valid(clean_fact_id, "fact"):
		return _failure("Knowledge fact ID is invalid: %s" % clean_fact_id)
	if not STATE_RANKS.has(clean_state):
		return _failure("Knowledge state is invalid: %s" % clean_state)

	var states: Dictionary = story_state.get("knowledge_states", {})
	var current_record: Dictionary = states.get(clean_fact_id, {})
	var current_state := state_for(clean_fact_id)
	if current_state == STATE_CONTRADICTED:
		return {
			"ok": true,
			"changed": false,
			"state": current_state,
			"reason": "already_contradicted",
		}

	var current_rank := int(STATE_RANKS.get(current_state, 0))
	var next_rank := int(STATE_RANKS.get(clean_state, 0))
	if clean_state != STATE_CONTRADICTED and next_rank < current_rank:
		return {
			"ok": true,
			"changed": false,
			"state": current_state,
			"reason": "non_monotonic_demotion_ignored",
		}
	if clean_state == current_state:
		return {
			"ok": true,
			"changed": false,
			"state": current_state,
			"reason": "already_at_state",
		}

	var next_record := current_record.duplicate(true)
	if next_record.is_empty():
		next_record["learned_at_minute"] = maxi(0, current_minute)
		next_record["first_source"] = source.strip_edges()
	if clean_state == STATE_CONTRADICTED:
		next_record["previous_state"] = current_state
	next_record["state"] = clean_state
	next_record["source"] = source.strip_edges()
	next_record["updated_at_minute"] = maxi(0, current_minute)
	next_record["confidence"] = confidence.strip_edges()
	states[clean_fact_id] = next_record
	story_state["knowledge_states"] = states
	story_state["knowledge_revision"] = (
		maxi(0, int(story_state.get("knowledge_revision", 0))) + 1
	)
	return {
		"ok": true,
		"changed": true,
		"state": clean_state,
		"record": next_record.duplicate(true),
	}


func _record_for(fact_id: String) -> Dictionary:
	var states: Dictionary = story_state.get("knowledge_states", {})
	var record: Variant = states.get(fact_id.strip_edges(), {})
	if record is Dictionary:
		return (record as Dictionary)
	return {}


func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"changed": false,
		"error": message,
	}
