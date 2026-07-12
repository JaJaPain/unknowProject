class_name NarrativeCacheScheduler
extends RefCounted

const PRIORITY_P0 := 0
const PRIORITY_P1 := 10
const PRIORITY_P2 := 20
const PRIORITY_P3 := 30

const TRIGGER_OBJECTIVE_COMPLETE_TURN_IN := "objective_complete_turn_in"
const TRIGGER_CURRENT_VISIBLE_STATION := "current_visible_station"
const TRIGGER_CURRENT_SYSTEM_AGENT := "current_system_agent"
const TRIGGER_CURRENT_SYSTEM_KAELEN := "current_system_kaelen"
const TRIGGER_CURRENT_SYSTEM_NOVA := "current_system_nova"
const TRIGGER_LIKELY_LOUNGE := "likely_lounge"
const TRIGGER_MECHANIC_GREETING := "mechanic_greeting"
const TRIGGER_NEARBY_SYSTEM := "nearby_system"
const TRIGGER_AMBIENT_REPLENISHMENT := "ambient_replenishment"

var _jobs: Dictionary = {}
var _sequence := 0
var _stats := {
	"queued": 0,
	"started": 0,
	"ready": 0,
	"canceled": 0,
	"stale_discarded": 0,
	"degraded": 0,
	"retry_queued": 0,
}
var _paused := false
var _pause_reason := ""
var max_concurrent_generations := 1


func queue_job(job: Dictionary) -> Dictionary:
	var job_id := str(job.get("job_id", "")).strip_edges()
	if job_id.is_empty():
		return _failure("Narrative cache job requires job_id.")
	var cache_key := str(job.get("cache_key", "")).strip_edges()
	if cache_key.is_empty():
		return _failure("Narrative cache job requires cache_key.")
	var existing_key_job_id := _find_active_job_id_by_cache_key(cache_key)
	if not existing_key_job_id.is_empty() and existing_key_job_id != job_id:
		var existing: Dictionary = _jobs[existing_key_job_id]
		existing["priority"] = min(
			int(existing.get("priority", PRIORITY_P2)),
			int(job.get("priority", PRIORITY_P2))
		)
		_add_requester(existing, job)
		_jobs[existing_key_job_id] = existing
		return {
			"ok": true,
			"deduped": true,
			"job": existing.duplicate(true),
		}
	var prepared := _prepare_job(job)
	prepared["job_id"] = job_id
	prepared["cache_key"] = cache_key
	if not _jobs.has(job_id):
		_sequence += 1
		prepared["sequence"] = _sequence
		prepared["diagnostic_timestamps"] = {}
		_stamp(prepared, "job_queued")
		_add_requester(prepared, job)
		_stats["queued"] = int(_stats.get("queued", 0)) + 1
	else:
		var existing: Dictionary = _jobs[job_id]
		prepared["sequence"] = int(existing.get("sequence", 0))
		prepared["diagnostic_timestamps"] = (
			existing.get("diagnostic_timestamps", {}) as Dictionary
		).duplicate(true)
		prepared["requesters"] = (
			existing.get("requesters", []) as Array
		).duplicate(true)
		_add_requester(prepared, job)
		prepared["diagnostic_timestamps"]["job_queued"] = int(
			prepared["diagnostic_timestamps"].get(
				"job_queued",
				Time.get_unix_time_from_system()
			)
		)
	prepared["status"] = str(prepared.get("status", "queued"))
	_jobs[job_id] = prepared
	return {"ok": true, "job": prepared.duplicate(true)}


func jobs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw in _jobs.values():
		if raw is Dictionary:
			result.append((raw as Dictionary).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_priority := int(left.get("priority", PRIORITY_P2))
		var right_priority := int(right.get("priority", PRIORITY_P2))
		if left_priority != right_priority:
			return left_priority < right_priority
		return int(left.get("sequence", 0)) < int(right.get("sequence", 0))
	)
	return result


