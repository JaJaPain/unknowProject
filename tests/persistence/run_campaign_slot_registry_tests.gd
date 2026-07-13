extends SceneTree

const RegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://campaign_slot_registry_fixture"
const ORPHAN_ROOT := "user://campaign_slot_orphan_fixture"

var _failures: Array[String] = []
var _system_registry: SystemRegistry


func _initialize() -> void:
	_cleanup()
	_system_registry = SystemRegistryType.load_default()
	_expect(_system_registry.is_valid(), "System registry failed to load.")

	_test_three_stable_slots()
	_test_create_reopen_and_initial_checkpoint()
	_test_slot_isolation_and_selection()
	_test_campaign_rename()
	_test_registry_corruption_recovery()
	_test_orphaned_occupied_slot_is_repaired()
	_test_empty_slot_with_stale_directory_is_claimed()
	_test_no_fourth_campaign()
	_test_delete_is_isolated()
	_cleanup()
	_cleanup_orphan()

	if _failures.is_empty():
		print("[PASS] Campaign slot registry tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_three_stable_slots() -> void:
	var registry := RegistryType.open(TEST_ROOT)
	_expect(registry.is_valid(), "Fresh campaign registry is invalid.")
	var slots := registry.enumerate_slots()
	_expect(slots.size() == 3, "Registry did not create exactly three slots.")
	_expect(
		slots[0]["slot_id"] == "slot_01"
			and slots[1]["slot_id"] == "slot_02"
			and slots[2]["slot_id"] == "slot_03",
		"Stable campaign slot IDs are incorrect."
	)


func _test_create_reopen_and_initial_checkpoint() -> void:
	var registry := RegistryType.open(TEST_ROOT)
	var created := registry.create_campaign(
		"slot_01",
		"First Light",
		"phase-2-test",
		_initial_state(50),
		_system_registry
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return
	var campaign: Dictionary = created["campaign"]
	var checkpoint: Dictionary = created["checkpoint"]
	_expect(
		str(campaign.get("campaign_seed", "")).length() == 64,
		"Campaign seed was not created once at full length."
	)
	_expect(
		checkpoint.get("source_reason") == "initial"
			and checkpoint.get("living") == true
			and checkpoint.get("transitional") == false,
		"Initial living safe checkpoint is malformed."
	)
	_expect(
		int(checkpoint.get("state", {}).get("player", {}).get("credits", 0))
			== 50,
		"Initial checkpoint did not preserve supplied startup state."
	)

	var reopened := RegistryType.open(TEST_ROOT)
	_expect(reopened.is_valid(), "Reopened campaign registry is invalid.")
	var loaded := reopened.read_campaign_document("slot_01")
	_expect(bool(loaded.get("ok", false)), loaded.get("error", ""))
	if bool(loaded.get("ok", false)):
		_expect(
			loaded["data"]["id"] == campaign["id"]
				and loaded["data"]["campaign_seed"]
					== campaign["campaign_seed"],
			"Reopening changed campaign identity or seed."
		)
	var bundle := reopened.load_initial_bundle("slot_01")
	_expect(
		bool(bundle.get("ok", false)),
		"Reopened initial campaign bundle did not validate."
	)


func _test_slot_isolation_and_selection() -> void:
	var registry := RegistryType.open(TEST_ROOT)
	var created := registry.create_campaign(
		"slot_02",
		"Second Wind",
		"phase-2-test",
		_initial_state(125),
		_system_registry
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	var first_before := registry.get_slot("slot_01")
	var selected := registry.select_campaign("slot_02")
	_expect(bool(selected.get("ok", false)), selected.get("error", ""))
	_expect(
		registry.selected_slot_id == "slot_02",
		"Campaign selection did not persist in memory."
	)
	_expect(
		registry.get_slot("slot_01")["campaign_id"]
			== first_before["campaign_id"],
		"Creating or selecting slot 2 changed slot 1."
	)
	var reopened := RegistryType.open(TEST_ROOT)
	_expect(
		reopened.is_valid() and reopened.selected_slot_id == "slot_02",
		"Selected campaign did not survive registry reopening."
	)


func _test_no_fourth_campaign() -> void:
	var registry := RegistryType.open(TEST_ROOT)
	var third := registry.create_campaign(
		"slot_03",
		"Third Rail",
		"phase-2-test",
		_initial_state(300),
		_system_registry
	)
	_expect(bool(third.get("ok", false)), third.get("error", ""))
	var fourth := registry.create_first_available_campaign(
		"Impossible Fourth",
		"phase-2-test",
		_initial_state(999),
		_system_registry
	)
	_expect(
		not bool(fourth.get("ok", false)),
		"Registry created a fourth campaign."
	)


func _test_campaign_rename() -> void:
	var registry := RegistryType.open(TEST_ROOT)
	var renamed := registry.rename_campaign(
		"slot_02",
		"  Second Wind Renamed  "
	)
	_expect(bool(renamed.get("ok", false)), renamed.get("error", ""))
	_expect(
		registry.get_slot("slot_02").get("display_name", "")
			== "Second Wind Renamed",
		"Campaign rename did not sanitize and update the slot name."
	)
	var reopened := RegistryType.open(TEST_ROOT)
	_expect(
		reopened.get_slot("slot_02").get("display_name", "")
			== "Second Wind Renamed",
		"Campaign rename did not persist after reopening."
	)
	_expect(
		not bool(reopened.rename_campaign(
			"slot_02",
			"   "
		).get("ok", false)),
		"Campaign rename accepted an empty display name."
	)


func _test_registry_corruption_recovery() -> void:
	var registry := RegistryType.open(TEST_ROOT)
	var selected := registry.select_campaign("slot_02")
	_expect(bool(selected.get("ok", false)), selected.get("error", ""))
	_write_text("%s/slots.json" % TEST_ROOT, "{ damaged")
	var recovered := RegistryType.open(TEST_ROOT)
	_expect(
		recovered.is_valid(),
		"Campaign registry did not recover a damaged slots index."
	)
	_expect(
		recovered.get_slot("slot_01").get("occupied") == true
			and recovered.get_slot("slot_02").get("occupied") == true,
		"Registry recovery lost a previously committed occupied slot."
	)


func _test_orphaned_occupied_slot_is_repaired() -> void:
	_cleanup_orphan()
	_make_directory("%s/slot_01/ships" % ORPHAN_ROOT)
	_write_text("%s/slot_01/ships/orphan.glb" % ORPHAN_ROOT, "not really a ship")
	_write_text(
		"%s/slots.json" % ORPHAN_ROOT,
		JSON.stringify({
			"schema_version": 1,
			"selected_slot_id": "slot_01",
			"slots": [
				{
					"slot_id": "slot_01",
					"occupied": true,
					"campaign_id": "campaign.local.aaaaaaaaaaaaaaaa",
					"display_name": "Orphan",
					"created_at_unix": 1,
					"last_played_at_unix": 1,
					"game_version": "test",
					"checkpoint_summary": {
						"checkpoint_id": "checkpoint.local.aaaaaaaaaaaaaaaa.initial",
						"source_reason": "initial",
						"system_id": "system.start",
						"living": true,
					},
				},
				RegistryType._empty_slot("slot_02"),
				RegistryType._empty_slot("slot_03"),
			],
		}, "\t")
	)
	var repaired := RegistryType.open(ORPHAN_ROOT)
	_expect(repaired.is_valid(), "Orphaned slot repair made registry invalid.")
	_expect(
		not bool(repaired.get_slot("slot_01").get("occupied", true)),
		"Orphaned occupied slot was not cleared."
	)
	_expect(
		repaired.selected_slot_id.is_empty(),
		"Orphaned selected slot was not cleared."
	)
	_expect(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path("%s/slot_01" % ORPHAN_ROOT)
		),
		"Orphaned campaign directory was not removed."
	)
	_cleanup_orphan()


func _test_empty_slot_with_stale_directory_is_claimed() -> void:
	_cleanup_orphan()
	var registry := RegistryType.open(ORPHAN_ROOT)
	_make_directory("%s/slot_01/ships" % ORPHAN_ROOT)
	_write_text("%s/slot_01/ships/stale.glb" % ORPHAN_ROOT, "old generated mesh")
	_write_text("%s/slot_01/narrative_cache.json" % ORPHAN_ROOT, "{}")
	var created := registry.create_campaign(
		"slot_01",
		"Fresh Start",
		"phase-2-test",
		_initial_state(75),
		_system_registry
	)
	_expect(
		bool(created.get("ok", false)),
		"Empty slot with stale files could not create a campaign: %s" %
			created.get("error", "")
	)
	_expect(
		FileAccess.file_exists("%s/slot_01/campaign.json" % ORPHAN_ROOT),
		"Fresh campaign did not write its campaign document."
	)
	_expect(
		not FileAccess.file_exists("%s/slot_01/ships/stale.glb" % ORPHAN_ROOT),
		"Fresh campaign creation kept stale generated files."
	)
	_expect(
		not FileAccess.file_exists(
			"%s/slot_01/narrative_cache.json" % ORPHAN_ROOT
		),
		"Fresh campaign creation kept a stale narrative cache."
	)
	_cleanup_orphan()


func _test_delete_is_isolated() -> void:
	var registry := RegistryType.open(TEST_ROOT)
	var slot_one_id := str(registry.get_slot("slot_01").get("campaign_id", ""))
	var slot_three_id := str(registry.get_slot("slot_03").get("campaign_id", ""))
	var deleted := registry.delete_campaign("slot_02")
	_expect(bool(deleted.get("ok", false)), deleted.get("error", ""))
	_expect(
		not bool(registry.get_slot("slot_02").get("occupied", true)),
		"Deleted campaign slot remained occupied."
	)
	_expect(
		registry.get_slot("slot_01").get("campaign_id") == slot_one_id
			and registry.get_slot("slot_03").get("campaign_id")
				== slot_three_id,
		"Deleting slot 2 changed another campaign."
	)
	_expect(
		FileAccess.file_exists("%s/slot_01/campaign.json" % TEST_ROOT)
			and FileAccess.file_exists(
				"%s/slot_03/campaign.json" % TEST_ROOT
			)
			and not FileAccess.file_exists(
				"%s/slot_02/campaign.json" % TEST_ROOT
			),
		"Campaign deletion crossed slot directory boundaries."
	)
	var reopened := RegistryType.open(TEST_ROOT)
	_expect(
		reopened.is_valid() and reopened.selected_slot_id == "slot_03",
		"Deleting another campaign changed persisted selection. "
			+ "valid=%s selected='%s' validation=%s" % [
				reopened.is_valid(),
				reopened.selected_slot_id,
				reopened.validation.summary(),
			]
	)


func _initial_state(credits: int) -> Dictionary:
	return {
		"current_system_id": "system.start",
		"player": {
			"credits": credits,
			"health": 100.0,
			"shield": 0.0,
			"position": [0.0, 0.0, 0.0],
			"rotation": [0.0, 0.0, 0.0],
		},
		"global": {
			"credits": credits,
			"cargo": 0.0,
			"upgrades": {},
			"reputations": {},
		},
		"quest": {},
		"systems": {},
	}


func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	_remove_directory(absolute)


func _cleanup_orphan() -> void:
	var absolute := ProjectSettings.globalize_path(ORPHAN_ROOT)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_directory(absolute)


func _make_directory(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)


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
