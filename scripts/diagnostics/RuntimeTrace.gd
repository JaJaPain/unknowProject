class_name RuntimeTrace
extends RefCounted

const TRACE_DIRECTORY := "user://diagnostics"
const TRACE_PATH := TRACE_DIRECTORY + "/runtime_trace.jsonl"
const PREVIOUS_TRACE_PATH := TRACE_DIRECTORY + "/runtime_trace.previous.jsonl"

static var _session_started: bool = false
static var _session_id: String = ""


static func begin_session() -> void:
	if _session_started:
		return
	_session_started = true
	_session_id = "%s-%d" % [
		Time.get_datetime_string_from_system(true).replace(":", "-"),
		Time.get_ticks_msec(),
	]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(TRACE_DIRECTORY)
	)
	if FileAccess.file_exists(TRACE_PATH):
		var current_path := ProjectSettings.globalize_path(TRACE_PATH)
		var previous_path := ProjectSettings.globalize_path(
			PREVIOUS_TRACE_PATH
		)
		if FileAccess.file_exists(PREVIOUS_TRACE_PATH):
			DirAccess.remove_absolute(previous_path)
		DirAccess.copy_absolute(current_path, previous_path)
		DirAccess.remove_absolute(current_path)
	event("session", "started", {
		"engine_version": Engine.get_version_info().get("string", ""),
		"trace_path": ProjectSettings.globalize_path(TRACE_PATH),
	})


static func event(
	category: String,
	event_name: String,
	details: Dictionary = {}
) -> void:
	if not _session_started:
		begin_session()
	var payload := {
		"timestamp_utc": Time.get_datetime_string_from_system(true),
		"ticks_msec": Time.get_ticks_msec(),
		"session_id": _session_id,
		"category": category,
		"event": event_name,
		"details": details,
	}
	var file := FileAccess.open(TRACE_PATH, FileAccess.READ_WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify(payload))
	file.flush()


static func absolute_path() -> String:
	return ProjectSettings.globalize_path(TRACE_PATH)