func pending_jobs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for job in jobs():
		if str(job.get("status", "")) == "queued":
			result.append(job)
	return result


func next_job() -> Dictionary:
	if _paused:
		return {}
	if _in_flight_count() >= max(1, max_concurrent_generations):
		return {}
	var pending := pending_jobs()
	if pending.is_empty():
		return {}
	return pending[0].duplicate(true)


func pause(reason: String = "large_model_gate") -> Dictionary:
	_paused = true
	_pause_reason = reason
	return {"ok": true, "paused": true, "reason": _pause_reason}


func resume() -> Dictionary:
	_paused = false
	_pause_reason = ""
	return {"ok": true, "paused": false}


func is_paused() -> bool:
	return _paused


static func priority_for_trigger(trigger: String) -> int:
	match trigger.strip_edges():
		TRIGGER_OBJECTIVE_COMPLETE_TURN_IN, TRIGGER_CURRENT_VISIBLE_STATION:
			return PRIORITY_P0
		TRIGGER_CURRENT_SYSTEM_AGENT, TRIGGER_CURRENT_SYSTEM_KAELEN, TRIGGER_CURRENT_SYSTEM_NOVA:
			return PRIORITY_P1
		TRIGGER_LIKELY_LOUNGE, TRIGGER_MECHANIC_GREETING, TRIGGER_NEARBY_SYSTEM:
			return PRIORITY_P2
		TRIGGER_AMBIENT_REPLENISHMENT:
			return PRIORITY_P3
		_:
			return PRIORITY_P2


static func priority_label(priority: int) -> String:
	match priority:
		PRIORITY_P0:
			return "P0"
		PRIORITY_P1:
			return "P1"
		PRIORITY_P2:
			return "P2"
		PRIORITY_P3:
			return "P3"
		_:
			return "P?"


func mark_generation_started(job_id: String) -> Dictionary:
	if _paused:
		return _failure("Narrative cache scheduler is paused.")
	var current := get_job(job_id)
	if current.is_empty():
		return _failure("Narrative cache job not found.")
	if str(current.get("status", "")) != "in_flight" \
			and _in_flight_count() >= max(1, max_concurrent_generations):
		return _failure("Narrative cache generation concurrency limit reached.")
	return _transition(job_id, "in_flight", "generation_started", "started")


func mark_generation_finished(job_id: String) -> Dictionary:
	return _stamp_existing(job_id, "generation_finished")


func mark_validation_finished(job_id: String, degraded: bool = false) -> Dictionary:
	var result := _stamp_existing(job_id, "validation_finished")
	if bool(result.get("ok", false)) and degraded:
		var job: Dictionary = _jobs[job_id]
		job["degraded"] = true
		_jobs[job_id] = job
		_stats["degraded"] = int(_stats.get("degraded", 0)) + 1
	return result


func mark_validation_failed(
	job_id: String,
	field_errors: Array = [],
	max_retries: int = 1
) -> Dictionary:
	var clean_id := job_id.strip_edges()
	if not _jobs.has(clean_id):
		return _failure("Narrative cache job not found.")
	var job: Dictionary = _jobs[clean_id]
	var retry_count := int(job.get("retry_count", 0))
	job["validation_errors"] = field_errors.duplicate(true)
	_stamp(job, "validation_finished")
	if retry_count < max_retries:
		retry_count += 1
		job["retry_count"] = retry_count
		job["status"] = "queued"
		_stamp(job, "retry_queued")
		_jobs[clean_id] = job
		_stats["retry_queued"] = int(_stats.get("retry_queued", 0)) + 1
		return {"ok": true, "retry_queued": true, "job": job.duplicate(true)}
	job["status"] = "degraded_required"
	job["degraded"] = true
	_stamp(job, "degraded_required")
	_jobs[clean_id] = job
	_stats["degraded"] = int(_stats.get("degraded", 0)) + 1
	return {"ok": true, "retry_queued": false, "job": job.duplicate(true)}


