extends SceneTree

const NpcStoreType := preload(
	"res://scripts/persistence/CampaignNpcIdentityStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://campaign_npc_identity_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_npc_identity_bootstrap_upsert_line_memory_and_reopen()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Campaign NPC identity store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_npc_identity_bootstrap_upsert_line_memory_and_reopen() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"NPC Identity Fixture",
		"npc-identity-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return

	var store := NpcStoreType.open(CAMPAIGN_PATH)
	_expect(
		store.is_valid(),
		"NPC identity store is invalid: %s" %
			JSON.stringify(store.validation.to_dict())
	)
	if not store.is_valid():
		return
	_expect(store.all_npcs().is_empty(), "NPC identity store did not bootstrap empty.")

	var upserted: Dictionary = store.ensure_npc_record({
		"source_key": "station.generated.alpha|Mara Venn|Faction contact|faction.generated.glass_choir_00",
		"display_name": "Mara Venn",
		"portrait_id": "portrait.minor_npc_01.hana_quill",
		"voice_profile_id": "voice.hana_quill.v1",
		"faction_id": "faction.generated.glass_choir_00",
		"faction_key": "gen_glass_choir_00",
		"job_role": "Faction contact",
		"home_system_id": "system.generated.alpha",
		"home_station_id": "station.generated.alpha",
		"personality_tags": ["dry", "broker"],
		"humor_style": "deadpan accounting threats",
	})
	_expect(bool(upserted.get("ok", false)), upserted.get("error", ""))
	var npc: Dictionary = upserted.get("npc", {})
	_expect(
		str(npc.get("id", "")).begins_with("npc.gen."),
		"Generated NPC ID did not use npc.gen prefix."
	)
	var duplicate: Dictionary = store.ensure_npc_record({
		"source_key": "station.generated.alpha|Mara Venn|Faction contact|faction.generated.glass_choir_00",
		"display_name": "Mara Venn",
		"portrait_id": "portrait.minor_npc_01.hana_quill",
		"voice_profile_id": "voice.hana_quill.v1",
		"job_role": "Faction contact",
		"home_station_id": "station.generated.alpha",
	})
	_expect(
		not bool(duplicate.get("created", true)),
		"Duplicate NPC source key created a second identity."
	)
	var remembered: Dictionary = store.remember_line(
		str(npc.get("id", "")),
		"Radio silence is not a faith, it is a billing strategy.",
		"faction"
	)
	_expect(bool(remembered.get("ok", false)), remembered.get("error", ""))
	_expect(
		store.prompt_context("system.generated.alpha").contains("Mara Venn"),
		"NPC prompt context did not include the generated contact."
	)

	var reopened := NpcStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid() and reopened.all_npcs().size() == 1,
		"NPC identity did not persist after reopening."
	)
	var reopened_npc: Dictionary = reopened.npc_by_display_name("Mara Venn")
	_expect(
		(reopened_npc.get("line_memory_fingerprints", []) as Array).size() == 1,
		"NPC line memory did not persist after reopening."
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
