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