func mark_ready(job_id: String, result_payload: Dictionary = {}) -> Dictionary:
	var result := _transition(job_id, "ready", "text_presented", "ready")
	if bool(result.get("ok", false)) and not result_payload.is_empty():
		var clean_id := job_id.strip_edges()
		var job: Dictionary = _jobs[clean_id]
		job["result_payload"] = result_payload.duplicate(true)
		_jobs[clean_id] = job
		result["job"] = job.duplicate(true)
	return result


func mark_tts_cache_started(job_id: String) -> Dictionary:
	return _stamp_existing(job_id, "tts_cache_started")


func mark_tts_ready(job_id: String) -> Dictionary:
	return _stamp_existing(job_id, "tts_ready")


func cancel_job(job_id: String, reason: String = "canceled") -> Dictionary:
	var clean_id := job_id.strip_edges()
	if not _jobs.has(clean_id):
		return _failure("Narrative cache job not found.")
	var job: Dictionary = _jobs[clean_id]
	if str(job.get("status", "")) == "ready":
		return _failure("Ready narrative cache jobs cannot be canceled.")
	job["status"] = "canceled"
	job["cancel_reason"] = reason
	_stamp(job, "canceled")
	_jobs[clean_id] = job
	_stats["canceled"] = int(_stats.get("canceled", 0)) + 1
	return {"ok": true, "job": job.duplicate(true)}


func cancel_jobs(criteria: Dictionary, reason: String = "scope_canceled") -> Dictionary:
	var canceled: Array[String] = []
	for job_id in _jobs.keys():
		var raw: Variant = _jobs[job_id]
		if not raw is Dictionary:
			continue
		var job: Dictionary = raw
		if str(job.get("status", "")) != "queued":
			continue
		if not _job_matches_all_scope_criteria(job, criteria):
			continue
		job["status"] = "canceled"
		job["cancel_reason"] = reason
		_stamp(job, "canceled")
		_jobs[job_id] = job
		canceled.append(str(job_id))
	_stats["canceled"] = int(_stats.get("canceled", 0)) + canceled.size()
	return {"ok": true, "canceled": canceled}


func discard_stale_jobs(criteria: Dictionary) -> Dictionary:
	var removed: Array[String] = []
	for job_id in _jobs.keys():
		var raw: Variant = _jobs[job_id]
		if not raw is Dictionary:
			continue
		var job: Dictionary = raw
		if str(job.get("status", "")) not in ["queued", "in_flight"]:
			continue
		if bool(job.get("truth_frozen", false)) \
				or str(job.get("status", "")) == "accepted":
			continue
		if _job_matches_any_stale_criterion(job, criteria):
			job["status"] = "stale_discarded"
			_stamp(job, "stale_discarded")
			_jobs[job_id] = job
			removed.append(str(job_id))
	_stats["stale_discarded"] = int(_stats.get("stale_discarded", 0)) + removed.size()
	return {"ok": true, "removed": removed}


func stats() -> Dictionary:
	var result := _stats.duplicate(true)
	result["pending"] = pending_jobs().size()
	result["total_jobs"] = _jobs.size()
	result["paused"] = _paused
	result["pause_reason"] = _pause_reason
	result["in_flight"] = _in_flight_count()
	result["max_concurrent_generations"] = max(1, max_concurrent_generations)
	return result


