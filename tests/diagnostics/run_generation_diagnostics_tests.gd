extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	GenerationDiagnostics.reset()
	_test_records_fallback_summary()
	_test_records_generation_event_summary()
	_test_records_content_source_summary()
	_test_summary_text_is_readable()
	_test_reset_clears_summary()

	if _failures.is_empty():
		print("[PASS] Generation diagnostics tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_records_fallback_summary() -> void:
	GenerationDiagnostics.record_fallback(
		"quest_generation",
		"http_failed",
		"test",
		{"model": "local-test"}
	)
	GenerationDiagnostics.record_fallback(
		"quest_generation",
		"parse_failed",
		"test",
		{}
	)
	var summary: Dictionary = GenerationDiagnostics.summary()
	_expect(
		int(summary.get("total_fallbacks", 0)) == 2,
		"Expected two recorded fallbacks."
	)
	_expect(
		int(summary.get("by_type", {}).get("quest_generation", 0)) == 2,
		"Type count was not recorded."
	)
	_expect(
		int(summary.get("by_reason", {}).get("http_failed", 0)) == 1,
		"Reason count was not recorded."
	)
	_expect(
		(summary.get("recent", []) as Array).size() == 2,
		"Recent fallback list was not recorded."
	)
	_expect(
		int(summary.get("events_by_reason", {}).get("fallback", 0)) == 2,
		"Fallbacks were not mirrored into generation events."
	)


func _test_records_generation_event_summary() -> void:
	GenerationDiagnostics.record_event(
		"quest_generation",
		"validation_repaired",
		"test",
		{"field": "amount_required"}
	)
	var summary: Dictionary = GenerationDiagnostics.summary()
	_expect(
		int(summary.get("total_events", 0)) == 3,
		"Expected fallback mirrors plus one generation event."
	)
	_expect(
		int(summary.get("events_by_reason", {}).get("validation_repaired", 0)) == 1,
		"Generation event reason count was not recorded."
	)
	_expect(
		(summary.get("recent_events", []) as Array).size() == 3,
		"Recent generation event list was not recorded."
	)


func _test_records_content_source_summary() -> void:
	GenerationDiagnostics.record_content_source(
		"quest_generation",
		"llm",
		"test",
		{"model": "local-test"}
	)
	GenerationDiagnostics.record_content_source(
		"quest_generation",
		"procedural_fallback",
		"test",
		{}
	)
	var summary: Dictionary = GenerationDiagnostics.summary()
	_expect(
		int(summary.get("source_counts", {}).get("llm", 0)) == 1,
		"LLM content source count was not recorded."
	)
	_expect(
		int(summary.get("source_counts", {}).get("procedural_fallback", 0)) == 1,
		"Procedural fallback content source count was not recorded."
	)


func _test_summary_text_is_readable() -> void:
	var text := GenerationDiagnostics.summary_text()
	_expect(
		text.contains("total_fallbacks: 2"),
		"Summary text did not include total fallback count."
	)
	_expect(
		text.contains("llm=1"),
		"Summary text did not include LLM source count."
	)
	_expect(
		text.contains("procedural_fallback=1"),
		"Summary text did not include procedural fallback source count."
	)
	_expect(
		text.contains("recent_events"),
		"Summary text did not include recent events."
	)


func _test_reset_clears_summary() -> void:
	GenerationDiagnostics.reset()
	var summary: Dictionary = GenerationDiagnostics.summary()
	_expect(
		int(summary.get("total_fallbacks", -1)) == 0,
		"Reset did not clear total fallback count."
	)
	_expect(
		(summary.get("recent", []) as Array).is_empty(),
		"Reset did not clear recent fallback events."
	)
	_expect(
		(summary.get("recent_events", []) as Array).is_empty(),
		"Reset did not clear recent generation events."
	)
	_expect(
		(summary.get("source_counts", {}) as Dictionary).is_empty(),
		"Reset did not clear source counts."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
