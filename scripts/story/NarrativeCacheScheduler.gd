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
const TRIGGER_OBJECTIVE_PROGRESS_TURN_IN := "objective_progress_turn_in"
const TRIGGER_MISSION_ACCEPTANCE_OUTCOMES := "mission_acceptance_outcomes"

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
	"tts_failed": 0,
	"cache_lookup_hit": 0,
	"cache_lookup_miss": 0,
	"interaction_clicked": 0,
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
		var left_kind_rank := _kind_dispatch_rank(str(left.get("kind", "")))
		var right_kind_rank := _kind_dispatch_rank(str(right.get("kind", "")))
		if left_kind_rank != right_kind_rank:
			return left_kind_rank < right_kind_rank
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
		TRIGGER_OBJECTIVE_PROGRESS_TURN_IN, TRIGGER_MISSION_ACCEPTANCE_OUTCOMES:
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


func restore_ready_job(job: Dictionary, result_payload: Dictionary) -> Dictionary:
	var restored := job.duplicate(true)
	restored["status"] = "ready"
	restored["result_payload"] = result_payload.duplicate(true)
	var queued := queue_job(restored)
	if not bool(queued.get("ok", false)):
		return queued
	var job_id := str(restored.get("job_id", "")).strip_edges()
	if job_id.is_empty():
		return _failure("Narrative cache job requires job_id.")
	var ready: Dictionary = _jobs[job_id]
	ready["status"] = "ready"
	ready["result_payload"] = result_payload.duplicate(true)
	_stamp(ready, "restored_ready")
	_jobs[job_id] = ready
	return {"ok": true, "job": ready.duplicate(true)}


func mark_tts_cache_started(job_id: String) -> Dictionary:
	return _stamp_existing(job_id, "tts_cache_started")


func mark_tts_ready(job_id: String) -> Dictionary:
	return _stamp_existing(job_id, "tts_ready")


func mark_tts_failed(job_id: String, reason: String = "tts_failed") -> Dictionary:
	var clean_id := job_id.strip_edges()
	if not _jobs.has(clean_id):
		return _failure("Narrative cache job not found.")
	var job: Dictionary = _jobs[clean_id]
	job["tts_failed"] = true
	job["tts_failure_reason"] = reason.strip_edges()
	_stamp(job, "tts_failed")
	if str(job.get("kind", "")) == "tts_cache":
		job["status"] = "audio_failed"
	_jobs[clean_id] = job
	_stats["tts_failed"] = int(_stats.get("tts_failed", 0)) + 1
	return {"ok": true, "job": job.duplicate(true)}


static func prefetch_jobs_for_event(event: Dictionary) -> Array[Dictionary]:
	var event_type := str(event.get("event_type", "")).strip_edges()
	if event_type == "system_arrived":
		return _system_arrival_prefetch_jobs(event)
	if event_type == "station_targeted":
		return _station_target_prefetch_jobs(event)
	if event_type == "chapter_packet_ready":
		return _chapter_packet_ready_prefetch_jobs(event)
	if event_type == "new_campaign_loading":
		return _new_campaign_loading_prefetch_jobs(event)
	var mission_id := str(event.get("mission_id", event.get("subject_id", ""))).strip_edges()
	if mission_id.is_empty():
		return []
	if event_type == "objective_complete" \
			or bool(event.get("objective_complete", false)):
		return [_turn_in_prefetch_job(event, TRIGGER_OBJECTIVE_COMPLETE_TURN_IN)]
	if event_type == "objective_progress" \
			and float(event.get("progress_fraction", 0.0)) >= 0.7:
		return [_turn_in_prefetch_job(event, TRIGGER_OBJECTIVE_PROGRESS_TURN_IN)]
	if event_type == "mission_accepted":
		return _mission_acceptance_prefetch_jobs(event)
	return []