func diagnostic_summary() -> Dictionary:
	var ready_durations: Array[int] = []
	var queue_waits: Array[int] = []
	var generation_durations: Array[int] = []
	var validation_waits: Array[int] = []
	for raw in _jobs.values():
		if not raw is Dictionary:
			continue
		var stamps: Dictionary = (raw as Dictionary).get(
			"diagnostic_timestamps",
			{}
		)
		_append_delta(queue_waits, stamps, "job_queued", "generation_started")
		_append_delta(
			generation_durations,
			stamps,
			"generation_started",
			"generation_finished"
		)
		_append_delta(
			validation_waits,
			stamps,
			"generation_finished",
			"validation_finished"
		)
		_append_delta(ready_durations, stamps, "job_queued", "text_presented")
	return {
		"queue_wait": _duration_summary(queue_waits),
		"generation": _duration_summary(generation_durations),
		"validation": _duration_summary(validation_waits),
		"time_to_ready": _duration_summary(ready_durations),
	}


func queue_health(max_queue_wait_seconds: int = 30) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var starved: Array[Dictionary] = []
	var pending_by_priority: Dictionary = {}
	var in_flight: Array[String] = []
	for job in jobs():
		var status := str(job.get("status", ""))
		if status == "queued":
			var priority: int = int(job.get("priority", PRIORITY_P2))
			pending_by_priority[str(priority)] = int(
				pending_by_priority.get(str(priority), 0)
			) + 1
			var age: int = max(0, now - int(job.get("queued_at_unix", now)))
			if age >= max_queue_wait_seconds:
				starved.append({
					"job_id": str(job.get("job_id", "")),
					"cache_key": str(job.get("cache_key", "")),
					"priority": priority,
					"age_seconds": age,
				})
		elif status == "in_flight":
			in_flight.append(str(job.get("job_id", "")))
	return {
		"paused": _paused,
		"pause_reason": _pause_reason,
		"in_flight": in_flight,
		"in_flight_count": in_flight.size(),
		"max_concurrent_generations": max(1, max_concurrent_generations),
		"contention": in_flight.size() >= max(1, max_concurrent_generations)
			and pending_jobs().size() > 0,
		"pending_by_priority": pending_by_priority,
		"starved_jobs": starved,
	}


func can_refill_pool(
	current_count: int,
	target_count: int,
	refill_priority: int = PRIORITY_P3
) -> bool:
	if _paused:
		return false
	if current_count >= target_count:
		return false
	if _in_flight_count() > 0:
		return false
	for job in pending_jobs():
		if int(job.get("priority", PRIORITY_P2)) < refill_priority:
			return false
	return true


func get_job(job_id: String) -> Dictionary:
	var clean_id := job_id.strip_edges()
	if not _jobs.has(clean_id):
		return {}
	var raw: Variant = _jobs[clean_id]
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


func ready_result_for_requester(requester_id: String) -> Dictionary:
	var clean_requester := requester_id.strip_edges()
	if clean_requester.is_empty():
		return {}
	for raw in _jobs.values():
		if not raw is Dictionary:
			continue
		var job: Dictionary = raw
		if str(job.get("status", "")) != "ready":
			continue
		var requesters: Array = job.get("requesters", [])
		if requesters.has(clean_requester):
			return {
				"job_id": str(job.get("job_id", "")),
				"cache_key": str(job.get("cache_key", "")),
				"result_payload": (
					job.get("result_payload", {}) as Dictionary
				).duplicate(true) if job.get("result_payload", {}) is Dictionary else {},
			}
	return {}


func _prepare_job(job: Dictionary) -> Dictionary:
	var prepared := job.duplicate(true)
	prepared["kind"] = str(prepared.get("kind", "mission_conversation")).strip_edges()
	prepared["priority"] = int(prepared.get("priority", PRIORITY_P2))
	prepared["queued_at_unix"] = int(Time.get_unix_time_from_system())
	return prepared


func _find_active_job_id_by_cache_key(cache_key: String) -> String:
	for job_id in _jobs.keys():
		var raw: Variant = _jobs[job_id]
		if not raw is Dictionary:
			continue
		var job: Dictionary = raw
		if str(job.get("cache_key", "")) != cache_key:
			continue
		if str(job.get("status", "")) in ["queued", "in_flight"]:
			return str(job_id)
	return ""


