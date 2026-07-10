class_name NarrativeMetadata
extends RefCounted

const STRING_FIELDS := [
	"offer_id",
	"story_thread_id",
	"story_beat_id",
	"story_hook_ref",
	"cause_id",
	"public_because",
	"stake",
	"conversation_cache_key",
	"conversation_state",
]

const ARRAY_FIELDS := [
	"question_fact_ids",
	"completion_fact_ids",
]

const DICTIONARY_FIELDS := [
	"outcome_snapshot",
]

const ALLOWED_FIELDS := [
	"offer_id",
	"story_thread_id",
	"story_beat_id",
	"story_hook_ref",
	"cause_id",
	"public_because",
	"stake",
	"question_fact_ids",
	"completion_fact_ids",
	"conversation_cache_key",
	"conversation_state",
	"outcome_snapshot",
]


static func allowed_fields() -> Array[String]:
	var fields: Array[String] = []
	for field in ALLOWED_FIELDS:
		fields.append(str(field))
	return fields


static func empty() -> Dictionary:
	var metadata := {}
	for field in STRING_FIELDS:
		metadata[field] = ""
	for field in ARRAY_FIELDS:
		metadata[field] = []
	for field in DICTIONARY_FIELDS:
		metadata[field] = {}
	return metadata


static func is_allowed_field(field: String) -> bool:
	return field in ALLOWED_FIELDS


static func from_source(source: Dictionary) -> Dictionary:
	var metadata := empty()
	var nested: Variant = source.get("narrative_metadata", {})
	if nested is Dictionary:
		_merge_allowed_fields(metadata, nested as Dictionary)
	_merge_allowed_fields(metadata, source)
	return metadata


static func apply_to_state(state: Dictionary, metadata: Dictionary) -> Dictionary:
	var next_state := state.duplicate(true)
	var clean := from_source({"narrative_metadata": metadata})
	next_state["narrative_metadata"] = clean
	for field in ALLOWED_FIELDS:
		next_state[field] = clean[field]
	return next_state


static func _merge_allowed_fields(target: Dictionary, source: Dictionary) -> void:
	for field in STRING_FIELDS:
		if source.has(field):
			target[field] = str(source.get(field, ""))
	for field in ARRAY_FIELDS:
		if source.get(field, null) is Array:
			target[field] = (source[field] as Array).duplicate(true)
	for field in DICTIONARY_FIELDS:
		if source.get(field, null) is Dictionary:
			target[field] = (source[field] as Dictionary).duplicate(true)
