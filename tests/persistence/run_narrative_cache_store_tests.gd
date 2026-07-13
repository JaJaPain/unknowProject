extends SceneTree

const CacheStoreType := preload("res://scripts/persistence/NarrativeCacheStore.gd")
const SchemaCatalogType := preload("res://scripts/persistence/CampaignSchemaCatalog.gd")

const TEST_ROOT := "res://.tmp_godot_user/narrative_cache_store_fixture"
const CAMPAIGN_ID := "campaign.local.narrative_cache_fixture"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_write_campaign()
	_test_semantic_cache_keys_use_truth_inputs()
	_test_bootstrap_upsert_reopen_consume_and_invalidate()
	_test_mark_field_displayed_persists_one_shot_consumption()
	_test_stale_offer_invalidation_preserves_consumed_and_frozen_entries()
	_test_context_discard_preserves_truth_frozen_entries()
	_test_limit_enforcement_evicts_disposable_entries_first()
	_test_text_fingerprints_survive_entry_eviction()
	_test_text_fingerprint_lookup_detects_prior_lines()
	_test_clear_cache_removes_entries_and_fingerprints()
	_test_tts_readiness_tracks_field_voice_and_text_fingerprint()
	_test_readiness_reports_text_audio_pending_and_failed_separately()
	_test_result_payload_update_persists_fallback_bank_state()
	_test_schema_catalog_marks_cache_disposable()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Narrative cache store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_semantic_cache_keys_use_truth_inputs() -> void:
	var base := _semantic_inputs()
	var reordered := _semantic_inputs()
	reordered["knowledge_fact_states"] = {
		"fact.b": "rumored",
		"fact.a": "known",
	}
	var base_key := CacheStoreType.semantic_cache_key(base)
	_expect(
		base_key == CacheStoreType.semantic_cache_key(reordered),
		"Semantic cache key changed when dictionary order changed."
	)
	var story_changed := _semantic_inputs()
	story_changed["story_revision"] = 8
	_expect(
		base_key != CacheStoreType.semantic_cache_key(story_changed),
		"Semantic cache key ignored story revision."
	)
	var knowledge_changed := _semantic_inputs()
	knowledge_changed["knowledge_fact_states"] = {
		"fact.a": "confirmed",
		"fact.b": "rumored",
	}
	_expect(
		base_key != CacheStoreType.semantic_cache_key(knowledge_changed),
		"Semantic cache key ignored relevant fact state changes."
	)
	var noisy := _semantic_inputs()
	noisy["credits"] = 999999
	noisy["hull_points"] = 1
	noisy["minute_tick"] = 123456
	_expect(
		base_key == CacheStoreType.semantic_cache_key(noisy),
		"Semantic cache key included unrelated raw runtime noise."
	)
	_expect(
		CacheStoreType.semantic_context_fingerprint(base).length() == 64,
		"Semantic context fingerprint should be a full SHA-256 hex string."
	)


func _test_bootstrap_upsert_reopen_consume_and_invalidate() -> void:
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	_expect(
		store.is_valid(),
		"Narrative cache store did not bootstrap cleanly: %s" %
			store.validation.summary()
	)
	_expect(store.entries().is_empty(), "New narrative cache should start empty.")
	var upserted: Dictionary = store.upsert_entry(_entry("cache.mission.alpha"))
	_expect(bool(upserted.get("ok", false)), str(upserted.get("error", "")))
	_expect(
		str(store.get_entry("cache.mission.alpha").get("kind", ""))
			== "mission_conversation",
		"Narrative cache did not expose the upserted entry."
	)
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	_expect(
		reopened.is_valid()
			and str(reopened.get_entry("cache.mission.alpha").get("campaign_id", ""))
				== CAMPAIGN_ID,
		"Narrative cache did not persist and reopen with campaign ownership."
	)
	var consumed: Dictionary = reopened.mark_consumed("cache.mission.alpha")
	_expect(bool(consumed.get("ok", false)), "Narrative cache did not mark consumed.")
	var consumed_reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	_expect(
		bool(consumed_reopened.get_entry("cache.mission.alpha").get("consumed", false)),
		"Narrative cache did not persist consumed state."
	)
	var invalidated: Dictionary = consumed_reopened.invalidate_by_subject("offer.alpha")
	_expect(
		bool(invalidated.get("ok", false))
			and (invalidated.get("removed", []) as Array).has("cache.mission.alpha"),
		"Narrative cache did not invalidate matching subject entries."
	)
	var final_reopen: RefCounted = CacheStoreType.open(TEST_ROOT)
	_expect(
		final_reopen.get_entry("cache.mission.alpha").is_empty(),
		"Narrative cache invalidated entry reappeared after reopen."
	)


