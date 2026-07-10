class_name NarrativeMetadata
extends RefCounted

const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const ID_PATTERN := "^[A-Za-z0-9_.:-]+$"

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

const ID_FIELDS := [
	"offer_id",
	"story_thread_id",
	"story_beat_id",
	"story_hook_ref",
	"cause_id",
	"conversation_cache_key",
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

static var _id_regex: RegEx


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


static func validate_source(source: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	var nested: Variant = source.get("narrative_metadata", {})
	if nested != null and not (nested is Dictionary):
		result.add_error(
			"invalid_narrative_metadata",
			"narrative_metadata must be an object when present.",
			"narrative_metadata"
		)
	if nested is Dictionary:
		_validate_fields(nested as Dictionary, "narrative_metadata", result)
	_validate_fields(source, "", result)
	return result


static func apply_to_state(state: Dictionary, metadata: Dictionary) -> Dictionary:
	var next_state := state.duplicate(true)
	var clean := from_source({"narrative_metadata": metadata})
	next_state["narrative_metadata"] = clean
	for field in ALLOWED_FIELDS:
		next_state[field] = clean[field]
	return next_state


static func validate_metadata(metadata: Dictionary, path_prefix: String = "narrative_metadata") -> ValidationResult:
	var result := ValidationResultType.new()
	_validate_fields(metadata, path_prefix, result)
	return result


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


static func _validate_fields(
	source: Dictionary,
	path_prefix: String,
	result: ValidationResult
) -> void:
	for field in ALLOWED_FIELDS:
		if not source.has(field):
			continue
		var value: Variant = source[field]
		var path: String = field if path_prefix.is_empty() else "%s.%s" % [path_prefix, field]
		if field in STRING_FIELDS:
			if not value is String:
				result.add_error(
					"invalid_narrative_metadata_type",
					"Narrative metadata field '%s' must be a string." % field,
					path
				)
				continue
			if field in ID_FIELDS:
				_validate_id_text(str(value), path, result)
		elif field in ARRAY_FIELDS:
			if not value is Array:
				result.add_error(
					"invalid_narrative_metadata_type",
					"Narrative metadata field '%s' must be an array." % field,
					path
				)
				continue
			var values: Array = value
			for index in range(values.size()):
				if not values[index] is String:
					result.add_error(
						"invalid_narrative_metadata_type",
						"Narrative metadata field '%s' may only contain strings." % field,
						"%s.%d" % [path, index]
					)
					continue
				_validate_id_text(str(values[index]), "%s.%d" % [path, index], result)
		elif field in DICTIONARY_FIELDS:
			if not value is Dictionary:
				result.add_error(
					"invalid_narrative_metadata_type",
					"Narrative metadata field '%s' must be an object." % field,
					path
				)


static func _validate_id_text(
	value: String,
	path: String,
	result: ValidationResult
) -> void:
	if value.is_empty():
		return
	if value != value.strip_edges():
		result.add_error(
			"invalid_narrative_metadata_id",
			"Narrative metadata IDs cannot contain leading or trailing whitespace.",
			path
		)
		return
	if _get_id_regex().search(value) == null:
		result.add_error(
			"invalid_narrative_metadata_id",
			"Narrative metadata IDs may only use letters, numbers, underscore, dot, colon, or dash.",
			path
		)


static func _get_id_regex() -> RegEx:
	if _id_regex == null:
		_id_regex = RegEx.new()
		var err := _id_regex.compile(ID_PATTERN)
		if err != OK:
			push_error("[NarrativeMetadata] Failed to compile ID validation pattern.")
	return _id_regex
