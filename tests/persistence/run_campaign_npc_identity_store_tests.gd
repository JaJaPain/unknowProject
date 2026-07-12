extends SceneTree

const NpcStoreType := preload(
	"res://scripts/persistence/CampaignNpcIdentityStore.gd"
)
const CharacterDirectorType := preload("res://scripts/story/CharacterDirector.gd")
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
	_test_legacy_v1_identity_migrates_to_v2_persona_voice()
	_cleanup()
	_test_recent_trait_combinations_avoid_reuse()
	_cleanup()
	_test_five_station_npcs_have_distinct_humor_and_contradiction()
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
	var campaign: Dictionary = created.get("campaign", {}) \
		if created.get("campaign", {}) is Dictionary else {}

	var store := NpcStoreType.open(CAMPAIGN_PATH)
	_expect(
		store.is_valid(),
		"NPC identity store is invalid: %s" %
			JSON.stringify(store.validation.to_dict())
	)
	if not store.is_valid():
		return
	_expect(
		int(store.data.get("schema_version", 0)) == 2,
		"NPC identity store did not bootstrap with schema v2."
	)
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
	_assert_v2_character_card(npc, "new NPC")
	var expected_card: Dictionary = CharacterDirectorType.generate_card(
		{
			"id": str(npc.get("id", "")),
			"job_role": "Faction contact",
		},
		str(campaign.get("campaign_seed", ""))
	).get("card", {})
	_expect(
		npc.get("persona", {}) == expected_card.get("persona", {}),
		"NPC identity store did not use deterministic CharacterDirector persona."
	)
	_expect(
		not str(npc.get("trait_combination_key", "")).strip_edges().is_empty()
			and (store.data.get("recent_trait_combinations", []) as Array)
				.has(str(npc.get("trait_combination_key", ""))),
		"NPC identity store did not persist the generated trait combination key."
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
	_assert_v2_character_card(reopened_npc, "reopened NPC")


func _test_legacy_v1_identity_migrates_to_v2_persona_voice() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"NPC Identity Legacy Fixture",
		"npc-identity-legacy-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return
	var campaign: Dictionary = created.get("campaign", {}) \
		if created.get("campaign", {}) is Dictionary else {}
	var legacy_doc := {
		"schema_version": 1,
		"document_type": "campaign_npc_identities",
		"campaign_id": str(campaign.get("id", "")),
		"npcs": [{
			"id": "npc.gen.legacy.mara",
			"source_key": "station.generated.alpha|Mara Venn|Dock controller",
			"display_name": "Mara Venn",
			"portrait_id": "portrait.minor_npc_01.hana_quill",
			"voice_profile_id": "voice.hana_quill.v1",
			"faction_id": "faction.generated.glass_choir_00",
			"faction_key": "gen_glass_choir_00",
			"job_role": "Dock controller",
			"home_system_id": "system.generated.alpha",
			"home_station_id": "station.generated.alpha",
			"personality_tags": ["dry", "rules-first"],
			"humor_style": "deadpan bureaucratic understatement",
			"relationship_state": "neutral",
			"memory_summary": "She remembers a failed relay inspection.",
			"line_memory_fingerprints": [],
			"lifecycle": {
				"available": true,
				"relocated": false,
				"captured": false,
				"dead": false,
				"protected": false,
			},
			"created_at_unix": 1,
			"updated_at_unix": 1,
		}],
	}
	_write_json("%s/npc_identities.json" % CAMPAIGN_PATH, legacy_doc)
	var migrated := NpcStoreType.open(CAMPAIGN_PATH)
	_expect(
		migrated.is_valid(),
		"Legacy NPC identity migration failed: %s" %
			JSON.stringify(migrated.validation.to_dict())
	)
	_expect(
		int(migrated.data.get("schema_version", 0)) == 2,
		"Legacy NPC identity document did not migrate to schema v2."
	)
	var npc: Dictionary = migrated.npc_by_display_name("Mara Venn")
	_assert_v2_character_card(npc, "migrated NPC")
	_expect(
		str(npc.get("memory_summary", "")) == "She remembers a failed relay inspection.",
		"Legacy memory summary was not preserved during v2 migration."
	)
	_expect(
		(migrated.data.get("recent_trait_combinations", []) as Array)
			.has(str(npc.get("trait_combination_key", ""))),
		"Legacy migration did not backfill recent trait combination memory."
	)


func _test_recent_trait_combinations_avoid_reuse() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"NPC Identity Recent Trait Fixture",
		"npc-identity-recent-trait-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return
	var campaign: Dictionary = created.get("campaign", {}) \
		if created.get("campaign", {}) is Dictionary else {}
	var explicit_source := {
		"id": "npc.gen.fixture.blocked_combo",
		"source_key": "station.generated.alpha|Blocked Combo|Station broker",
		"display_name": "Blocked Combo",
		"portrait_id": "portrait.minor_npc_01.hana_quill",
		"voice_profile_id": "voice.hana_quill.v1",
		"job_role": "Station broker",
		"home_system_id": "system.generated.alpha",
		"home_station_id": "station.generated.alpha",
	}
	var initial_card: Dictionary = CharacterDirectorType.generate_card(
		explicit_source,
		str(campaign.get("campaign_seed", ""))
	).get("card", {})
	var blocked_key := str(initial_card.get("trait_combination_key", ""))
	_expect(
		not blocked_key.is_empty(),
		"Could not compute initial trait combination key for recent-memory test."
	)
	var store := NpcStoreType.open(CAMPAIGN_PATH)
	_expect(store.is_valid(), "NPC identity store was invalid for recent-memory test.")
	if not store.is_valid():
		return
	store.data["recent_trait_combinations"] = [blocked_key]
	var upserted: Dictionary = store.ensure_npc_record(explicit_source)
	_expect(bool(upserted.get("ok", false)), upserted.get("error", ""))
	var npc: Dictionary = upserted.get("npc", {})
	var chosen_key := str(npc.get("trait_combination_key", ""))
	_expect(
		not chosen_key.is_empty() and chosen_key != blocked_key,
		"NPC identity store reused a recent trait combination."
	)
	_expect(
		(store.data.get("recent_trait_combinations", []) as Array).has(blocked_key)
			and (store.data.get("recent_trait_combinations", []) as Array).has(chosen_key),
		"NPC identity store did not retain recent and newly chosen trait keys."
	)


func _test_five_station_npcs_have_distinct_humor_and_contradiction() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"NPC Identity Station Variety Fixture",
		"npc-identity-station-variety-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return
	var store := NpcStoreType.open(CAMPAIGN_PATH)
	_expect(store.is_valid(), "NPC identity store was invalid for station variety test.")
	if not store.is_valid():
		return
	var humor_seen := {}
	var contradiction_seen := {}
	for index in range(5):
		var upserted: Dictionary = store.ensure_npc_record({
			"id": "npc.gen.fixture.station_%02d" % index,
			"source_key": "station.generated.alpha|Variety %02d|Station local" % index,
			"display_name": "Variety %02d" % index,
			"portrait_id": "portrait.minor_npc_01.hana_quill",
			"voice_profile_id": "voice.hana_quill.v1",
			"job_role": "Station local",
			"home_system_id": "system.generated.alpha",
			"home_station_id": "station.generated.alpha",
		})
		_expect(bool(upserted.get("ok", false)), upserted.get("error", ""))
		var npc: Dictionary = upserted.get("npc", {})
		var persona: Dictionary = npc.get("persona", {}) \
			if npc.get("persona", {}) is Dictionary else {}
		var humor := str(persona.get("humor_mechanism", "")).strip_edges()
		var contradiction := str(persona.get("contradiction", "")).strip_edges()
		_expect(
			not humor.is_empty() and not humor_seen.has(humor),
			"Five-NPC station variety repeated humor mechanism: %s" % humor
		)
		_expect(
			not contradiction.is_empty() and not contradiction_seen.has(contradiction),
			"Five-NPC station variety repeated contradiction: %s" % contradiction
		)
		humor_seen[humor] = true
		contradiction_seen[contradiction] = true


func _assert_v2_character_card(npc: Dictionary, label: String) -> void:
	var persona: Dictionary = npc.get("persona", {}) \
		if npc.get("persona", {}) is Dictionary else {}
	var voice_rules: Dictionary = npc.get("voice_rules", {}) \
		if npc.get("voice_rules", {}) is Dictionary else {}
	for field in [
		"core_drive",
		"current_want",
		"fear",
		"contradiction",
		"social_strategy",
		"pressure_tell",
		"kindness_tell",
		"verbal_habit",
		"humor_mechanism",
		"taboo",
	]:
		_expect(
			not str(persona.get(field, "")).strip_edges().is_empty(),
			"%s missing persona.%s." % [label, field]
		)
	_expect(
		not str(voice_rules.get("sentence_shape", "")).strip_edges().is_empty(),
		"%s missing voice sentence shape." % label
	)
	_expect(
		not str(voice_rules.get("address_rule", "")).strip_edges().is_empty(),
		"%s missing voice address rule." % label
	)
	_expect(
		voice_rules.get("favored_vocabulary", []) is Array
			and not (voice_rules.get("favored_vocabulary", []) as Array).is_empty(),
		"%s missing favored vocabulary." % label
	)
	_expect(
		voice_rules.get("banned_tics", []) is Array
			and (voice_rules.get("banned_tics", []) as Array).has("Shiny"),
		"%s missing protected banned tics." % label
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


func _write_json(path: String, value: Dictionary) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write fixture JSON: %s" % absolute)
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


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