func queue_tts_jobs_for_validated_text(
	source_job_id: String,
	text_bundle: Dictionary,
	required_fields: Array,
	voice_profile_id: String
) -> Dictionary:
	var source := get_job(source_job_id)
	if source.is_empty():
		return _failure("Narrative cache source job not found.")
	var stamps: Dictionary = source.get("diagnostic_timestamps", {}) \
		if source.get("diagnostic_timestamps", {}) is Dictionary else {}
	if not stamps.has("validation_finished"):
		return _failure("TTS jobs require validated text.")
	var clean_voice := voice_profile_id.strip_edges()
	if clean_voice.is_empty():
		return _failure("TTS jobs require voice_profile_id.")
	var queued: Array[String] = []
	var missing_fields: Array[String] = []
	var prepared_fields: Array[Dictionary] = []
	for raw_field in required_fields:
		var field_id := str(raw_field).strip_edges()
		if field_id.is_empty():
			continue
		var text := str(text_bundle.get(field_id, "")).strip_edges()
		if text.is_empty():
			missing_fields.append(field_id)
			continue
		var fingerprint := text.sha256_text()
		prepared_fields.append({
			"field_id": field_id,
			"text": text,
			"fingerprint": fingerprint,
		})
	if not missing_fields.is_empty():
		return {
			"ok": false,
			"error": "TTS jobs missing required text fields.",
			"missing_fields": missing_fields,
			"queued": [],
		}
	for field in prepared_fields:
		var job := _tts_job_from_source(
			source,
			str(field.get("field_id", "")),
			clean_voice,
			str(field.get("text", "")),
			str(field.get("fingerprint", ""))
		)
		var result := queue_job(job)
		if not bool(result.get("ok", false)):
			return result
		queued.append(str(result.get("job", {}).get("job_id", job.get("job_id", ""))))
	return {"ok": true, "queued": queued}


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
	var ready_to_click_durations: Array[int] = []
	var queue_waits: Array[int] = []
	var generation_durations: Array[int] = []
	var validation_waits: Array[int] = []
	var ready_payloads := 0
	var content_type_counts: Dictionary = {}
	var source_counts: Dictionary = {}
	var fallback_uses := 0
	var generated_replacements := 0
	for raw in _jobs.values():
		if not raw is Dictionary:
			continue
		var job: Dictionary = raw
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
		_append_delta(
			ready_to_click_durations,
			stamps,
			"text_presented",
			"interaction_clicked"
		)
		if str(job.get("status", "")) == "ready":
			var payload: Dictionary = job.get("result_payload", {}) \
				if job.get("result_payload", {}) is Dictionary else {}
			if not payload.is_empty():
				ready_payloads += 1
				var content_type := str(payload.get("content_type", "unknown"))
				content_type_counts[content_type] = int(
					content_type_counts.get(content_type, 0)
				) + 1
				var source := str(payload.get("source", "unknown"))
				source_counts[source] = int(source_counts.get(source, 0)) + 1
				fallback_uses += int(payload.get("fallback_uses", 0))
				generated_replacements += int(
					payload.get("generated_replacements", 0)
				)
	return {
		"queue_wait": _duration_summary(queue_waits),
		"generation": _duration_summary(generation_durations),
		"validation": _duration_summary(validation_waits),
		"time_to_ready": _duration_summary(ready_durations),
		"ready_to_click": _duration_summary(ready_to_click_durations),
		"ready_payloads": ready_payloads,
		"content_type_counts": content_type_counts,
		"source_counts": source_counts,
		"fallback_uses": fallback_uses,
		"generated_replacements": generated_replacements,
		"cache_lookup_hit": int(_stats.get("cache_lookup_hit", 0)),
		"cache_lookup_miss": int(_stats.get("cache_lookup_miss", 0)),
		"interaction_clicked": int(_stats.get("interaction_clicked", 0)),
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


func queue_pool_refill_job(
	pool_id: String,
	current_count: int,
	target_count: int,
	scope: Dictionary = {}
) -> Dictionary:
	var clean_pool_id := pool_id.strip_edges()
	if clean_pool_id.is_empty():
		return _failure("Pool refill requires pool_id.")
	var priority := priority_for_trigger(TRIGGER_AMBIENT_REPLENISHMENT)
	if not can_refill_pool(current_count, target_count, priority):
		return {
			"ok": false,
			"deferred": true,
			"error": "Pool refill deferred while higher-priority work is pending or pool is full.",
		}
	var job := {
		"job_id": "job.%s.%s" % [
			TRIGGER_AMBIENT_REPLENISHMENT,
			_safe_id_part(clean_pool_id),
		],
		"cache_key": "prefetch.%s.%s" % [
			TRIGGER_AMBIENT_REPLENISHMENT,
			_safe_id_part(clean_pool_id),
		],
		"kind": "ambient_pool_refill",
		"trigger": TRIGGER_AMBIENT_REPLENISHMENT,
		"priority": priority,
		"subject_id": clean_pool_id,
		"pool_id": clean_pool_id,
		"pool_count": max(0, current_count),
		"pool_target": max(0, target_count),
		"requester_id": "prefetch:%s:%s" % [
			TRIGGER_AMBIENT_REPLENISHMENT,
			clean_pool_id,
		],
	}
	for key in [
		"campaign_id",
		"timeline_id",
		"story_revision",
		"knowledge_revision",
		"mission_history_revision",
		"system_id",
		"station_id",
		"speaker_id",
		"relationship_tier",
	]:
		if scope.has(key):
			job[key] = scope[key]
	return queue_job(job)


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
			_stats["cache_lookup_hit"] = int(_stats.get("cache_lookup_hit", 0)) + 1
			return {
				"job_id": str(job.get("job_id", "")),
				"cache_key": str(job.get("cache_key", "")),
				"result_payload": (
					job.get("result_payload", {}) as Dictionary
				).duplicate(true) if job.get("result_payload", {}) is Dictionary else {},
			}
	_stats["cache_lookup_miss"] = int(_stats.get("cache_lookup_miss", 0)) + 1
	return {}


func mark_interaction_clicked_for_requester(requester_id: String) -> Dictionary:
	var clean_requester := requester_id.strip_edges()
	if clean_requester.is_empty():
		return _failure("Narrative cache requester is required.")
	for job_id in _jobs.keys():
		var raw: Variant = _jobs[job_id]
		if not raw is Dictionary:
			continue
		var job: Dictionary = raw
		if str(job.get("status", "")) != "ready":
			continue
		var requesters: Array = job.get("requesters", [])
		if requesters.has(clean_requester):
			_stamp(job, "interaction_clicked")
			_jobs[job_id] = job
			_stats["interaction_clicked"] = int(
				_stats.get("interaction_clicked", 0)
			) + 1
			return {"ok": true, "job": job.duplicate(true)}
	return _failure("Ready narrative cache job not found for requester.")


func update_result_payload(job_id: String, result_payload: Dictionary) -> Dictionary:
	var clean_id := job_id.strip_edges()
	if clean_id.is_empty() or not _jobs.has(clean_id):
		return _failure("Narrative cache job not found.")
	var raw: Variant = _jobs[clean_id]
	if not raw is Dictionary:
		return _failure("Narrative cache job is invalid.")
	var job: Dictionary = raw
	if str(job.get("status", "")) != "ready":
		return _failure("Narrative cache job is not ready.")
	job["result_payload"] = result_payload.duplicate(true)
	_jobs[clean_id] = job
	return {"ok": true, "job": job.duplicate(true)}


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


static func _tts_job_from_source(
	source: Dictionary,
	field_id: String,
	voice_profile_id: String,
	text: String,
	text_fingerprint: String
) -> Dictionary:
	var source_cache_key := str(source.get("cache_key", "")).strip_edges()
	var safe_field := _safe_id_part(field_id)
	var safe_voice := _safe_id_part(voice_profile_id)
	var short_fingerprint := text_fingerprint.substr(0, 16)
	var job := {
		"job_id": "tts.%s.%s.%s" % [
			_safe_id_part(source_cache_key),
			safe_field,
			short_fingerprint,
		],
		"cache_key": "%s.tts.%s.%s.%s" % [
			source_cache_key,
			safe_field,
			safe_voice,
			short_fingerprint,
		],
		"kind": "tts_cache",
		"priority": int(source.get("priority", PRIORITY_P2)),
		"text_cache_key": source_cache_key,
		"field_id": field_id,
		"voice_profile_id": voice_profile_id,
		"text_fingerprint": text_fingerprint,
		"text": text,
		"requester_id": "tts:%s:%s" % [source_cache_key, field_id],
	}
	for key in [
		"campaign_id",
		"story_revision",
		"knowledge_revision",
		"mission_history_revision",
		"system_id",
		"station_id",
		"npc_id",
		"speaker_id",
		"subject_id",
		"story_beat_id",
		"giver_npc_id",
		"destination_id",
		"objective_fingerprint",
		"allowed_facts_fingerprint",
		"relationship_tier",
		"truth_frozen",
	]:
		if source.has(key):
			job[key] = source[key]
	return job


static func _turn_in_prefetch_job(event: Dictionary, trigger: String) -> Dictionary:
	var mission_id := str(event.get("mission_id", event.get("subject_id", ""))).strip_edges()
	var outcome_fingerprint := str(
		event.get("outcome_fingerprint", "pending")
	).strip_edges()
	if outcome_fingerprint.is_empty():
		outcome_fingerprint = "pending"
	var cache_key := str(event.get("cache_key", "")).strip_edges()
	if cache_key.is_empty():
		cache_key = "prefetch.%s.%s.%s" % [
			trigger,
			_safe_id_part(mission_id),
			_safe_id_part(outcome_fingerprint),
		]
	var job := {
		"job_id": "job.%s.%s" % [trigger, _safe_id_part(mission_id)],
		"cache_key": cache_key,
		"kind": "kaelen_turn_in_bundle",
		"trigger": trigger,
		"priority": priority_for_trigger(trigger),
		"subject_id": mission_id,
		"mission_id": mission_id,
		"outcome_fingerprint": outcome_fingerprint,
		"requester_id": "prefetch:%s:%s" % [trigger, mission_id],
	}
	for key in [
		"campaign_id",
		"timeline_id",
		"story_revision",
		"knowledge_revision",
		"mission_history_revision",
		"system_id",
		"station_id",
		"speaker_id",
		"story_beat_id",
		"cause_id",
		"relationship_tier",
	]:
		if event.has(key):
			job[key] = event[key]
	return job


static func _mission_acceptance_prefetch_jobs(event: Dictionary) -> Array[Dictionary]:
	var mission_id := str(event.get("mission_id", event.get("subject_id", ""))).strip_edges()
	if mission_id.is_empty():
		return []
	var outcome_variants: Array = event.get("likely_outcome_variants", []) \
		if event.get("likely_outcome_variants", []) is Array else []
	var variants: Array[String] = ["abandon_baseline"]
	for raw_variant in outcome_variants:
		var variant := str(raw_variant).strip_edges()
		if not variant.is_empty() and not variants.has(variant):
			variants.append(variant)
	var jobs: Array[Dictionary] = []
	for variant in variants:
		var variant_event := event.duplicate(true)
		variant_event["outcome_fingerprint"] = variant
		var job := _turn_in_prefetch_job(
			variant_event,
			TRIGGER_MISSION_ACCEPTANCE_OUTCOMES
		)
		job["job_id"] = "job.%s.%s.%s" % [
			TRIGGER_MISSION_ACCEPTANCE_OUTCOMES,
			_safe_id_part(mission_id),
			_safe_id_part(variant),
		]
		job["cache_key"] = "prefetch.%s.%s.%s" % [
			TRIGGER_MISSION_ACCEPTANCE_OUTCOMES,
			_safe_id_part(mission_id),
			_safe_id_part(variant),
		]
		job["outcome_variant"] = variant
		job["truth_frozen"] = true
		jobs.append(job)
	return jobs


static func _system_arrival_prefetch_jobs(event: Dictionary) -> Array[Dictionary]:
	var system_id := str(event.get("system_id", event.get("subject_id", ""))).strip_edges()
	if system_id.is_empty():
		return []
	var jobs: Array[Dictionary] = [
		_context_prefetch_job(
			event,
			TRIGGER_CURRENT_SYSTEM_AGENT,
			system_id,
			"current_system_agent_bundle"
		),
		_context_prefetch_job(
			event,
			TRIGGER_CURRENT_SYSTEM_KAELEN,
			system_id,
			"current_system_kaelen_bundle"
		),
		_context_prefetch_job(
			event,
			TRIGGER_CURRENT_SYSTEM_NOVA,
			system_id,
			"current_system_nova_bundle"
		),
	]
	var contact_profiles: Array = event.get("contact_profiles", []) \
		if event.get("contact_profiles", []) is Array else []
	for raw_profile in contact_profiles:
		if not raw_profile is Dictionary:
			continue
		var profile: Dictionary = raw_profile
		var contact_id := str(profile.get("contact_id", profile.get("agent_id", ""))).strip_edges()
		if contact_id.is_empty():
			continue
		var contact_event := event.duplicate(true)
		contact_event["speaker_id"] = contact_id
		contact_event["contact_id"] = contact_id
		contact_event["contact_display"] = str(profile.get("display_name", profile.get("agent_name", contact_id)))
		contact_event["faction_id"] = str(profile.get("faction_id", ""))
		contact_event["voice_profile_id"] = str(profile.get("voice_profile_id", ""))
		jobs.append(_context_prefetch_job(
			contact_event,
			TRIGGER_CURRENT_SYSTEM_AGENT,
			"%s.%s" % [system_id, contact_id],
			"system_contact_offer_bundle"
		))
	var station_ids: Array[String] = []
	var station_id := str(event.get("station_id", "")).strip_edges()
	if not station_id.is_empty():
		station_ids.append(station_id)
	var raw_station_ids: Array = event.get("visible_station_ids", []) \
		if event.get("visible_station_ids", []) is Array else []
	for raw_id in raw_station_ids:
		var visible_station_id := str(raw_id).strip_edges()
		if not visible_station_id.is_empty() and not station_ids.has(visible_station_id):
			station_ids.append(visible_station_id)
	for visible_station_id in station_ids:
		var station_event := event.duplicate(true)
		station_event["station_id"] = visible_station_id
		jobs.append(_context_prefetch_job(
			station_event,
			TRIGGER_CURRENT_VISIBLE_STATION,
			visible_station_id,
			"current_visible_station_bundle"
		))
	return jobs


static func _station_target_prefetch_jobs(event: Dictionary) -> Array[Dictionary]:
	var station_id := str(event.get("station_id", event.get("subject_id", ""))).strip_edges()
	if station_id.is_empty():
		return []
	return [
		_context_prefetch_job(
			event,
			TRIGGER_CURRENT_VISIBLE_STATION,
			station_id,
			"current_station_agent_offer_bundle"
		),
		_context_prefetch_job(
			event,
			TRIGGER_MECHANIC_GREETING,
			station_id,
			"mechanic_greeting_bundle"
		),
		_context_prefetch_job(
			event,
			TRIGGER_LIKELY_LOUNGE,
			station_id,
			"likely_lounge_opener_bundle"
		),
	]


static func _chapter_packet_ready_prefetch_jobs(event: Dictionary) -> Array[Dictionary]:
	var packet_id := str(event.get("packet_id", event.get("subject_id", ""))).strip_edges()
	if packet_id.is_empty():
		return []
	var beat_ids: Array = event.get("first_beat_ids", []) \
		if event.get("first_beat_ids", []) is Array else []
	var jobs: Array[Dictionary] = []
	for raw_beat_id in beat_ids:
		var beat_id := str(raw_beat_id).strip_edges()
		if beat_id.is_empty():
			continue
		var beat_event := event.duplicate(true)
		beat_event["story_beat_id"] = beat_id
		var job := _context_prefetch_job(
			beat_event,
			TRIGGER_CURRENT_SYSTEM_AGENT,
			"%s.%s" % [packet_id, beat_id],
			"chapter_first_interaction_bundle"
		)
		job["packet_id"] = packet_id
		job["chapter"] = int(event.get("chapter", 1))
		job["story_beat_id"] = beat_id
		jobs.append(job)
	return jobs


static func _new_campaign_loading_prefetch_jobs(event: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	var station_id := str(event.get("station_id", "")).strip_edges()
	if not station_id.is_empty():
		var station_event := event.duplicate(true)
		station_event["event_type"] = "station_targeted"
		station_event["target_reason"] = "new_campaign_loading"
		jobs.append_array(_station_target_prefetch_jobs(station_event))
	var system_id := str(event.get("system_id", event.get("subject_id", ""))).strip_edges()
	if not system_id.is_empty():
		jobs.append(_context_prefetch_job(
			event,
			TRIGGER_CURRENT_SYSTEM_KAELEN,
			system_id,
			"new_campaign_kaelen_handoff_bank"
		))
		jobs.append(_context_prefetch_job(
			event,
			TRIGGER_CURRENT_SYSTEM_NOVA,
			system_id,
			"new_campaign_nova_bank"
		))
	var packet_id := str(event.get("packet_id", "")).strip_edges()
	if not packet_id.is_empty():
		var packet_event := event.duplicate(true)
		packet_event["event_type"] = "chapter_packet_ready"
		jobs.append_array(_chapter_packet_ready_prefetch_jobs(packet_event))
	return jobs


static func _context_prefetch_job(
	event: Dictionary,
	trigger: String,
	subject_id: String,
	kind: String
) -> Dictionary:
	var safe_subject := _safe_id_part(subject_id)
	var cache_key := str(event.get("cache_key", "")).strip_edges()
	if cache_key.is_empty():
		cache_key = "prefetch.%s.%s" % [trigger, safe_subject]
	var job := {
		"job_id": "job.%s.%s" % [trigger, safe_subject],
		"cache_key": cache_key,
		"kind": kind,
		"trigger": trigger,
		"priority": priority_for_trigger(trigger),
		"subject_id": subject_id,
		"requester_id": "prefetch:%s:%s" % [trigger, subject_id],
	}
	for key in [
		"campaign_id",
		"timeline_id",
		"story_revision",
		"knowledge_revision",
		"mission_history_revision",
		"system_id",
		"station_id",
		"speaker_id",
		"story_beat_id",
		"cause_id",
		"relationship_tier",
		"arrival_gate_id",
		"target_reason",
		"station_type",
		"packet_id",
		"chapter",
		"contact_id",
		"contact_display",
		"faction_id",
		"voice_profile_id",
	]:
		if event.has(key):
			job[key] = event[key]
	return job


static func _safe_id_part(value: String) -> String:
	var result := ""
	for index in value.length():
		var character := value[index]
		if character.is_valid_identifier() or character.is_valid_int():
			result += character
		else:
			result += "_"
	return result.strip_edges().trim_prefix("_").trim_suffix("_")


static func _kind_dispatch_rank(kind: String) -> int:
	match kind.strip_edges():
		"tts_cache":
			return 10
		_:
			return 0


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
			"p50_seconds": 0,
			"p95_seconds": 0,
			"max_seconds": 0,
		}
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var total := 0
	var max_value := 0
	for value in values:
		total += value
		max_value = max(max_value, value)
	var p50_index: int = clampi(
		int(ceil(float(sorted_values.size()) * 0.50)) - 1,
		0,
		sorted_values.size() - 1
	)
	var p95_index: int = clampi(
		int(ceil(float(sorted_values.size()) * 0.95)) - 1,
		0,
		sorted_values.size() - 1
	)
	return {
		"count": values.size(),
		"avg_seconds": float(total) / float(values.size()),
		"p50_seconds": int(sorted_values[p50_index]),
		"p95_seconds": int(sorted_values[p95_index]),
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
