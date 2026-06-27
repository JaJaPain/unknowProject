extends SceneTree

const DiagnosticsType := preload("res://scripts/diagnostics/GenerationDiagnostics.gd")

var _failures: Array[String] = []
var diagnostics: GenerationDiagnosticsService


func _initialize() -> void:
	diagnostics = DiagnosticsType.new()
	diagnostics.reset()
	diagnostics.clear_persistent_fallback_log()
	_test_records_fallback_summary()
	_test_persistent_fallback_log_written()
	_test_records_generation_event_summary()
	_test_records_content_source_summary()
	_test_summary_text_is_readable()
	_test_developer_warning_marks_high_fallback_rate()
	_test_reset_clears_summary()
	diagnostics.clear_persistent_fallback_log()

	if _failures.is_empty():
		print("[PASS] Generation diagnostics tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_records_fallback_summary() -> void:
	diagnostics.record_fallback(
		"quest_generation",
		"http_failed",
		"test",
		{"model": "local-test"}
	)
	diagnostics.record_fallback(
		"quest_generation",
		"parse_failed",
		"test",
		{}
	)
	var summary: Dictionary = diagnostics.summary()
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


func _test_persistent_fallback_log_written() -> void:
	var log_path := diagnostics.fallback_event_log_path()
	var summary_path := diagnostics.fallback_summary_path()
	_expect(FileAccess.file_exists(log_path), "Persistent fallback event log was not written.")
	_expect(FileAccess.file_exists(summary_path), "Persistent fallback summary was not written.")
	var log_file := FileAccess.open(log_path, FileAccess.READ)
	_expect(log_file != null, "Persistent fallback event log could not be opened.")
	if log_file == null:
		return
	var rows: Array[String] = []
	while not log_file.eof_reached():
		var line := log_file.get_line().strip_edges()
		if not line.is_empty():
			rows.append(line)
	log_file.close()
	_expect(rows.size() == 2, "Persistent fallback event log did not contain two rows.")
	var parsed := JSON.new()
	_expect(parsed.parse(rows[0]) == OK, "Persistent fallback event row was not valid JSON.")
	var event = parsed.get_data()
	_expect(event is Dictionary, "Persistent fallback event row was not a Dictionary.")
	if event is Dictionary:
		_expect(
			str(event.get("content_type", "")) == "quest_generation",
			"Persistent fallback event did not include content type."
		)
		_expect(
			str(event.get("content_source", "")) == "fallback",
			"Persistent fallback event did not include fallback content source."
		)
	var summary_file := FileAccess.open(summary_path, FileAccess.READ)
	_expect(summary_file != null, "Persistent fallback summary could not be opened.")
	if summary_file == null:
		return
	var summary_json := summary_file.get_as_text()
	summary_file.close()
	var summary_parse := JSON.new()
	_expect(summary_parse.parse(summary_json) == OK, "Persistent fallback summary was not valid JSON.")
	var persisted_summary = summary_parse.get_data()
	_expect(persisted_summary is Dictionary, "Persistent fallback summary was not a Dictionary.")
	if persisted_summary is Dictionary:
		_expect(
			int(persisted_summary.get("total_fallbacks", 0)) == 2,
			"Persistent fallback summary did not include fallback count."
		)


func _test_records_generation_event_summary() -> void:
	diagnostics.record_event(
		"quest_generation",
		"validation_repaired",
		"test",
		{"field": "amount_required"}
	)
	var summary: Dictionary = diagnostics.summary()
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
	diagnostics.record_content_source(
		"quest_generation",
		"llm",
		"test",
		{"model": "local-test"}
	)
	diagnostics.record_content_source(
		"quest_generation",
		"procedural_fallback",
		"test",
		{}
	)
	diagnostics.record_content_source(
		"kaelen_reaction",
		"static_fallback",
		"test",
		{}
	)
	var summary: Dictionary = diagnostics.summary()
	_expect(
		int(summary.get("source_counts", {}).get("llm", 0)) == 1,
		"LLM content source count was not recorded."
	)
	_expect(
		int(summary.get("source_counts", {}).get("procedural_fallback", 0)) == 1,
		"Procedural fallback content source count was not recorded."
	)
	_expect(
		int(summary.get("source_counts", {}).get("static_fallback", 0)) == 1,
		"Static fallback content source count was not recorded."
	)
	_expect(
		int(summary.get("source_counts", {}).get("fallback", 0)) == 2,
		"Direct fallback content source count was not recorded."
	)
	_expect(
		int(summary.get("content_source_total", 0)) == 5,
		"Content source total was not recorded."
	)
	_expect(
		int(summary.get("fallback_source_count", 0)) == 4,
		"Fallback source count was not recorded."
	)


func _test_summary_text_is_readable() -> void:
	var text := diagnostics.summary_text()
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
		text.contains("static_fallback=1"),
		"Summary text did not include static fallback source count."
	)
	_expect(
		text.contains("fallback=2"),
		"Summary text did not include direct fallback source count."
	)
	_expect(
		text.contains("fallback_source_rate: 80.0%"),
		"Summary text did not include fallback source rate."
	)
	_expect(
		text.contains("developer_warnings"),
		"Summary text did not include developer warnings."
	)
	_expect(
		text.contains("recent_events"),
		"Summary text did not include recent events."
	)


func _test_developer_warning_marks_high_fallback_rate() -> void:
	var summary: Dictionary = diagnostics.summary()
	var warnings: Array = summary.get("developer_warnings", [])
	_expect(
		not warnings.is_empty(),
		"High fallback source rate did not produce a developer warning."
	)
	_expect(
		float(summary.get("fallback_source_rate", 0.0)) > 0.6,
		"Fallback source rate was not calculated."
	)


func _test_reset_clears_summary() -> void:
	diagnostics.reset()
	var summary: Dictionary = diagnostics.summary()
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
	_expect(
		(summary.get("developer_warnings", []) as Array).is_empty(),
		"Reset did not clear developer warnings."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
