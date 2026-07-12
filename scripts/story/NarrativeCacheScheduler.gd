class_name NarrativeCacheScheduler
extends RefCounted

const PRIORITY_P0 := 0
const PRIORITY_P1 := 10
const PRIORITY_P2 := 20
const PRIORITY_P3 := 30

var _jobs: Dictionary = {}
var _sequence := 0
var _stats := {
	"queued": 0,
	"started": 0,
	"ready": 0,
	"canceled": 0,
	"stale_discarded": 0,
	"degraded": 0,
}


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
	var pending := pending_jobs()
	if pending.is_empty():
		return {}
	return pending[0].duplicate(true)


func mark_generation_started(job_id: String) -> Dictionary:
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


func mark_ready(job_id: String) -> Dictionary:
	return _transition(job_id, "ready", "text_presented", "ready")


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
	return result


func get_job(job_id: String) -> Dictionary:
	var clean_id := job_id.strip_edges()
	if not _jobs.has(clean_id):
		return {}
	var raw: Variant = _jobs[clean_id]
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
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


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
