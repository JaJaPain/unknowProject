class_name GenerationDiagnosticsService
extends Node

signal fallback_recorded(event: Dictionary)
signal generation_event_recorded(event: Dictionary)

const MAX_RECENT_EVENTS := 100
const WARNING_MIN_CONTENT_SOURCES := 3
const WARNING_FALLBACK_SOURCE_RATE := 0.25
const CLICK_TO_GENERATE_REPORT_WINDOW_MS := 750
const LIFECYCLE_STAGES := [
	"job_queued",
	"generation_started",
	"generation_finished",
	"validation_finished",
	"text_presented",
	"tts_cache_started",
	"tts_ready",
	"interaction_clicked",
]
# Permanent, in-repo fallback log so it can be reviewed any session (gitignored
# via logs/). res:// is writable when running from source (editor/dev); an
# exported build can't write res://, so it falls back to user://.
const FALLBACK_EVENT_LOG_PATH := "res://logs/fallback_events.jsonl"
const FALLBACK_SUMMARY_PATH := "res://logs/fallback_summary.json"
const FALLBACK_SUMMARY_TEXT_PATH := "res://logs/fallback_summary.txt"
const FALLBACK_EVENT_LOG_BACKUP_PATH := "user://fallback_events.jsonl"
const FALLBACK_SUMMARY_BACKUP_PATH := "user://fallback_summary.json"

var fallback_counts_by_type: Dictionary = {}
var fallback_counts_by_reason: Dictionary = {}
var fallback_events: Array[Dictionary] = []
var total_fallbacks := 0
var event_counts_by_type: Dictionary = {}
var event_counts_by_reason: Dictionary = {}
var source_counts: Dictionary = {}
var generation_events: Array[Dictionary] = []
var total_events := 0
var click_to_generate_reports: Array[Dictionary] = []
var _active_fallback_event_log_path := FALLBACK_EVENT_LOG_PATH
var _active_fallback_summary_path := FALLBACK_SUMMARY_PATH


func reset() -> void:
	fallback_counts_by_type.clear()
	fallback_counts_by_reason.clear()
	fallback_events.clear()
	total_fallbacks = 0
	event_counts_by_type.clear()
	event_counts_by_reason.clear()
	source_counts.clear()
	generation_events.clear()
	total_events = 0
	click_to_generate_reports.clear()


func record_fallback(
	content_type: String,
	reason: String,
	source: String = "",
	context: Dictionary = {}
) -> Dictionary:
	var clean_type := content_type.strip_edges()
	if clean_type.is_empty():
		clean_type = "unknown"
	var clean_reason := reason.strip_edges()
	if clean_reason.is_empty():
		clean_reason = "unspecified"
	var event := {
		"content_type": clean_type,
		"reason": clean_reason,
		"source": source,
		"content_source": "fallback",
		"context": context.duplicate(true),
		"time_msec": Time.get_ticks_msec(),
		"unix_time": Time.get_unix_time_from_system(),
	}
	total_fallbacks += 1
	fallback_counts_by_type[clean_type] = int(
		fallback_counts_by_type.get(clean_type, 0)
	) + 1
	fallback_counts_by_reason[clean_reason] = int(
		fallback_counts_by_reason.get(clean_reason, 0)
	) + 1
	source_counts["fallback"] = int(source_counts.get("fallback", 0)) + 1
	fallback_events.append(event)
	while fallback_events.size() > MAX_RECENT_EVENTS:
		fallback_events.pop_front()
	print(
		"[GenerationDiagnostics] fallback type=%s reason=%s source=%s count=%d" %
		[clean_type, clean_reason, source, total_fallbacks]
	)
	fallback_recorded.emit(event.duplicate(true))
	_append_fallback_event_log(event)
	_record_generation_event(
		clean_type,
		"fallback",
		source,
		context.merged({"fallback_reason": clean_reason}, true),
		false
	)
	_write_fallback_summary()
	return event


