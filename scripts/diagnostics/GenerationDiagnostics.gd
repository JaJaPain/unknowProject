class_name GenerationDiagnosticsService
extends Node

signal fallback_recorded(event: Dictionary)
signal generation_event_recorded(event: Dictionary)

const MAX_RECENT_EVENTS := 100
const WARNING_MIN_CONTENT_SOURCES := 3
const WARNING_FALLBACK_SOURCE_RATE := 0.25

var fallback_counts_by_type: Dictionary = {}
var fallback_counts_by_reason: Dictionary = {}
var fallback_events: Array[Dictionary] = []
var total_fallbacks := 0
var event_counts_by_type: Dictionary = {}
var event_counts_by_reason: Dictionary = {}
var source_counts: Dictionary = {}
var generation_events: Array[Dictionary] = []
var total_events := 0


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
	}
	total_fallbacks += 1
	fallback_counts_by_type[clean_type] = int(
		fallback_counts_by_type.get(clean_type, 0)
	) + 1
	fallback_counts_by_reason[clean_reason] = int(
		fallback_counts_by_reason.get(clean_reason, 0)
	) + 1
	fallback_events.append(event)
	while fallback_events.size() > MAX_RECENT_EVENTS:
		fallback_events.pop_front()
	print(
		"[GenerationDiagnostics] fallback type=%s reason=%s source=%s count=%d" %
		[clean_type, clean_reason, source, total_fallbacks]
	)
	fallback_recorded.emit(event.duplicate(true))
	_record_generation_event(
		clean_type,
		"fallback",
		source,
		context.merged({"fallback_reason": clean_reason}, true),
		false
	)
	return event


func record_event(
	content_type: String,
	reason: String,
	source: String = "",
	context: Dictionary = {}
) -> Dictionary:
	return _record_generation_event(content_type, reason, source, context)


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
		"recent_events": generation_events.duplicate(true),
	}


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
	lines.append("- fallback_types: %s" % _format_counts(fallback_counts_by_type))
	lines.append("- fallback_reasons: %s" % _format_counts(fallback_counts_by_reason))
	lines.append("- event_reasons: %s" % _format_counts(event_counts_by_reason))
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
	return warnings


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