func _test_mark_field_displayed_persists_one_shot_consumption() -> void:
	_cleanup()
	_write_campaign()
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	store.upsert_entry(_entry("cache.display.alpha"))
	var displayed: Dictionary = store.mark_field_displayed(
		"cache.display.alpha",
		"opening"
	)
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	var entry: Dictionary = reopened.get_entry("cache.display.alpha")
	var fields: Dictionary = entry.get("displayed_fields", {})
	_expect(
		bool(displayed.get("ok", false))
			and not bool(entry.get("consumed", false))
			and fields.has("opening")
			and str(fields.get("opening", {}).get("text_fingerprint", ""))
				== CacheStoreType.text_fingerprint("The cache has work."),
		"Displayed field marker did not persist without consuming the whole entry."
	)


func _test_stale_offer_invalidation_preserves_consumed_and_frozen_entries() -> void:
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	store.upsert_entry(_entry_with_truth("cache.stale.unconsumed", false, false))
	store.upsert_entry(_entry_with_truth("cache.stale.consumed", true, false))
	store.upsert_entry(_entry_with_truth("cache.stale.frozen", false, true))
	store.upsert_entry(_entry_with_truth("cache.other.beat", false, false, "beat.other"))
	var invalidated: Dictionary = store.invalidate_unconsumed_stale_offers({
		"story_beat_id": "beat.alpha",
	})
	var removed: Array = invalidated.get("removed", [])
	_expect(
		bool(invalidated.get("ok", false))
			and removed == ["cache.stale.unconsumed"],
		"Stale invalidation did not remove only unconsumed matching offers."
	)
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	_expect(
		reopened.get_entry("cache.stale.unconsumed").is_empty()
			and not reopened.get_entry("cache.stale.consumed").is_empty()
			and not reopened.get_entry("cache.stale.frozen").is_empty()
			and not reopened.get_entry("cache.other.beat").is_empty(),
		"Stale invalidation did not persist the expected survivor set."
	)


func _test_context_discard_preserves_truth_frozen_entries() -> void:
	_cleanup()
	_write_campaign()
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	store.upsert_entry(_context_entry("cache.context.current", "timeline.a", 7, false))
	store.upsert_entry(_context_entry("cache.context.old", "timeline.old", 6, false))
	store.upsert_entry(_context_entry("cache.context.accepted", "timeline.old", 6, true))
	var discarded: Dictionary = store.discard_entries_outside_context({
		"timeline_id": "timeline.a",
		"story_revision": 7,
	})
	var removed: Array = discarded.get("removed", [])
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	_expect(
		bool(discarded.get("ok", false))
			and removed == ["cache.context.old"]
			and not reopened.get_entry("cache.context.current").is_empty()
			and reopened.get_entry("cache.context.old").is_empty()
			and not reopened.get_entry("cache.context.accepted").is_empty(),
		"Context discard did not remove only mismatched disposable entries."
	)


func _test_limit_enforcement_evicts_disposable_entries_first() -> void:
	_cleanup()
	_write_campaign()
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	store.upsert_entry(_limited_entry("cache.limit.accepted", 0, "accepted", false))
	store.upsert_entry(_limited_entry("cache.limit.ready", 0, "ready", false))
	store.upsert_entry(_limited_entry("cache.limit.expired", 10, "ready", false, 1))
	store.upsert_entry(_limited_entry("cache.limit.consumed", 30, "ready", true))
	var enforced: Dictionary = store.enforce_limits(2, 0)
	var removed: Array = enforced.get("removed", [])
	_expect(
		bool(enforced.get("ok", false))
			and removed == ["cache.limit.consumed", "cache.limit.expired"],
		"Cache limit enforcement did not evict consumed/expired entries first."
	)
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	_expect(
		reopened.entries().size() == 2
			and not reopened.get_entry("cache.limit.accepted").is_empty()
			and not reopened.get_entry("cache.limit.ready").is_empty(),
		"Cache limit enforcement did not persist the bounded survivor set."
	)


