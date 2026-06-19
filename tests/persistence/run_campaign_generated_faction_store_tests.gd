extends SceneTree

const FactionStoreType := preload(
	"res://scripts/persistence/CampaignGeneratedFactionStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://campaign_generated_faction_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_bootstrap_generate_reveal_and_reopen()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Campaign generated faction store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_bootstrap_generate_reveal_and_reopen() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"Faction Fixture",
		"generated-faction-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return

	var store := FactionStoreType.open(CAMPAIGN_PATH)
	_expect(
		store.is_valid(),
		"Generated faction store is invalid: %s" %
			JSON.stringify(store.validation.to_dict())
	)
	_expect(store.all_factions().is_empty(), "Default store should not reveal factions upfront.")
	var batch := store.ensure_frontier_batch("generated-faction-test", 4)
	_expect(bool(batch.get("ok", false)), batch.get("error", ""))
	_expect(store.all_factions().size() == 4, "Generated faction batch size was wrong.")
	_expect(
		store.prompt_context().contains("Generated frontier factions"),
		"Generated faction prompt context was empty."
	)
	var revealed := store.reveal_next_for_system("system.generated.alpha", 2)
	_expect(bool(revealed.get("ok", false)), revealed.get("error", ""))
	_expect(
		store.revealed_faction_ids().size() == 2,
		"Reveal did not persist two faction IDs."
	)
	_expect(
		store.prompt_context(true).contains(str(store.all_factions()[0].get("display_name", ""))),
		"Revealed-only prompt context did not include the first revealed faction."
	)

	var reopened := FactionStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid() and reopened.all_factions().size() == 4,
		"Generated faction records did not persist after reopening."
	)
	_expect(
		reopened.revealed_faction_ids().size() == 2,
		"Revealed faction IDs did not persist after reopening."
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