func record_event(
	content_type: String,
	reason: String,
	source: String = "",
	context: Dictionary = {}
) -> Dictionary:
	return _record_generation_event(content_type, reason, source, context)


func record_lifecycle_timestamp(
	content_type: String,
	stage: String,
	source: String = "",
	context: Dictionary = {}
) -> Dictionary:
	if not LIFECYCLE_STAGES.has(stage):
		push_warning("[GenerationDiagnostics] Unknown lifecycle stage: %s" % stage)
		return {}
	var next_context := context.duplicate(true)
	next_context["lifecycle_stage"] = stage
	if stage == "generation_started":
		_report_click_to_generate_if_recent(content_type, source, next_context)
	return _record_generation_event(content_type, stage, source, next_context)


func record_content_source(
	content_type: String,
	content_source: String,
	source: String = "",
	context: Dictionary = {}
) -> Dictionary:
	var clean_source := content_source.strip_edges()
	if clean_source.is_empty():
		clean_source = "unknown"
	var next_context := context.duplicate(true)
	next_context["content_source"] = clean_source
	source_counts[clean_source] = int(source_counts.get(clean_source, 0)) + 1
	return _record_generation_event(content_type, "content_source", source, next_context)


func summary() -> Dictionary:
	return {
		"total_fallbacks": total_fallbacks,
		"by_type": fallback_counts_by_type.duplicate(true),
		"by_reason": fallback_counts_by_reason.duplicate(true),
		"recent": fallback_events.duplicate(true),
		"total_events": total_events,
		"events_by_type": event_counts_by_type.duplicate(true),
		"events_by_reason": event_counts_by_reason.duplicate(true),
		"source_counts": source_counts.duplicate(true),
		"content_source_total": content_source_total(),
		"fallback_source_count": fallback_source_count(),
		"fallback_source_rate": fallback_source_rate(),
		"developer_warnings": developer_warnings(),
		"percentile_summaries": percentile_summaries(),
		"click_to_generate_reports": click_to_generate_reports.duplicate(true),
		"recent_events": generation_events.duplicate(true),
	}


func assert_no_click_to_generate_reports(label: String = "") -> Dictionary:
	if click_to_generate_reports.is_empty():
		return {
			"ok": true,
			"status": "no_click_to_generate_reports",
			"label": label,
			"report_count": 0,
			"reports": [],
		}
	return {
		"ok": false,
		"status": "click_to_generate_detected",
		"label": label,
		"report_count": click_to_generate_reports.size(),
		"reports": click_to_generate_reports.duplicate(true),
	}


func percentile_summaries() -> Dictionary:
	var metrics := {
		"click_to_text_ms": _duration_summary_from_pair(
			"interaction_clicked",
			"text_presented"
		),
		"click_to_audio_ms": _duration_summary_from_pair(
			"interaction_clicked",
			"tts_ready"
		),
		"queue_wait_ms": _duration_summary_from_pair(
			"job_queued",
			"generation_started"
		),
		"model_generation_ms": _duration_summary_from_pair(
			"generation_started",
			"generation_finished"
		),
		"cache": _cache_summary(),
		"stale_discard": _reason_rate_summary(["stale"]),
		"degraded_field": _reason_rate_summary([
			"validation_repaired",
			"objective_dialogue_rewritten",
			"fallback",
		]),
	}
	return metrics


