extends SceneTree

const ChronicleStoreType := preload(
	"res://scripts/persistence/CampaignChronicleStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://campaign_chronicle_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_append_branch_filter_and_legacy_import()
	_cleanup()
	if _failures.is_empty():
		print("[PASS] Campaign chronicle branch tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_append_branch_filter_and_legacy_import() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"Chronicle Fixture",
		"phase-2-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return
	var initial_checkpoint: Dictionary = created["checkpoint"]
	var store := ChronicleStoreType.open(CAMPAIGN_PATH)
	_expect(
		store.is_valid(),
		"Chronicle store is invalid: %s" %
			JSON.stringify(store.validation.to_dict())
	)
	if not store.is_valid():
		return
	var initial_events := store.current_branch_events()
	_expect(
		bool(initial_events.get("ok", false))
			and initial_events.get("events", []).size() == 1,
		"Initial campaign event was not indexed."
	)
	var first := store.append_event(
		"mission_completed",
		["campaign.local.fixture_subject"],
		{"title": "Future One"},
		initial_checkpoint["id"]
	)
	var second := store.append_event(
		"mission_abandoned",
		["campaign.local.fixture_subject"],
		{"title": "Future Two"},
		initial_checkpoint["id"]
	)
	_expect(bool(first.get("ok", false)), first.get("error", ""))
	_expect(bool(second.get("ok", false)), second.get("error", ""))
	var before_branch := store.current_branch_events()
	_expect(
		before_branch.get("events", []).size() == 3,
		"Appended chronicle events were not visible on the current timeline."
	)
	var original_timeline_id := str(
		store.index.get("current_timeline_id", "")
	)
	var branched := store.branch_from_checkpoint(initial_checkpoint)
	_expect(bool(branched.get("ok", false)), branched.get("error", ""))
	_expect(
		bool(branched.get("branched", false))
			and branched.get("timeline_id", "") != original_timeline_id,
		"Loading an older checkpoint did not create a new timeline."
	)
	var after_branch := store.current_branch_events()
	_expect(
		after_branch.get("events", []).size() == 1
			and after_branch.get("events", [])[0].get(
				"event_type",
				""
			) == "campaign_started",
		"Discarded future events leaked into the new current branch."
	)
	var branch_event := store.append_event(
		"mission_completed",
		["campaign.local.fixture_subject"],
		{"title": "Branch Mission"},
		initial_checkpoint["id"]
	)
	_expect(bool(branch_event.get("ok", false)), branch_event.get("error", ""))
	var branch_history := store.current_branch_events()
	_expect(
		branch_history.get("events", []).size() == 2
			and branch_history.get("events", [])[-1].get(
				"payload",
				{}
			).get("title", "") == "Branch Mission",
		"New branch event did not extend inherited history."
	)
	var segment_count_before_import: int = (
		store.index.get("segments", []) as Array
	).size()
	var imported := store.import_legacy_quest_history(
		"# Quest History Log\n"
		+ "- **Old Contract** (DELIVER_ORE): Completed.\n"
		+ "- **Lost Contract** (KILL_SHIPS): Abandoned.\n",
		initial_checkpoint["id"]
	)
	_expect(
		bool(imported.get("ok", false))
			and int(imported.get("imported", 0)) == 2,
		"Legacy quest history was not imported as structured events."
	)
	var imported_again := store.import_legacy_quest_history(
		"- **Duplicate** (DELIVER_ORE): Completed.",
		initial_checkpoint["id"]
	)
	_expect(
		bool(imported_again.get("already_imported", false))
			and store.index.get("segments", []).size()
				== segment_count_before_import + 2,
		"Legacy quest history import was not idempotent."
	)
	var all_segment_files := _count_json_files(
		"%s/chronicle/segments" % CAMPAIGN_PATH
	)
	_expect(
		all_segment_files >= 6,
		"Discarded timeline segment files were deleted during branching."
	)
	var reopened := ChronicleStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid()
			and reopened.index.get("current_timeline_id", "")
				== branched.get("timeline_id", ""),
		"Timeline branch did not persist after reopening."
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


func _count_json_files(path: String) -> int:
	var directory := DirAccess.open(path)
	if directory == null:
		return 0
	var count := 0
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() and entry.ends_with(".json"):
			count += 1
		entry = directory.get_next()
	directory.list_dir_end()
	return count


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
