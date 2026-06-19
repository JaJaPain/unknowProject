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
		store.prompt_context().contains("Story horizon regeneration triggers"),
		"Default campaign bible prompt context did not include regeneration triggers."
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
	var replaced := store.replace_bible(replacement)
	_expect(bool(replaced.get("ok", false)), replaced.get("error", ""))
	_expect(
		store.prompt_context().contains("Glass Choir"),
		"Replacement campaign bible did not update prompt context."
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