func summary_text(recent_limit: int = 8) -> String:
	var lines: Array[String] = []
	lines.append("[GenerationDiagnostics] Summary")
	lines.append("- total_events: %d" % total_events)
	lines.append("- total_fallbacks: %d" % total_fallbacks)
	lines.append("- content_sources: %s" % _format_counts(source_counts))
	lines.append(
		"- fallback_source_rate: %.1f%% (%d/%d)" %
		[
			fallback_source_rate() * 100.0,
			fallback_source_count(),
			content_source_total(),
		]
	)
	var warnings: Array[String] = developer_warnings()
	if not warnings.is_empty():
		lines.append("- developer_warnings:")
		for warning in warnings:
			lines.append("  %s" % warning)
	if not click_to_generate_reports.is_empty():
		lines.append("- click_to_generate_reports: %d" % click_to_generate_reports.size())
	lines.append("- fallback_types: %s" % _format_counts(fallback_counts_by_type))
	lines.append("- fallback_reasons: %s" % _format_counts(fallback_counts_by_reason))
	lines.append("- event_reasons: %s" % _format_counts(event_counts_by_reason))
	lines.append("- percentiles: %s" % _format_percentile_summaries(percentile_summaries()))
	var recent_count: int = mini(maxi(recent_limit, 0), generation_events.size())
	if recent_count > 0:
		lines.append("- recent_events:")
		var start: int = generation_events.size() - recent_count
		for index in range(start, generation_events.size()):
			var event := generation_events[index]
			lines.append(
				"  %s/%s from %s %s" %
				[
					str(event.get("content_type", "unknown")),
					str(event.get("reason", "unknown")),
					str(event.get("source", "unknown")),
					_format_context(event.get("context", {})),
				]
			)
	return "\n".join(lines)


func print_summary() -> void:
	print(summary_text())


func fallback_event_log_path() -> String:
	return _active_fallback_event_log_path


func fallback_summary_path() -> String:
	return _active_fallback_summary_path


func clear_persistent_fallback_log() -> void:
	_remove_user_file(FALLBACK_EVENT_LOG_PATH)
	_remove_user_file(FALLBACK_SUMMARY_PATH)
	_remove_user_file(FALLBACK_SUMMARY_TEXT_PATH)
	_remove_user_file(FALLBACK_EVENT_LOG_BACKUP_PATH)
	_remove_user_file(FALLBACK_SUMMARY_BACKUP_PATH)
	_remove_user_file("user://fallback_summary.txt")


func content_source_total() -> int:
	var total := 0
	for count in source_counts.values():
		total += int(count)
	return total


func fallback_source_count() -> int:
	var total := 0
	for source in source_counts.keys():
		var source_name := str(source)
		if source_name == "fallback" or source_name.ends_with("_fallback"):
			total += int(source_counts.get(source, 0))
	return total


func fallback_source_rate() -> float:
	var total := content_source_total()
	if total <= 0:
		return 0.0
	return float(fallback_source_count()) / float(total)


func developer_warnings() -> Array[String]:
	var warnings: Array[String] = []
	var total := content_source_total()
	if total >= WARNING_MIN_CONTENT_SOURCES \
			and fallback_source_rate() >= WARNING_FALLBACK_SOURCE_RATE:
		warnings.append(
			"High fallback source rate: %.1f%% (%d/%d content sources)." %
			[
				fallback_source_rate() * 100.0,
				fallback_source_count(),
				total,
			]
		)
	if not click_to_generate_reports.is_empty():
		warnings.append(
			"Player-facing click-to-generate reports: %d. Report-only until V2 gates enforce cache-first paths." %
			click_to_generate_reports.size()
		)
	return warnings


func _report_click_to_generate_if_recent(
	content_type: String,
	source: String,
	context: Dictionary
) -> void:
	var now := Time.get_ticks_msec()
	for index in range(generation_events.size() - 1, -1, -1):
		var event: Dictionary = generation_events[index]
		var stage := str(event.get("context", {}).get("lifecycle_stage", event.get("reason", "")))
		if stage != "interaction_clicked":
			continue
		var elapsed_ms := now - int(event.get("time_msec", 0))
		if elapsed_ms < 0:
			return
		if elapsed_ms > CLICK_TO_GENERATE_REPORT_WINDOW_MS:
			return
		var interaction_context: Dictionary = event.get("context", {})
		var report := {
			"content_type": content_type,
			"source": source,
			"elapsed_ms": elapsed_ms,
			"interaction_name": str(interaction_context.get("interaction_name", "")),
			"generation_context": context.duplicate(true),
			"time_msec": now,
			"unix_time": Time.get_unix_time_from_system(),
		}
		click_to_generate_reports.append(report)
		while click_to_generate_reports.size() > MAX_RECENT_EVENTS:
			click_to_generate_reports.pop_front()
		push_warning(
			"[GenerationDiagnostics] Report-only click-to-generate path: %s after '%s' in %dms" %
			[content_type, str(report.get("interaction_name", "")), elapsed_ms]
		)
		return