func _test_text_fingerprints_survive_entry_eviction() -> void:
	_cleanup()
	_write_campaign()
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	var evicted := _limited_entry("cache.fingerprint.evicted", 30, "ready", true)
	evicted["text_bundle"]["opening"] = "Nobody gets to unhear the nebula joke."
	store.upsert_entry(evicted)
	store.upsert_entry(_limited_entry("cache.fingerprint.kept", 0, "ready", false))
	var enforced: Dictionary = store.enforce_limits(1, 0)
	var fingerprint := CacheStoreType.text_fingerprint(
		"Nobody gets to unhear the nebula joke."
	)
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	_expect(
		bool(enforced.get("ok", false))
			and reopened.get_entry("cache.fingerprint.evicted").is_empty()
			and reopened.text_fingerprints().has(fingerprint),
		"Cache text fingerprint did not survive entry eviction."
	)


func _test_text_fingerprint_lookup_detects_prior_lines() -> void:
	_cleanup()
	_write_campaign()
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	store.upsert_entry(_entry("cache.fingerprint.lookup"))
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	_expect(
		reopened.has_text_fingerprint("The cache has work.")
			and not reopened.has_text_fingerprint("A line nobody has stored."),
		"Cache text fingerprint lookup did not detect prior generated lines."
	)


func _test_clear_cache_removes_entries_and_fingerprints() -> void:
	_cleanup()
	_write_campaign()
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	store.upsert_entry(_entry("cache.clear.alpha"))
	var cleared: Dictionary = store.clear_cache("narrative_cache_test_clear")
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	_expect(
		bool(cleared.get("ok", false))
			and reopened.entries().is_empty()
			and reopened.text_fingerprints().is_empty(),
		"Cache clear did not remove entries and text fingerprints."
	)


func _test_tts_readiness_tracks_field_voice_and_text_fingerprint() -> void:
	_cleanup()
	_write_campaign()
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	store.upsert_entry(_entry("cache.tts.alpha"))
	var marked: Dictionary = store.mark_tts_status(
		"cache.tts.alpha",
		"opening",
		"voice.agent.alpha",
		"ready",
		"user://tts/cache.tts.alpha/opening.ogg"
	)
	var failed: Dictionary = store.mark_tts_status(
		"cache.tts.alpha",
		"accept_standard_response",
		"voice.agent.alpha",
		"failed"
	)
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	var entry: Dictionary = reopened.get_entry("cache.tts.alpha")
	var tts: Dictionary = entry.get("tts_ready", {})
	_expect(
		bool(marked.get("ok", false))
			and bool(failed.get("ok", false))
			and str(tts.get("opening|voice.agent.alpha", {}).get("status", ""))
				== "ready"
			and str(tts.get("accept_standard_response|voice.agent.alpha", {}).get(
				"status",
				""
			)) == "failed"
			and str(tts.get("opening|voice.agent.alpha", {}).get(
				"text_fingerprint",
				""
			)) == CacheStoreType.text_fingerprint("The cache has work."),
		"Cache TTS readiness did not track field, voice, status, and text fingerprint."
	)


func _test_readiness_reports_text_audio_pending_and_failed_separately() -> void:
	_cleanup()
	_write_campaign()
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	store.upsert_entry(_entry("cache.ready.alpha"))
	store.mark_tts_status(
		"cache.ready.alpha",
		"opening",
		"voice.agent.alpha",
		"ready",
		"user://tts/opening.ogg"
	)
	store.mark_tts_status(
		"cache.ready.alpha",
		"accept_standard_response",
		"voice.agent.alpha",
		"failed"
	)
	var status: Dictionary = store.readiness(
		"cache.ready.alpha",
		["opening", "accept_standard_response"],
		"voice.agent.alpha"
	)
	_expect(
		bool(status.get("text_ready", false))
			and not bool(status.get("audio_ready", true))
			and (status.get("missing_audio_fields", []) as Array).is_empty()
			and (status.get("failed_audio_fields", []) as Array).has(
				"accept_standard_response"
			),
		"Cache readiness did not separate text readiness from audio failure."
	)


func _test_result_payload_update_persists_fallback_bank_state() -> void:
	_cleanup()
	_write_campaign()
	var store: RefCounted = CacheStoreType.open(TEST_ROOT)
	store.upsert_entry(_entry("cache.line_bank.alpha"))
	var updated: Dictionary = store.update_result_payload("cache.line_bank.alpha", {
		"content_type": "story_line_bank",
		"fallback_uses": 1,
		"generated_replacements": 1,
		"fallback_bank": {
			"target_size": 20,
			"entries": [{
				"text": "Generated replacement.",
				"source": "llm_kaelen_handoff",
				"is_fallback": false,
			}],
		},
	})
	var reopened: RefCounted = CacheStoreType.open(TEST_ROOT)
	var entry: Dictionary = reopened.get_entry("cache.line_bank.alpha")
	var payload: Dictionary = entry.get("result_payload", {}) \
		if entry.get("result_payload", {}) is Dictionary else {}
	var bank: Dictionary = payload.get("fallback_bank", {}) \
		if payload.get("fallback_bank", {}) is Dictionary else {}
	_expect(
		bool(updated.get("ok", false))
			and int(payload.get("fallback_uses", 0)) == 1
			and int(payload.get("generated_replacements", 0)) == 1
			and int(bank.get("target_size", 0)) == 20,
		"Narrative cache store did not persist fallback-bank result payload updates."
	)


