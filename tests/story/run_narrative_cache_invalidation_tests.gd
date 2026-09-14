extends SceneTree

const CacheStoreType := preload("res://scripts/persistence/NarrativeCacheStore.gd")
const SchedulerType := preload("res://scripts/story/NarrativeCacheScheduler.gd")

const TEST_ROOT := "res://.tmp_godot_user/narrative_cache_invalidation_fixture"
const CAMPAIGN_ID := "campaign.local.narrative_cache_invalidation"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_write_campaign()
	_test_store_and_scheduler_discard_stale_disposable_work()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Narrative cache invalidation tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_store_and_scheduler_discard_stale_disposable_work() -> void:
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	store.upsert_entry(_cache_entry("cache.current", "beat.current", false))
	store.upsert_entry(_cache_entry("cache.stale", "beat.old", false))
	store.upsert_entry(_cache_entry("cache.accepted", "beat.old", true))
	store.upsert_entry(_cache_entry(
		"cache.knowledge_stale",
		"beat.current",
		false,
		{"allowed_facts_fingerprint": "facts.old"}
	))
	store.upsert_entry(_cache_entry(
		"cache.relationship_stale",
		"beat.current",
		false,
		{"relationship_tier": "wary"}
	))
	var discarded: Dictionary = store.discard_entries_outside_context({
		"timeline_id": "timeline.current",
		"story_revision": 4,
	})
	var stale: Dictionary = store.invalidate_unconsumed_stale_offers({
		"story_beat_id": "beat.old",
		"allowed_facts_fingerprint": "facts.old",
		"relationship_tier": "wary",
	})
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	var scheduler: RefCounted = SchedulerType.new()
	scheduler.queue_job(_job("job.current", "beat.current", false))
	scheduler.queue_job(_job("job.stale", "beat.old", false))
	scheduler.queue_job(_job("job.frozen", "beat.old", true))
	scheduler.queue_job(_job(
		"job.knowledge_stale",
		"beat.current",
		false,
		{"allowed_facts_fingerprint": "facts.old"}
	))
	scheduler.queue_job(_job(
		"job.relationship_stale",
		"beat.current",
		false,
		{"relationship_tier": "wary"}
	))
	var scheduler_discarded: Dictionary = scheduler.discard_stale_jobs({
		"story_beat_id": "beat.old",
		"allowed_facts_fingerprint": "facts.old",
		"relationship_tier": "wary",
	})
	_expect(
		bool(discarded.get("ok", false))
			and bool(stale.get("ok", false))
			and reopened.get_entry("cache.stale").is_empty()
			and reopened.get_entry("cache.knowledge_stale").is_empty()
			and reopened.get_entry("cache.relationship_stale").is_empty()
			and not reopened.get_entry("cache.current").is_empty()
			and not reopened.get_entry("cache.accepted").is_empty(),
		"Cache store did not discard stale disposable entries while preserving accepted truth."
	)
	_expect(
		(scheduler_discarded.get("removed", []) as Array) == [
			"job.stale",
			"job.knowledge_stale",
			"job.relationship_stale",
		]
			and str(scheduler.get_job("job.stale").get("status", ""))
				== "stale_discarded"
			and str(scheduler.get_job("job.knowledge_stale").get("status", ""))
				== "stale_discarded"
			and str(scheduler.get_job("job.relationship_stale").get("status", ""))
				== "stale_discarded"
			and str(scheduler.get_job("job.current").get("status", "")) == "queued"
			and str(scheduler.get_job("job.frozen").get("status", "")) == "accepted",
		"Scheduler did not discard only stale disposable jobs."
	)


func _cache_entry(
	cache_key: String,
	beat_id: String,
	truth_frozen: bool,
	overrides: Dictionary = {}
) -> Dictionary:
	var entry := {
		"cache_key": cache_key,
		"kind": "mission_conversation",
		"subject_id": cache_key,
		"speaker_id": "agent.alpha",
		"system_id": "system.start",
		"context_fingerprint": cache_key.sha256_text(),
		"timeline_id": "timeline.current" if beat_id == "beat.current" else "timeline.old",
		"story_revision": 4 if beat_id == "beat.current" else 3,
		"story_beat_id": beat_id,
		"giver_npc_id": "agent.alpha",
		"destination_id": "station.start.main",
		"objective_fingerprint": "objective.alpha",
		"allowed_facts_fingerprint": "facts.alpha",
		"relationship_tier": "cordial",
		"truth_frozen": truth_frozen,
		"status": "accepted" if truth_frozen else "ready",
		"text_bundle": {
			"opening": "Cache entry %s." % cache_key,
			"accept_standard_response": "Logged.",
		},
	}
	entry.merge(overrides, true)
	return entry


func _job(
	job_id: String,
	beat_id: String,
	truth_frozen: bool,
	overrides: Dictionary = {}
) -> Dictionary:
	var job := {
		"job_id": job_id,
		"cache_key": "%s.cache" % job_id,
		"kind": "mission_conversation",
		"priority": SchedulerType.PRIORITY_P1,
		"story_beat_id": beat_id,
		"giver_npc_id": "agent.alpha",
		"destination_id": "station.start.main",
		"objective_fingerprint": "objective.alpha",
		"allowed_facts_fingerprint": "facts.alpha",
		"relationship_tier": "cordial",
		"truth_frozen": truth_frozen,
		"status": "accepted" if truth_frozen else "queued",
	}
	job.merge(overrides, true)
	return job


func _write_campaign() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	DirAccess.make_dir_recursive_absolute(absolute)
	var file := FileAccess.open("%s/campaign.json" % TEST_ROOT, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write campaign fixture.")
		return
	file.store_string(JSON.stringify({
		"id": CAMPAIGN_ID,
		"campaign_id": CAMPAIGN_ID,
		"schema_version": 1,
		"document_type": "campaign",
	}))


func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_directory(absolute)


func _remove_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := "%s/%s" % [path, entry]
			if directory.current_is_dir():
				_remove_directory(child)
			else:
				DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