func _duration_summary_from_pair(start_stage: String, end_stage: String) -> Dictionary:
	var durations: Array[float] = []
	var last_start_msec := -1
	for event in generation_events:
		var stage := str(event.get("context", {}).get("lifecycle_stage", event.get("reason", "")))
		if stage == start_stage:
			last_start_msec = int(event.get("time_msec", 0))
		elif stage == end_stage and last_start_msec >= 0:
			var end_msec := int(event.get("time_msec", 0))
			if end_msec >= last_start_msec:
				durations.append(float(end_msec - last_start_msec))
			last_start_msec = -1
	return _percentile_summary(durations)


func _percentile_summary(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {
			"count": 0,
			"p50": 0.0,
			"p95": 0.0,
			"p99": 0.0,
		}
	var sorted := values.duplicate()
	sorted.sort()
	return {
		"count": sorted.size(),
		"p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95),
		"p99": _percentile(sorted, 0.99),
	}


func _percentile(sorted_values: Array, percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := int(ceil(percentile * float(sorted_values.size())) - 1.0)
	index = clampi(index, 0, sorted_values.size() - 1)
	return float(sorted_values[index])


func _cache_summary() -> Dictionary:
	var hit_count := 0
	var ready_count := 0
	for event in generation_events:
		var stage := str(event.get("context", {}).get("lifecycle_stage", event.get("reason", "")))
		if stage != "tts_ready":
			continue
		ready_count += 1
		if str(event.get("context", {}).get("cache_state", "")) == "already_cached":
			hit_count += 1
	var miss_count := int(event_counts_by_reason.get("tts_cache_started", 0))
	var total := hit_count + miss_count
	var hit_rate := 0.0
	if total > 0:
		hit_rate = float(hit_count) / float(total)
	return {
		"hits": hit_count,
		"misses": miss_count,
		"ready": ready_count,
		"hit_rate": hit_rate,
	}


func _reason_rate_summary(markers: Array[String]) -> Dictionary:
	var count := 0
	for reason in event_counts_by_reason.keys():
		var reason_text := str(reason)
		var matched := false
		for marker in markers:
			if reason_text.find(marker) != -1:
				matched = true
				break
		if matched:
			count += int(event_counts_by_reason.get(reason, 0))
	var rate := 0.0
	if total_events > 0:
		rate = float(count) / float(total_events)
	return {
		"count": count,
		"rate": rate,
	}


func _format_percentile_summaries(metrics: Dictionary) -> String:
	var parts: Array[String] = []
	for key in [
		"click_to_text_ms",
		"click_to_audio_ms",
		"queue_wait_ms",
		"model_generation_ms",
	]:
		var metric: Dictionary = metrics.get(key, {})
		parts.append(
			"%s(count=%d,p50=%.0f,p95=%.0f,p99=%.0f)" %
			[
				key,
				int(metric.get("count", 0)),
				float(metric.get("p50", 0.0)),
				float(metric.get("p95", 0.0)),
				float(metric.get("p99", 0.0)),
			]
		)
	var cache: Dictionary = metrics.get("cache", {})
	parts.append(
		"cache(hits=%d,misses=%d,hit_rate=%.1f%%)" %
		[
			int(cache.get("hits", 0)),
			int(cache.get("misses", 0)),
			float(cache.get("hit_rate", 0.0)) * 100.0,
		]
	)
	var stale: Dictionary = metrics.get("stale_discard", {})
	parts.append(
		"stale_discard(count=%d,rate=%.1f%%)" %
		[
			int(stale.get("count", 0)),
			float(stale.get("rate", 0.0)) * 100.0,
		]
	)
	var degraded: Dictionary = metrics.get("degraded_field", {})
	parts.append(
		"degraded_field(count=%d,rate=%.1f%%)" %
		[
			int(degraded.get("count", 0)),
			float(degraded.get("rate", 0.0)) * 100.0,
		]
	)
	return ", ".join(parts)


func _record_generation_event(
	content_type: String,
	reason: String,
	source: String = "",
	context: Dictionary = {},
	should_print: bool = true
) -> Dictionary:
	var clean_type := content_type.strip_edges()
	if clean_type.is_empty():
		clean_type = "unknown"
	var clean_reason := reason.strip_edges()
	if clean_reason.is_empty():
		clean_reason = "unspecified"
	var event := {
		"content_type": clean_type,
		"reason": clean_reason,
		"source": source,
		"context": context.duplicate(true),
		"time_msec": Time.get_ticks_msec(),
		"unix_time": Time.get_unix_time_from_system(),
	}
	total_events += 1
	event_counts_by_type[clean_type] = int(event_counts_by_type.get(clean_type, 0)) + 1
	event_counts_by_reason[clean_reason] = int(event_counts_by_reason.get(clean_reason, 0)) + 1
	generation_events.append(event)
	while generation_events.size() > MAX_RECENT_EVENTS:
		generation_events.pop_front()
	if should_print:
		print(
			"[GenerationDiagnostics] event type=%s reason=%s source=%s count=%d" %
			[clean_type, clean_reason, source, total_events]
		)
	generation_event_recorded.emit(event.duplicate(true))
	return event


func _append_fallback_event_log(event: Dictionary) -> void:
	var path := _resolve_writable_fallback_path(
		FALLBACK_EVENT_LOG_PATH,
		FALLBACK_EVENT_LOG_BACKUP_PATH
	)
	_active_fallback_event_log_path = path
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning(
			"[GenerationDiagnostics] Could not open fallback event log: %s" %
			path
		)
		return
	file.seek_end()
	file.store_line(JSON.stringify(event))
	file.close()


func _write_fallback_summary() -> void:
	var path := _resolve_writable_fallback_path(
		FALLBACK_SUMMARY_PATH,
		FALLBACK_SUMMARY_BACKUP_PATH
	)
	_active_fallback_summary_path = path
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning(
			"[GenerationDiagnostics] Could not write fallback summary: %s" %
			path
		)
		return
	file.store_string(JSON.stringify(summary(), "\t"))
	file.close()
	# Human-readable sibling so the status can be eyeballed without parsing JSON.
	var text_path := path.get_base_dir().path_join("fallback_summary.txt")
	var text_file := FileAccess.open(text_path, FileAccess.WRITE)
	if text_file != null:
		text_file.store_string(summary_text(20))
		text_file.close()


func _remove_user_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var global_path := ProjectSettings.globalize_path(path)
	var err := DirAccess.remove_absolute(global_path)
	if err != OK:
		push_warning("[GenerationDiagnostics] Could not remove %s (err=%d)." % [path, err])


func _resolve_writable_fallback_path(primary_path: String, backup_path: String) -> String:
	if _can_open_for_write(primary_path):
		return primary_path
	_ensure_parent_dir(backup_path)
	return backup_path


func _can_open_for_write(path: String) -> bool:
	_ensure_parent_dir(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	return true


func _ensure_parent_dir(path: String) -> void:
	var base_dir := path.get_base_dir()
	if base_dir.is_empty():
		return
	var global_dir := ProjectSettings.globalize_path(base_dir)
	if not DirAccess.dir_exists_absolute(global_dir):
		DirAccess.make_dir_recursive_absolute(global_dir)


func _format_counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "(none)"
	var keys := counts.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s=%d" % [str(key), int(counts.get(key, 0))])
	return ", ".join(parts)


func _format_context(context: Variant) -> String:
	if not context is Dictionary or context.is_empty():
		return ""
	var context_dict := context as Dictionary
	var keys := context_dict.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s=%s" % [str(key), str(context_dict.get(key, ""))])
	return "(%s)" % ", ".join(parts)