func _in_flight_count() -> int:
	var count := 0
	for raw in _jobs.values():
		if raw is Dictionary and str((raw as Dictionary).get("status", "")) == "in_flight":
			count += 1
	return count


static func _add_requester(target: Dictionary, source: Dictionary) -> void:
	var requesters: Array = target.get("requesters", [])
	var requester_id := str(source.get("requester_id", "")).strip_edges()
	if requester_id.is_empty():
		requester_id = str(source.get("job_id", "")).strip_edges()
	if not requester_id.is_empty() and not requesters.has(requester_id):
		requesters.append(requester_id)
	target["requesters"] = requesters


func _transition(
	job_id: String,
	status: String,
	timestamp_name: String,
	stat_name: String
) -> Dictionary:
	var clean_id := job_id.strip_edges()
	if not _jobs.has(clean_id):
		return _failure("Narrative cache job not found.")
	var job: Dictionary = _jobs[clean_id]
	job["status"] = status
	_stamp(job, timestamp_name)
	_jobs[clean_id] = job
	_stats[stat_name] = int(_stats.get(stat_name, 0)) + 1
	return {"ok": true, "job": job.duplicate(true)}


func _stamp_existing(job_id: String, timestamp_name: String) -> Dictionary:
	var clean_id := job_id.strip_edges()
	if not _jobs.has(clean_id):
		return _failure("Narrative cache job not found.")
	var job: Dictionary = _jobs[clean_id]
	_stamp(job, timestamp_name)
	_jobs[clean_id] = job
	return {"ok": true, "job": job.duplicate(true)}


static func _stamp(job: Dictionary, timestamp_name: String) -> void:
	var timestamps: Dictionary = job.get("diagnostic_timestamps", {})
	timestamps[timestamp_name] = int(Time.get_unix_time_from_system())
	job["diagnostic_timestamps"] = timestamps


static func _append_delta(
	target: Array[int],
	stamps: Dictionary,
	start_key: String,
	end_key: String
) -> void:
	if not stamps.has(start_key) or not stamps.has(end_key):
		return
	target.append(max(0, int(stamps[end_key]) - int(stamps[start_key])))


static func _duration_summary(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {
			"count": 0,
			"avg_seconds": 0.0,
			"max_seconds": 0,
		}
	var total := 0
	var max_value := 0
	for value in values:
		total += value
		max_value = max(max_value, value)
	return {
		"count": values.size(),
		"avg_seconds": float(total) / float(values.size()),
		"max_seconds": max_value,
	}


static func _job_matches_any_stale_criterion(
	job: Dictionary,
	criteria: Dictionary
) -> bool:
	for key in [
		"story_beat_id",
		"giver_npc_id",
		"destination_id",
		"objective_fingerprint",
		"allowed_facts_fingerprint",
		"relationship_tier",
	]:
		if not criteria.has(key):
			continue
		var expected := str(criteria.get(key, "")).strip_edges()
		if expected.is_empty():
			continue
		if str(job.get(key, "")).strip_edges() == expected:
			return true
	return false


static func _job_matches_all_scope_criteria(
	job: Dictionary,
	criteria: Dictionary
) -> bool:
	var accepted_keys := [
		"campaign_id",
		"story_revision",
		"system_id",
		"station_id",
		"npc_id",
		"speaker_id",
		"subject_id",
	]
	var saw_criterion := false
	for key in accepted_keys:
		if not criteria.has(key):
			continue
		var expected: Variant = criteria.get(key)
		if expected == null:
			continue
		if expected is String and str(expected).strip_edges().is_empty():
			continue
		saw_criterion = true
		if key == "npc_id":
			if str(job.get("npc_id", job.get("speaker_id", ""))) != str(expected):
				return false
		elif key == "story_revision":
			if int(job.get("story_revision", -1)) != int(expected):
				return false
		elif str(job.get(key, "")) != str(expected):
			return false
	return saw_criterion


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
