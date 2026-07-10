extends SceneTree

const NarrativeMetadataType := preload("res://scripts/domain/NarrativeMetadata.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_allowed_field_contract()
	_test_empty_metadata_defaults_are_legacy_safe()

	if _failures.is_empty():
		print("[PASS] Narrative metadata tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_allowed_field_contract() -> void:
	var expected := [
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
	_expect(
		NarrativeMetadataType.allowed_fields() == expected,
		"Narrative metadata allowed-field list changed unexpectedly."
	)
	for field in expected:
		_expect(
			NarrativeMetadataType.is_allowed_field(field),
			"Allowed field was not recognized: %s" % field
		)
	_expect(
		not NarrativeMetadataType.is_allowed_field("director_secret"),
		"Unknown narrative metadata field was allowed."
	)


func _test_empty_metadata_defaults_are_legacy_safe() -> void:
	var metadata := NarrativeMetadataType.empty()
	for field in NarrativeMetadataType.STRING_FIELDS:
		_expect(
			metadata.get(field, null) == "",
			"String field did not default to empty string: %s" % field
		)
	for field in NarrativeMetadataType.ARRAY_FIELDS:
		_expect(
			metadata.get(field, null) is Array
					and (metadata.get(field, []) as Array).is_empty(),
			"Array field did not default to empty array: %s" % field
		)
	for field in NarrativeMetadataType.DICTIONARY_FIELDS:
		_expect(
			metadata.get(field, null) is Dictionary
					and (metadata.get(field, {}) as Dictionary).is_empty(),
			"Dictionary field did not default to empty dictionary: %s" % field
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
