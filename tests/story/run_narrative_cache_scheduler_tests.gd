extends SceneTree

const SchedulerType := preload("res://scripts/story/NarrativeCacheScheduler.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_priority_order_and_dedupe()
	_test_deduplicates_active_jobs_by_cache_key()
	_test_lifecycle_timestamps_and_stats()
	_test_cancel_and_stale_discard_skip_ready_and_frozen_jobs()
	_test_scope_cancellation_only_cancels_matching_queued_jobs()
	_test_diagnostic_summary_reports_lifecycle_durations()
	_test_pause_blocks_starting_small_jobs_until_resume()

	if _failures.is_empty():
		print("[PASS] Narrative cache scheduler tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_priority_order_and_dedupe() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	scheduler.queue_job(_job("job.p2", "cache.p2", SchedulerType.PRIORITY_P2))
	scheduler.queue_job(_job("job.p0", "cache.p0", SchedulerType.PRIORITY_P0))
	scheduler.queue_job(_job("job.p1", "cache.p1", SchedulerType.PRIORITY_P1))
	_expect(
		str(scheduler.next_job().get("job_id", "")) == "job.p0",
		"Scheduler did not choose the highest-priority pending job first."
	)
	var update := _job("job.p2", "cache.p2.changed", SchedulerType.PRIORITY_P0)
	var queued: Dictionary = scheduler.queue_job(update)
	_expect(
		bool(queued.get("ok", false))
			and str(scheduler.get_job("job.p2").get("cache_key", ""))
				== "cache.p2.changed"
			and int(scheduler.stats().get("queued", 0)) == 3,
		"Scheduler did not update an existing job without double-counting it."
	)


func _test_deduplicates_active_jobs_by_cache_key() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	var first := _job("job.first", "cache.shared", SchedulerType.PRIORITY_P2)
	first["requester_id"] = "ui.agent_panel"
	var second := _job("job.second", "cache.shared", SchedulerType.PRIORITY_P0)
	second["requester_id"] = "prefetch.current_station"
	scheduler.queue_job(first)
	var deduped: Dictionary = scheduler.queue_job(second)
	var job: Dictionary = scheduler.get_job("job.first")
	var requesters: Array = job.get("requesters", [])
	_expect(
		bool(deduped.get("deduped", false))
			and scheduler.jobs().size() == 1
			and str(deduped.get("job", {}).get("job_id", "")) == "job.first"
			and int(job.get("priority", SchedulerType.PRIORITY_P2))
				== SchedulerType.PRIORITY_P0
			and requesters.has("ui.agent_panel")
			and requesters.has("prefetch.current_station"),
		"Scheduler did not deduplicate active jobs by cache key."
	)
	scheduler.mark_ready("job.first")
	var after_ready: Dictionary = scheduler.queue_job(
		_job("job.third", "cache.shared", SchedulerType.PRIORITY_P1)
	)
	_expect(
		not bool(after_ready.get("deduped", false))
			and scheduler.jobs().size() == 2,
		"Scheduler should allow a fresh job for a cache key after the prior job is ready."
	)


func _test_lifecycle_timestamps_and_stats() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	scheduler.queue_job(_job("job.alpha", "cache.alpha", SchedulerType.PRIORITY_P1))
	scheduler.mark_generation_started("job.alpha")
	scheduler.mark_generation_finished("job.alpha")
	scheduler.mark_validation_finished("job.alpha", true)
	scheduler.mark_tts_cache_started("job.alpha")
	scheduler.mark_tts_ready("job.alpha")
	scheduler.mark_ready("job.alpha")
	var job: Dictionary = scheduler.get_job("job.alpha")
	var stamps: Dictionary = job.get("diagnostic_timestamps", {})
	_expect(
		str(job.get("status", "")) == "ready"
			and stamps.has("job_queued")
			and stamps.has("generation_started")
			and stamps.has("generation_finished")
			and stamps.has("validation_finished")
			and stamps.has("tts_cache_started")
			and stamps.has("tts_ready")
			and stamps.has("text_presented"),
		"Scheduler did not preserve required lifecycle diagnostic timestamps."
	)
	_expect(
		int(scheduler.stats().get("started", 0)) == 1
			and int(scheduler.stats().get("ready", 0)) == 1
			and int(scheduler.stats().get("degraded", 0)) == 1,
		"Scheduler lifecycle stats did not update."
	)


func _test_cancel_and_stale_discard_skip_ready_and_frozen_jobs() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	scheduler.queue_job(_job("job.cancel", "cache.cancel", SchedulerType.PRIORITY_P0))
	var canceled: Dictionary = scheduler.cancel_job("job.cancel", "test")
	_expect(
		bool(canceled.get("ok", false))
			and str(scheduler.get_job("job.cancel").get("status", "")) == "canceled",
		"Scheduler did not cancel a pending job."
	)
	scheduler.queue_job(_truth_job("job.stale", false))
	scheduler.queue_job(_truth_job("job.frozen", true))
	scheduler.queue_job(_truth_job("job.ready", false))
	scheduler.mark_ready("job.ready")
	var discarded: Dictionary = scheduler.discard_stale_jobs({
		"story_beat_id": "beat.alpha",
	})
	var removed: Array = discarded.get("removed", [])
	_expect(
		removed == ["job.stale"]
			and str(scheduler.get_job("job.stale").get("status", ""))
				== "stale_discarded"
			and str(scheduler.get_job("job.frozen").get("status", "")) == "queued"
			and str(scheduler.get_job("job.ready").get("status", "")) == "ready",
		"Scheduler stale discard did not preserve frozen and ready jobs."
	)


func _test_scope_cancellation_only_cancels_matching_queued_jobs() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	scheduler.queue_job(_scoped_job("job.cancel.alpha", "station.alpha", "npc.alpha"))
	scheduler.queue_job(_scoped_job("job.keep.station", "station.beta", "npc.alpha"))
	scheduler.queue_job(_scoped_job("job.keep.npc", "station.alpha", "npc.beta"))
	scheduler.queue_job(_scoped_job("job.inflight", "station.alpha", "npc.alpha"))
	scheduler.mark_generation_started("job.inflight")
	var canceled: Dictionary = scheduler.cancel_jobs({
		"campaign_id": "campaign.alpha",
		"story_revision": 7,
		"station_id": "station.alpha",
		"npc_id": "npc.alpha",
	}, "station_changed")
	var ids: Array = canceled.get("canceled", [])
	_expect(
		ids == ["job.cancel.alpha"]
			and str(scheduler.get_job("job.cancel.alpha").get("status", ""))
				== "canceled"
			and str(scheduler.get_job("job.keep.station").get("status", ""))
				== "queued"
			and str(scheduler.get_job("job.keep.npc").get("status", ""))
				== "queued"
			and str(scheduler.get_job("job.inflight").get("status", ""))
				== "in_flight",
		"Scheduler scope cancellation did not cancel only matching queued jobs."
	)


func _test_diagnostic_summary_reports_lifecycle_durations() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	scheduler.queue_job(_job("job.metrics", "cache.metrics", SchedulerType.PRIORITY_P1))
	scheduler.mark_generation_started("job.metrics")
	scheduler.mark_generation_finished("job.metrics")
	scheduler.mark_validation_finished("job.metrics")
	scheduler.mark_ready("job.metrics")
	var summary: Dictionary = scheduler.diagnostic_summary()
	_expect(
		int(summary.get("queue_wait", {}).get("count", 0)) == 1
			and int(summary.get("generation", {}).get("count", 0)) == 1
			and int(summary.get("validation", {}).get("count", 0)) == 1
			and int(summary.get("time_to_ready", {}).get("count", 0)) == 1
			and float(summary.get("time_to_ready", {}).get("avg_seconds", -1.0))
				>= 0.0,
		"Scheduler diagnostic summary did not report lifecycle durations."
	)


func _test_pause_blocks_starting_small_jobs_until_resume() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	scheduler.queue_job(_job("job.paused", "cache.paused", SchedulerType.PRIORITY_P0))
	var paused: Dictionary = scheduler.pause("campaign_bible_generation")
	var start_while_paused: Dictionary = scheduler.mark_generation_started("job.paused")
	_expect(
		bool(paused.get("paused", false))
			and scheduler.next_job().is_empty()
			and not bool(start_while_paused.get("ok", false))
			and bool(scheduler.stats().get("paused", false)),
		"Scheduler pause did not block small job dispatch."
	)
	scheduler.resume()
	var started: Dictionary = scheduler.mark_generation_started("job.paused")
	_expect(
		not scheduler.is_paused()
			and bool(started.get("ok", false))
			and str(scheduler.get_job("job.paused").get("status", "")) == "in_flight",
		"Scheduler did not resume small job dispatch."
	)


func _job(job_id: String, cache_key: String, priority: int) -> Dictionary:
	return {
		"job_id": job_id,
		"cache_key": cache_key,
		"kind": "mission_conversation",
		"priority": priority,
	}


func _truth_job(job_id: String, truth_frozen: bool) -> Dictionary:
	var job := _job(job_id, "%s.cache" % job_id, SchedulerType.PRIORITY_P1)
	job["story_beat_id"] = "beat.alpha"
	job["giver_npc_id"] = "agent.alpha"
	job["destination_id"] = "station.start.main"
	job["objective_fingerprint"] = "objective.alpha"
	job["allowed_facts_fingerprint"] = "facts.alpha"
	job["relationship_tier"] = "cordial"
	job["truth_frozen"] = truth_frozen
	return job


func _scoped_job(job_id: String, station_id: String, npc_id: String) -> Dictionary:
	var job := _job(job_id, "%s.cache" % job_id, SchedulerType.PRIORITY_P1)
	job["campaign_id"] = "campaign.alpha"
	job["story_revision"] = 7
	job["system_id"] = "system.alpha"
	job["station_id"] = station_id
	job["speaker_id"] = npc_id
	job["subject_id"] = "offer.alpha"
	return job


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