func _test_schema_catalog_marks_cache_disposable() -> void:
	_expect(
		SchemaCatalogType.ownership_for("narrative_cache") == "disposable",
		"Schema catalog did not mark narrative_cache as disposable."
	)
	var document := {
		"schema_version": 1,
		"document_type": "narrative_cache",
		"ownership": "disposable",
		"campaign_id": CAMPAIGN_ID,
		"entries": {
			"cache.mission.alpha": _entry("cache.mission.alpha"),
		},
	}
	var validation = SchemaCatalogType.validate_document(document)
	_expect(
		validation.is_valid(),
		"Schema catalog rejected valid narrative cache document: %s" %
			validation.summary()
	)


func _entry(cache_key: String) -> Dictionary:
	return {
		"cache_key": cache_key,
		"kind": "mission_conversation",
		"subject_id": "offer.alpha",
		"speaker_id": "agent.alpha",
		"system_id": "system.start",
		"context_fingerprint": "fingerprint.alpha",
		"text_bundle": {
			"opening": "The cache has work.",
			"accept_standard_response": "Logged.",
		},
		"consumed": false,
	}


func _entry_with_truth(
	cache_key: String,
	consumed: bool,
	truth_frozen: bool,
	beat_id: String = "beat.alpha"
) -> Dictionary:
	var entry := _entry(cache_key)
	entry["subject_id"] = cache_key
	entry["story_beat_id"] = beat_id
	entry["giver_npc_id"] = "agent.alpha"
	entry["destination_id"] = "station.start.main"
	entry["objective_fingerprint"] = "objective.alpha"
	entry["allowed_facts_fingerprint"] = "facts.alpha"
	entry["relationship_tier"] = "cordial"
	entry["consumed"] = consumed
	entry["truth_frozen"] = truth_frozen
	entry["status"] = "accepted" if truth_frozen else "ready"
	return entry


func _limited_entry(
	cache_key: String,
	priority: int,
	status: String,
	consumed: bool,
	expires_at_unix: int = 0
) -> Dictionary:
	var entry := _entry(cache_key)
	entry["subject_id"] = cache_key
	entry["priority"] = priority
	entry["status"] = status
	entry["consumed"] = consumed
	entry["truth_frozen"] = status == "accepted"
	if expires_at_unix > 0:
		entry["expires_at_unix"] = expires_at_unix
	return entry


func _context_entry(
	cache_key: String,
	timeline_id: String,
	story_revision: int,
	truth_frozen: bool
) -> Dictionary:
	var entry := _entry(cache_key)
	entry["subject_id"] = cache_key
	entry["timeline_id"] = timeline_id
	entry["context_revision"] = story_revision
	entry["story_revision"] = story_revision
	entry["knowledge_revision"] = story_revision
	entry["relationship_revision"] = story_revision
	entry["truth_frozen"] = truth_frozen
	entry["status"] = "accepted" if truth_frozen else "ready"
	return entry


func _semantic_inputs() -> Dictionary:
	return {
		"campaign_id": CAMPAIGN_ID,
		"kind": "mission_conversation",
		"subject_id": "offer.alpha",
		"speaker_id": "agent.alpha",
		"system_id": "system.start",
		"station_id": "station.start.main",
		"story_revision": 7,
		"thread_revision": 2,
		"beat_revision": 3,
		"knowledge_revision": 12,
		"relationship_tier": "cordial",
		"relationship_revision": 4,
		"recent_line_digest": "recent.digest",
		"knowledge_fact_states": {
			"fact.a": "known",
			"fact.b": "rumored",
		},
		"mission_objective": {
			"type": "RECOVER_COMBAT_DROP",
			"item_name": "blackbox shard",
			"count_required": 3,
		},
		"choice_consequences": {
			"accept_standard": {
				"reward_credits_multiplier": 1.0,
			},
			"request_hazard_pay": {
				"reward_credits_multiplier": 1.15,
			},
		},
		"player_state_bands": {
			"hull": "safe",
		},
	}


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
