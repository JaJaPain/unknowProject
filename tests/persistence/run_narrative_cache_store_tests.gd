extends SceneTree

const CacheStoreType := preload("res://scripts/persistence/NarrativeCacheStore.gd")
const SchemaCatalogType := preload("res://scripts/persistence/CampaignSchemaCatalog.gd")

const TEST_ROOT := "res://.tmp_godot_user/narrative_cache_store_fixture"
const CAMPAIGN_ID := "campaign.local.narrative_cache_fixture"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_write_campaign()
	_test_bootstrap_upsert_reopen_consume_and_invalidate()
	_test_schema_catalog_marks_cache_disposable()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Narrative cache store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


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
