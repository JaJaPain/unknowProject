extends SceneTree

const IdeaMemoryStoreType := preload(
	"res://scripts/persistence/CampaignIdeaMemoryStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://campaign_idea_memory_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_idea_memory_bootstrap_append_query_and_reopen()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Campaign idea memory store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_idea_memory_bootstrap_append_query_and_reopen() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"Idea Memory Fixture",
		"idea-memory-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return

	var store := IdeaMemoryStoreType.open(CAMPAIGN_PATH)
	_expect(
		store.is_valid(),
		"Idea memory store is invalid: %s" %
			JSON.stringify(store.validation.to_dict())
	)
	if not store.is_valid():
		return
	_expect(
		int(store.summary().get("total_ideas", -1)) == 0,
		"Idea memory did not bootstrap empty."
	)

	var faction := store.append_idea(
		"faction",
		"The Glass Choir are soft-spoken miners who treat radio silence as worship.",
		["frontier", "miners"],
		"glass choir miners radio silence"
	)
	_expect(bool(faction.get("ok", false)), faction.get("error", ""))
	var duplicate := store.append_idea(
		"faction",
		"The Glass Choir are renamed but same core idea.",
		["frontier"],
		"glass choir miners radio silence"
	)
	_expect(
		bool(duplicate.get("duplicate", false)),
		"Duplicate fingerprint was not detected."
	)
	var joke := store.append_idea(
		"joke",
		"A dockhand keeps calling catastrophic decompression a lifestyle choice.",
		["humor", "dock"]
	)
	_expect(bool(joke.get("ok", false)), joke.get("error", ""))

	var prompt := store.prompt_context(["faction"], ["miners"], 5)
	_expect(
		prompt.contains("Glass Choir") and not prompt.contains("decompression"),
		"Prompt context did not filter by category and tag."
	)

	var reopened := IdeaMemoryStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid()
			and int(reopened.summary().get("total_ideas", 0)) == 2,
		"Idea memory did not persist after reopening."
	)
	_expect(
		reopened.prompt_context(["joke"], [], 5).contains("lifestyle choice"),
		"Reopened idea memory could not retrieve joke idea."
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
