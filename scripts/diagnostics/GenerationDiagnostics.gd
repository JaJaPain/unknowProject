extends Node

signal fallback_recorded(event: Dictionary)

const MAX_RECENT_EVENTS := 100

var fallback_counts_by_type: Dictionary = {}
var fallback_counts_by_reason: Dictionary = {}
var fallback_events: Array[Dictionary] = []
var total_fallbacks := 0


func reset() -> void:
	fallback_counts_by_type.clear()
	fallback_counts_by_reason.clear()
	fallback_events.clear()
	total_fallbacks = 0


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
	return event


func summary() -> Dictionary:
	return {
		"total_fallbacks": total_fallbacks,
		"by_type": fallback_counts_by_type.duplicate(true),
		"by_reason": fallback_counts_by_reason.duplicate(true),
		"recent": fallback_events.duplicate(true),
	}


func print_summary() -> void:
	var data := summary()
	print("[GenerationDiagnostics] summary: ", JSON.stringify(data))
