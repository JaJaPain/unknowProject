extends SceneTree

const SchedulerType := preload("res://scripts/story/NarrativeCacheScheduler.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_priority_trigger_mapping_matches_phase_contract()
	_test_priority_order_and_dedupe()
	_test_deduplicates_active_jobs_by_cache_key()
	_test_ready_result_fans_out_to_deduped_requesters()
	_test_lifecycle_timestamps_and_stats()
	_test_cancel_and_stale_discard_skip_ready_and_frozen_jobs()
	_test_scope_cancellation_only_cancels_matching_queued_jobs()
	_test_diagnostic_summary_reports_lifecycle_durations()
	_test_pause_blocks_starting_small_jobs_until_resume()
	_test_validation_failure_retries_once_then_requires_degraded_content()
	_test_default_concurrency_allows_only_one_generation_in_flight()
	_test_tts_jobs_inherit_text_priority_and_scope_after_validation()
	_test_tts_failure_is_recorded_separately_from_text_degradation()
	_test_equal_priority_text_dispatches_before_audio_cache()
	_test_objective_progress_and_completion_plan_turn_in_prefetch()
	_test_mission_acceptance_plans_baseline_and_likely_outcomes()
	_test_system_arrival_plans_current_system_and_station_prefetch()
	_test_station_target_plans_agent_mechanic_and_lounge_prefetch()
	_test_chapter_packet_ready_plans_first_interaction_prefetch()
	_test_new_campaign_loading_plans_startup_prefetch_bundle()
	_test_game_root_acceptance_hook_calls_prefetch_planner()
	_test_station_target_hooks_call_prefetch_planner()
	_test_chapter_packet_ready_hook_calls_prefetch_planner()
	_test_queue_health_reports_contention_and_starvation()
	_test_pool_refill_waits_for_higher_priority_work()

	if _failures.is_empty():
		print("[PASS] Narrative cache scheduler tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_priority_trigger_mapping_matches_phase_contract() -> void:
	_expect(
		SchedulerType.priority_for_trigger(
			SchedulerType.TRIGGER_OBJECTIVE_COMPLETE_TURN_IN
		) == SchedulerType.PRIORITY_P0
			and SchedulerType.priority_for_trigger(
				SchedulerType.TRIGGER_CURRENT_SYSTEM_AGENT
			) == SchedulerType.PRIORITY_P1
			and SchedulerType.priority_for_trigger(
				SchedulerType.TRIGGER_LIKELY_LOUNGE
			) == SchedulerType.PRIORITY_P2
			and SchedulerType.priority_for_trigger(
				SchedulerType.TRIGGER_AMBIENT_REPLENISHMENT
			) == SchedulerType.PRIORITY_P3
			and SchedulerType.priority_label(SchedulerType.PRIORITY_P0) == "P0",
		"Scheduler priority trigger mapping does not match the Phase 6 contract."
	)


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


func _test_ready_result_fans_out_to_deduped_requesters() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	var first := _job("job.shared.first", "cache.shared.ready", SchedulerType.PRIORITY_P2)
	first["requester_id"] = "ui.agent_panel"
	var second := _job("job.shared.second", "cache.shared.ready", SchedulerType.PRIORITY_P1)
	second["requester_id"] = "prefetch.station"
	scheduler.queue_job(first)
	scheduler.queue_job(second)
	scheduler.mark_generation_started("job.shared.first")
	scheduler.mark_ready("job.shared.first", {
		"cache_key": "cache.shared.ready",
		"opening": "Same finished bundle.",
	})
	var ui_result: Dictionary = scheduler.ready_result_for_requester("ui.agent_panel")
	var prefetch_result: Dictionary = scheduler.ready_result_for_requester("prefetch.station")
	_expect(
		str(ui_result.get("job_id", "")) == "job.shared.first"
			and str(prefetch_result.get("job_id", "")) == "job.shared.first"
			and str(ui_result.get("result_payload", {}).get("opening", ""))
				== "Same finished bundle."
			and str(prefetch_result.get("result_payload", {}).get("opening", ""))
				== "Same finished bundle.",
		"Scheduler did not expose the same ready result to deduped requesters."
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


func _test_validation_failure_retries_once_then_requires_degraded_content() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	scheduler.queue_job(_job("job.retry", "cache.retry", SchedulerType.PRIORITY_P0))
	scheduler.mark_generation_started("job.retry")
	scheduler.mark_generation_finished("job.retry")
	var retried: Dictionary = scheduler.mark_validation_failed(
		"job.retry",
		["opening missing cause"]
	)
	_expect(
		bool(retried.get("retry_queued", false))
			and str(scheduler.get_job("job.retry").get("status", "")) == "queued"
			and int(scheduler.get_job("job.retry").get("retry_count", 0)) == 1
			and int(scheduler.stats().get("retry_queued", 0)) == 1,
		"Scheduler did not queue exactly one validation retry."
	)
	scheduler.mark_generation_started("job.retry")
	scheduler.mark_generation_finished("job.retry")
	var degraded: Dictionary = scheduler.mark_validation_failed(
		"job.retry",
		["answer revealed forbidden fact"]
	)
	_expect(
		not bool(degraded.get("retry_queued", true))
			and str(scheduler.get_job("job.retry").get("status", ""))
				== "degraded_required"
			and bool(scheduler.get_job("job.retry").get("degraded", false)),
		"Scheduler did not require degraded content after retry budget was spent."
	)


func _test_default_concurrency_allows_only_one_generation_in_flight() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	scheduler.queue_job(_job("job.first", "cache.concurrent.first", SchedulerType.PRIORITY_P0))
	scheduler.queue_job(_job("job.second", "cache.concurrent.second", SchedulerType.PRIORITY_P0))
	var first_started: Dictionary = scheduler.mark_generation_started("job.first")
	var second_started: Dictionary = scheduler.mark_generation_started("job.second")
	_expect(
		bool(first_started.get("ok", false))
			and not bool(second_started.get("ok", false))
			and scheduler.next_job().is_empty()
			and int(scheduler.stats().get("in_flight", 0)) == 1,
		"Scheduler allowed more than one default in-flight generation."
	)
	scheduler.mark_ready("job.first")
	var next: Dictionary = scheduler.next_job()
	var second_retry: Dictionary = scheduler.mark_generation_started("job.second")
	_expect(
		str(next.get("job_id", "")) == "job.second"
			and bool(second_retry.get("ok", false)),
		"Scheduler did not release the next job after in-flight work completed."
	)


func _test_tts_jobs_inherit_text_priority_and_scope_after_validation() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	var text_job := _scoped_job("job.text", "station.alpha", "npc.alpha")
	text_job["priority"] = SchedulerType.PRIORITY_P0
	text_job["subject_id"] = "offer.alpha"
	text_job["story_beat_id"] = "beat.alpha"
	scheduler.queue_job(text_job)
	scheduler.mark_generation_started("job.text")
	scheduler.mark_generation_finished("job.text")
	var early: Dictionary = SchedulerType.new().queue_tts_jobs_for_validated_text(
		"job.missing",
		{"opening": "No source."},
		["opening"],
		"voice.agent.alpha"
	)
	var queued: Dictionary = scheduler.queue_tts_jobs_for_validated_text(
		"job.text",
		{"opening": "Line one.", "accept_standard_response": "Line two."},
		["opening", "accept_standard_response"],
		"voice.agent.alpha"
	)
	scheduler.mark_validation_finished("job.text")
	var missing_text: Dictionary = scheduler.queue_tts_jobs_for_validated_text(
		"job.text",
		{"opening": "Line one."},
		["opening", "accept_standard_response"],
		"voice.agent.alpha"
	)
	var validated_queued: Dictionary = scheduler.queue_tts_jobs_for_validated_text(
		"job.text",
		{"opening": "Line one.", "accept_standard_response": "Line two."},
		["opening", "accept_standard_response"],
		"voice.agent.alpha"
	)
	scheduler.mark_ready("job.text")
	var next: Dictionary = scheduler.next_job()
	var canceled: Dictionary = scheduler.cancel_jobs({
		"subject_id": "offer.alpha",
	}, "offer_replaced")
	var canceled_ids: Array = canceled.get("canceled", [])
	_expect(
		not bool(early.get("ok", true))
			and not bool(queued.get("ok", true))
			and not bool(missing_text.get("ok", true))
			and (missing_text.get("queued", []) as Array).is_empty()
			and bool(validated_queued.get("ok", false))
			and (validated_queued.get("queued", []) as Array).size() == 2,
		"Scheduler did not require validated text before queuing TTS jobs."
	)
	_expect(
		str(next.get("kind", "")) == "tts_cache"
			and int(next.get("priority", SchedulerType.PRIORITY_P2))
				== SchedulerType.PRIORITY_P0
			and str(next.get("subject_id", "")) == "offer.alpha"
			and str(next.get("field_id", "")) in [
				"opening",
				"accept_standard_response",
			],
		"Scheduler TTS jobs did not inherit text priority, scope, and field identity."
	)
	_expect(
		canceled_ids.size() == 2,
		"Scheduler did not cancel obsolete queued TTS jobs by inherited scope."
	)


func _test_tts_failure_is_recorded_separately_from_text_degradation() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	var text_job := _job(
		"job.text.ready",
		"cache.text.ready",
		SchedulerType.PRIORITY_P0
	)
	scheduler.queue_job(text_job)
	scheduler.mark_generation_started("job.text.ready")
	scheduler.mark_generation_finished("job.text.ready")
	scheduler.mark_validation_finished("job.text.ready")
	scheduler.mark_ready("job.text.ready", {"opening": "Readable subtitle."})
	var failed: Dictionary = scheduler.mark_tts_failed(
		"job.text.ready",
		"provider_timeout"
	)
	var job: Dictionary = scheduler.get_job("job.text.ready")
	_expect(
		bool(failed.get("ok", false))
			and str(job.get("status", "")) == "ready"
			and bool(job.get("tts_failed", false))
			and str(job.get("tts_failure_reason", "")) == "provider_timeout"
			and not bool(job.get("degraded", false))
			and int(scheduler.stats().get("tts_failed", 0)) == 1,
		"Scheduler did not record TTS failure separately from ready text."
	)
	var audio_job := _job(
		"job.audio.failed",
		"cache.audio.failed",
		SchedulerType.PRIORITY_P0
	)
	audio_job["kind"] = "tts_cache"
	scheduler.queue_job(audio_job)
	scheduler.mark_generation_started("job.audio.failed")
	var audio_failed: Dictionary = scheduler.mark_tts_failed("job.audio.failed")
	_expect(
		bool(audio_failed.get("ok", false))
			and str(scheduler.get_job("job.audio.failed").get("status", ""))
				== "audio_failed",
		"Scheduler did not mark failed audio cache work without touching text status."
	)


func _test_equal_priority_text_dispatches_before_audio_cache() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	var audio_job := _job(
		"job.audio",
		"cache.audio",
		SchedulerType.PRIORITY_P0
	)
	audio_job["kind"] = "tts_cache"
	scheduler.queue_job(audio_job)
	scheduler.queue_job(_job(
		"job.text",
		"cache.text",
		SchedulerType.PRIORITY_P0
	))
	var next: Dictionary = scheduler.next_job()
	_expect(
		str(next.get("job_id", "")) == "job.text",
		"Scheduler let equal-priority audio cache work delay visible text."
	)
	var lower_priority_text := _job(
		"job.lower.text",
		"cache.lower.text",
		SchedulerType.PRIORITY_P1
	)
	scheduler.queue_job(lower_priority_text)
	_expect(
		str(scheduler.next_job().get("job_id", "")) == "job.text",
		"Scheduler kind ranking overrode priority bands."
	)


func _test_objective_progress_and_completion_plan_turn_in_prefetch() -> void:
	var early := SchedulerType.prefetch_jobs_for_event({
		"event_type": "objective_progress",
		"mission_id": "mission.alpha",
		"progress_fraction": 0.69,
	})
	var likely := SchedulerType.prefetch_jobs_for_event({
		"event_type": "objective_progress",
		"mission_id": "mission.alpha",
		"progress_fraction": 0.7,
		"outcome_fingerprint": "rough.pending",
		"story_revision": 8,
		"relationship_tier": "cordial",
	})
	var complete := SchedulerType.prefetch_jobs_for_event({
		"event_type": "objective_complete",
		"mission_id": "mission.alpha",
		"outcome_fingerprint": "clean.complete",
		"story_revision": 8,
		"relationship_tier": "trusted",
	})
	_expect(
		early.is_empty()
			and likely.size() == 1
			and complete.size() == 1,
		"Scheduler prefetch planner did not respect objective progress thresholds."
	)
	_expect(
		str(likely[0].get("trigger", ""))
			== SchedulerType.TRIGGER_OBJECTIVE_PROGRESS_TURN_IN
			and int(likely[0].get("priority", -1)) == SchedulerType.PRIORITY_P1
			and str(likely[0].get("kind", "")) == "kaelen_turn_in_bundle"
			and str(likely[0].get("relationship_tier", "")) == "cordial",
		"Scheduler progress prefetch job did not preserve likely turn-in context."
	)
	_expect(
		str(complete[0].get("trigger", ""))
			== SchedulerType.TRIGGER_OBJECTIVE_COMPLETE_TURN_IN
			and int(complete[0].get("priority", -1)) == SchedulerType.PRIORITY_P0
			and str(complete[0].get("outcome_fingerprint", ""))
				== "clean.complete",
		"Scheduler completion prefetch job did not become exact P0 turn-in work."
	)


func _test_mission_acceptance_plans_baseline_and_likely_outcomes() -> void:
	var jobs := SchedulerType.prefetch_jobs_for_event({
		"event_type": "mission_accepted",
		"mission_id": "mission.beta",
		"story_revision": 11,
		"relationship_tier": "wary",
		"likely_outcome_variants": ["turn_in_clean", "turn_in_rough"],
	})
	var variants: Array[String] = []
	for job in jobs:
		variants.append(str(job.get("outcome_variant", "")))
	_expect(
		jobs.size() == 3
			and variants.has("abandon_baseline")
			and variants.has("turn_in_clean")
			and variants.has("turn_in_rough"),
		"Scheduler mission acceptance prefetch did not include baseline and likely outcomes."
	)
	for job in jobs:
		_expect(
			str(job.get("trigger", ""))
				== SchedulerType.TRIGGER_MISSION_ACCEPTANCE_OUTCOMES
				and int(job.get("priority", -1)) == SchedulerType.PRIORITY_P1
				and bool(job.get("truth_frozen", false))
				and str(job.get("relationship_tier", "")) == "wary",
			"Mission acceptance prefetch job did not preserve frozen accepted context."
		)


func _test_system_arrival_plans_current_system_and_station_prefetch() -> void:
	var jobs := SchedulerType.prefetch_jobs_for_event({
		"event_type": "system_arrived",
		"system_id": "system.generated.cinder",
		"arrival_gate_id": "gate.generated.cinder.in",
		"visible_station_ids": [
			"station.cinder.exchange",
			"station.cinder.relay",
		],
		"story_revision": 12,
		"knowledge_revision": 4,
	})
	var triggers: Array[String] = []
	var station_job_count := 0
	for job in jobs:
		triggers.append(str(job.get("trigger", "")))
		if str(job.get("trigger", "")) \
				== SchedulerType.TRIGGER_CURRENT_VISIBLE_STATION:
			station_job_count += 1
			_expect(
				int(job.get("priority", -1)) == SchedulerType.PRIORITY_P0
					and str(job.get("system_id", ""))
						== "system.generated.cinder"
					and str(job.get("arrival_gate_id", ""))
						== "gate.generated.cinder.in",
				"System arrival station prefetch did not preserve arrival context."
			)
	_expect(
		jobs.size() == 5
			and triggers.has(SchedulerType.TRIGGER_CURRENT_SYSTEM_AGENT)
			and triggers.has(SchedulerType.TRIGGER_CURRENT_SYSTEM_KAELEN)
			and triggers.has(SchedulerType.TRIGGER_CURRENT_SYSTEM_NOVA)
			and station_job_count == 2,
		"Scheduler system arrival prefetch did not plan current-system and visible-station jobs."
	)


func _test_station_target_plans_agent_mechanic_and_lounge_prefetch() -> void:
	var jobs := SchedulerType.prefetch_jobs_for_event({
		"event_type": "station_targeted",
		"station_id": "station.cinder.exchange",
		"system_id": "system.generated.cinder",
		"target_reason": "fly_to",
		"station_type": "full_service",
		"story_revision": 13,
	})
	var triggers: Array[String] = []
	for job in jobs:
		triggers.append(str(job.get("trigger", "")))
		_expect(
			str(job.get("station_id", "")) == "station.cinder.exchange"
				and str(job.get("target_reason", "")) == "fly_to",
			"Station target prefetch did not preserve station targeting context."
		)
	_expect(
		jobs.size() == 3
			and triggers.has(SchedulerType.TRIGGER_CURRENT_VISIBLE_STATION)
			and triggers.has(SchedulerType.TRIGGER_MECHANIC_GREETING)
			and triggers.has(SchedulerType.TRIGGER_LIKELY_LOUNGE)
			and int(jobs[0].get("priority", -1)) == SchedulerType.PRIORITY_P0,
		"Scheduler station target prefetch did not plan station, mechanic, and lounge work."
	)


func _test_chapter_packet_ready_plans_first_interaction_prefetch() -> void:
	var jobs := SchedulerType.prefetch_jobs_for_event({
		"event_type": "chapter_packet_ready",
		"packet_id": "chapter_packet.2",
		"chapter": 2,
		"first_beat_ids": ["beat.alpha", "beat.beta"],
		"system_id": "system.generated.cinder",
		"story_revision": 15,
	})
	_expect(
		jobs.size() == 2
			and str(jobs[0].get("kind", "")) == "chapter_first_interaction_bundle"
			and str(jobs[0].get("packet_id", "")) == "chapter_packet.2"
			and int(jobs[0].get("chapter", 0)) == 2
			and str(jobs[0].get("story_beat_id", "")) == "beat.alpha"
			and int(jobs[0].get("priority", -1)) == SchedulerType.PRIORITY_P1,
		"Scheduler chapter packet ready prefetch did not plan first interaction bundles."
	)


func _test_new_campaign_loading_plans_startup_prefetch_bundle() -> void:
	var jobs := SchedulerType.prefetch_jobs_for_event({
		"event_type": "new_campaign_loading",
		"system_id": "system.start",
		"station_id": "station.start.iron_reach",
		"packet_id": "chapter_packet.1",
		"chapter": 1,
		"first_beat_ids": ["beat.opening"],
		"story_revision": 1,
	})
	var kinds: Array[String] = []
	var triggers: Array[String] = []
	for job in jobs:
		kinds.append(str(job.get("kind", "")))
		triggers.append(str(job.get("trigger", "")))
	_expect(
		jobs.size() == 6
			and kinds.has("current_station_agent_offer_bundle")
			and kinds.has("mechanic_greeting_bundle")
			and kinds.has("likely_lounge_opener_bundle")
			and kinds.has("new_campaign_kaelen_handoff_bank")
			and kinds.has("new_campaign_nova_bank")
			and kinds.has("chapter_first_interaction_bundle")
			and triggers.has(SchedulerType.TRIGGER_CURRENT_VISIBLE_STATION)
			and triggers.has(SchedulerType.TRIGGER_CURRENT_SYSTEM_KAELEN)
			and triggers.has(SchedulerType.TRIGGER_CURRENT_SYSTEM_NOVA),
		"Scheduler new campaign loading prefetch did not plan the startup bundle."
	)


func _test_game_root_acceptance_hook_calls_prefetch_planner() -> void:
	var file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect GameRoot prefetch wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("func _on_quest_accepted_chronicle")
			and source.contains("_queue_narrative_prefetch_jobs_for_event")
			and source.contains("_narrative_prefetch_event_from_quest(quest, \"mission_accepted\")")
			and source.contains("_narrative_prefetch_event_from_quest(quest, \"objective_progress\")")
			and source.contains("_narrative_prefetch_event_from_quest(quest, \"objective_complete\")")
			and source.contains("system_changed.connect(_on_system_arrival_prefetch)")
			and source.contains("_narrative_prefetch_event_from_system_arrival")
			and source.contains("QuestManager.quest_progress_updated.connect(_on_quest_progress_prefetch)")
			and source.contains("NarrativeCacheSchedulerType.prefetch_jobs_for_event"),
		"GameRoot mission lifecycle hooks are not wired to the narrative prefetch planner."
	)


func _test_station_target_hooks_call_prefetch_planner() -> void:
	var game_root_file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	var ui_file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(
		game_root_file != null and ui_file != null,
		"Could not inspect station target prefetch wiring."
	)
	if game_root_file == null or ui_file == null:
		return
	var game_root_source := game_root_file.get_as_text()
	var ui_source := ui_file.get_as_text()
	_expect(
		game_root_source.contains("queue_narrative_station_target_prefetch")
			and game_root_source.contains("_narrative_prefetch_event_from_station_target")
			and game_root_source.contains("\"event_type\": \"station_targeted\"")
			and ui_source.contains("_queue_station_target_prefetch")
			and ui_source.contains("queue_narrative_station_target_prefetch")
			and ui_source.contains("\"fly_to\"")
			and ui_source.contains("\"dock\""),
		"Station target/fly-to hooks are not wired to the narrative prefetch planner."
	)


func _test_chapter_packet_ready_hook_calls_prefetch_planner() -> void:
	var file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect chapter packet prefetch wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("_narrative_prefetch_event_from_chapter_packet")
			and source.contains("\"event_type\": \"chapter_packet_ready\"")
			and source.contains("\"first_beat_ids\"")
			and source.contains("_queue_narrative_prefetch_jobs_for_event("),
		"Chapter packet ready hook is not wired to the narrative prefetch planner."
	)


func _test_queue_health_reports_contention_and_starvation() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	scheduler.queue_job(_job("job.flight", "cache.health.flight", SchedulerType.PRIORITY_P0))
	scheduler.queue_job(_job("job.waiting", "cache.health.waiting", SchedulerType.PRIORITY_P1))
	scheduler.mark_generation_started("job.flight")
	var health: Dictionary = scheduler.queue_health(0)
	_expect(
		bool(health.get("contention", false))
			and int(health.get("in_flight_count", 0)) == 1
			and (health.get("in_flight", []) as Array).has("job.flight")
			and int(health.get("pending_by_priority", {}).get(
				str(SchedulerType.PRIORITY_P1),
				0
			)) == 1
			and (health.get("starved_jobs", []) as Array).size() == 1,
		"Scheduler queue health did not report contention and queued starvation."
	)


func _test_pool_refill_waits_for_higher_priority_work() -> void:
	var scheduler: RefCounted = SchedulerType.new()
	_expect(
		scheduler.can_refill_pool(1, 2),
		"Scheduler should allow refill when pool is below threshold and idle."
	)
	var queued: Dictionary = scheduler.queue_pool_refill_job(
		"ambient.system.cinder",
		1,
		2,
		{"system_id": "system.generated.cinder", "story_revision": 14}
	)
	_expect(
		bool(queued.get("ok", false))
			and str(queued.get("job", {}).get("trigger", ""))
				== SchedulerType.TRIGGER_AMBIENT_REPLENISHMENT
			and int(queued.get("job", {}).get("priority", -1))
				== SchedulerType.PRIORITY_P3
			and str(queued.get("job", {}).get("system_id", ""))
				== "system.generated.cinder",
		"Scheduler did not queue safe ambient pool refill work."
	)
	scheduler.mark_generation_started(
		str(queued.get("job", {}).get("job_id", ""))
	)
	scheduler.mark_ready(str(queued.get("job", {}).get("job_id", "")))
	scheduler.queue_job(_job("job.p1", "cache.refill.p1", SchedulerType.PRIORITY_P1))
	_expect(
		not scheduler.can_refill_pool(1, 2),
		"Scheduler allowed ambient refill while higher-priority work was pending."
	)
	var deferred: Dictionary = scheduler.queue_pool_refill_job(
		"ambient.system.cinder",
		1,
		2
	)
	_expect(
		not bool(deferred.get("ok", true))
			and bool(deferred.get("deferred", false)),
		"Scheduler queued pool refill while higher-priority work was pending."
	)
	scheduler.mark_generation_started("job.p1")
	scheduler.mark_ready("job.p1")
	_expect(
		not scheduler.can_refill_pool(2, 2)
			and scheduler.can_refill_pool(1, 2),
		"Scheduler pool refill threshold check did not recover after priority work finished."
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
