extends SceneTree

const BibleStoreType := preload(
	"res://scripts/persistence/CampaignBibleStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://campaign_bible_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_bible_bootstrap_replace_and_reopen()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Campaign bible store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_bible_bootstrap_replace_and_reopen() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"Bible Fixture",
		"bible-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return

	var store := BibleStoreType.open(CAMPAIGN_PATH)
	_expect(
		store.is_valid(),
		"Campaign bible store is invalid: %s" %
			JSON.stringify(store.validation.to_dict())
	)
	if not store.is_valid():
		return
	_expect(
		store.prompt_context().contains("Kaelen"),
		"Default campaign bible prompt context did not mention Kaelen."
	)
	_expect(
		store.generation_status() == BibleStoreType.STATUS_PROCEDURAL_BOOTSTRAP,
		"Default campaign bible did not expose procedural bootstrap status."
	)
	_expect(
		store.prompt_context().contains("Generation status: procedural_bootstrap"),
		"Default campaign bible prompt context did not expose generation status."
	)
	_expect(
		store.prompt_context().contains("Story horizon regeneration triggers"),
		"Default campaign bible prompt context did not include regeneration triggers."
	)
	var default_trail: Dictionary = store.data.get("rumor_trails", [])[0]
	_expect(
		str(default_trail.get("trail_id", "")).begins_with("rumor_trail."),
		"Default campaign bible rumor trail did not include a trail id."
	)
	_expect(
		str(default_trail.get("discovery_type", "")) == "endgame_easter_egg",
		"Default campaign bible rumor trail did not include a discovery type."
	)
	var default_trigger: Dictionary = store.data.get("regeneration_triggers", [])[0]
	_expect(
		str(default_trigger.get("metric", "")) == "prepared_systems_remaining"
			and str(default_trigger.get("action", "")) == "append_story_horizon",
		"Default campaign bible regeneration trigger was not structured."
	)

	var replacement := store.data.duplicate(true)
	replacement["tone"] = "Dry frontier comedy with sudden consequences."
	replacement["story_horizon_rule"] = "Extend the story horizon when Glass Choir clues run low."
	replacement["story_arcs"] = [{
		"name": "Glass Choir",
		"summary": "A quiet faction keeps turning distress calls into hymns.",
	}]
	replacement["regeneration_triggers"] = [{
		"id": "glass_choir_low",
		"description": "The choir has fewer than two prepared clues left.",
	}]
	replacement["rumor_trails"] = [{
		"name": "Glass Choir Static",
		"clue_count": 3,
		"payoff": "A hidden transmitter in a silent belt.",
	}]
	var replaced := store.replace_bible(replacement)
	_expect(bool(replaced.get("ok", false)), replaced.get("error", ""))
	_expect(
		store.generation_status() == BibleStoreType.STATUS_PROCEDURAL_BOOTSTRAP,
		"Replacement campaign bible should preserve an explicit source/status."
	)
	_expect(
		store.prompt_context().contains("Glass Choir"),
		"Replacement campaign bible did not update prompt context."
	)
	var normalized_trail: Dictionary = store.data.get("rumor_trails", [])[0]
	_expect(
		str(normalized_trail.get("trail_id", "")) == "rumor_trail.glass_choir_static"
			and str(normalized_trail.get("discovery_type", "")) == "hidden_discovery",
		"Simple replacement rumor trail was not normalized for future clue tracking."
	)
	var normalized_trigger: Dictionary = store.data.get("regeneration_triggers", [])[0]
	_expect(
		str(normalized_trigger.get("metric", "")) == "prepared_systems_remaining"
			and int(normalized_trigger.get("threshold", -1)) == 2,
		"Simple replacement regeneration trigger was not normalized for future horizon checks."
	)

	var reopened := BibleStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid()
			and reopened.prompt_context().contains("Glass Choir"),
		"Campaign bible did not persist after reopening."
	)
	_expect(
		reopened.prompt_context().contains("glass_choir_low"),
		"Campaign bible regeneration trigger did not persist after reopening."
	)
	var unavailable := reopened.mark_model_unavailable(
		"Large story model is not installed.",
		"gemma4:12b"
	)
	_expect(bool(unavailable.get("ok", false)), unavailable.get("error", ""))
	_expect(
		reopened.generation_status() == BibleStoreType.STATUS_LLM_UNAVAILABLE,
		"Campaign bible did not record explicit local-model-unavailable status."
	)
	_expect(
		reopened.status_summary().contains("gemma4:12b"),
		"Campaign bible unavailable status did not keep the model name."
	)
	var unavailable_reopened := BibleStoreType.open(CAMPAIGN_PATH)
	_expect(
		unavailable_reopened.generation_status() == BibleStoreType.STATUS_LLM_UNAVAILABLE,
		"Campaign bible unavailable status did not persist after reopening."
	)
	var failed := unavailable_reopened.mark_generation_failed(
		"campaign_bible_validation_failed",
		"gemma4:12b"
	)
	_expect(bool(failed.get("ok", false)), failed.get("error", ""))
	_expect(
		unavailable_reopened.generation_status() == BibleStoreType.STATUS_GENERATION_FAILED,
		"Campaign bible did not record explicit generation-failed status."
	)
	_expect(
		unavailable_reopened.status_summary().contains("campaign_bible_validation_failed"),
		"Campaign bible failed status did not keep the failure reason."
	)


func _initial_state() -> Dictionary:
	return {
		"current_system_id": "system.start",
		"player": {"health": 100.0, "shield": 0.0},
		"global": {
			"credits": 50,
			"cargo": 0.0,
			"upgrades": {},
			"reputations": {},
		},
		"quest": {},
		"systems": {},
	}


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
