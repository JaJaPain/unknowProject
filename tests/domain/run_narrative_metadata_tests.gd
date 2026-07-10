extends SceneTree

const NarrativeMetadataType := preload("res://scripts/domain/NarrativeMetadata.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_allowed_field_contract()
	_test_empty_metadata_defaults_are_legacy_safe()
	_test_extracts_nested_and_legacy_fields()

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


func _test_extracts_nested_and_legacy_fields() -> void:
	var metadata := NarrativeMetadataType.from_source({
		"story_hook_ref": "hook:legacy",
		"narrative_metadata": {
			"offer_id": "offer.alpha",
			"question_fact_ids": ["fact.public"],
			"outcome_snapshot": {"clean": true},
			"director_secret": "do not copy",
		},
	})
	_expect(
		metadata.get("story_hook_ref", "") == "hook:legacy",
		"Legacy top-level story_hook_ref was not extracted."
	)
	_expect(
		metadata.get("offer_id", "") == "offer.alpha",
		"Nested offer_id was not extracted."
	)
	_expect(
		(metadata.get("question_fact_ids", []) as Array).size() == 1,
		"Nested question_fact_ids were not extracted."
	)
	_expect(
		metadata.get("outcome_snapshot", {}) is Dictionary
				and bool(metadata.get("outcome_snapshot", {}).get("clean", false)),
		"Nested outcome_snapshot was not extracted."
	)
	_expect(
		not metadata.has("director_secret"),
		"Unknown nested metadata field was copied."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
