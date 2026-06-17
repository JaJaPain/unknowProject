extends SceneTree

const ManifestStoreType := preload(
	"res://scripts/persistence/CampaignManifestStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://campaign_manifest_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_handcrafted_canon_and_append_only_identity()
	_test_missing_asset_fallback_without_reroll()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Campaign manifest and asset registry tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_handcrafted_canon_and_append_only_identity() -> void:
	var slot_registry := SlotRegistryType.open(TEST_ROOT)
	var created := slot_registry.create_campaign(
		"slot_01",
		"Manifest Fixture",
		"phase-2-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return

	var store := ManifestStoreType.open(CAMPAIGN_PATH)
	_expect(
		store.is_valid(),
		"Initial permanent canon store is invalid: %s" %
			store.validation.summary()
	)
	if not store.is_valid():
		return
	_expect(store.generation == 1, "Initial canon generation is not one.")
	_expect(
		store.manifest.get("entity_ids", []).size() > 150,
		"Handcrafted registries were not captured as initial campaign canon."
	)
	_expect(
		"system.start" in store.manifest.get("entity_ids", [])
			and "system.test" in store.manifest.get("entity_ids", [])
			and "npc.kaelen" in store.manifest.get("entity_ids", []),
		"Required handcrafted identities are absent from campaign canon."
	)
	_expect(
		store.assets.get("assets", []).size() > 100,
		"Curated assets were not registered in the campaign asset catalog."
	)

	var generated_entity := {
		"entity_id": "npc.generated.distress_pilot_001",
		"entity_type": "npc",
		"origin": "generated",
		"source_registry": "campaign_generator",
		"definition_hash": "sha256:distress-pilot-001",
	}
	var appended := store.register_entity(generated_entity)
	_expect(bool(appended.get("ok", false)), appended.get("error", ""))
	_expect(store.generation == 2, "Generated identity did not append canon.")
	var unchanged := store.register_entity(generated_entity)
	_expect(
		bool(unchanged.get("ok", false))
			and bool(unchanged.get("unchanged", false))
			and store.generation == 2,
		"Idempotent identity registration rewrote permanent canon."
	)
	var conflicting := generated_entity.duplicate(true)
	conflicting["definition_hash"] = "sha256:changed-definition"
	_expect(
		not bool(store.register_entity(conflicting).get("ok", false)),
		"Existing permanent identity accepted conflicting canon."
	)

	var fact := {
		"fact_id": "fact.generated.distress_pilot_met",
		"subject_ids": ["npc.generated.distress_pilot_001"],
		"value": true,
	}
	_expect(
		bool(store.register_canon_fact(fact).get("ok", false)),
		"Generated canon fact could not be appended."
	)
	var generation_after_append := store.generation
	var entity_count: int = store.manifest.get("entity_ids", []).size()
	var old_checkpoint := slot_registry.load_initial_bundle("slot_01")
	_expect(
		bool(old_checkpoint.get("ok", false)),
		"Initial checkpoint bundle could not be read after canon advanced."
	)
	var reopened := ManifestStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid()
			and reopened.generation == generation_after_append
			and reopened.manifest.get("entity_ids", []).size() == entity_count
			and "npc.generated.distress_pilot_001"
				in reopened.manifest.get("entity_ids", []),
		"Reading an older checkpoint changed permanent campaign canon."
	)


func _test_missing_asset_fallback_without_reroll() -> void:
	var store := ManifestStoreType.open(CAMPAIGN_PATH)
	if not store.is_valid():
		_expect(false, "Canon store unavailable for asset tests.")
		return
	var fallback_asset := _generated_asset(
		"asset.generated.distress_pilot_portrait",
		"user://missing/distress_pilot.png",
		"res://assets/QuestGivers.png",
		"seed-distress-pilot"
	)
	var missing_asset := _generated_asset(
		"asset.generated.distress_ship_model",
		"user://missing/distress_ship.glb",
		"user://missing/distress_ship_fallback.glb",
		"seed-distress-ship"
	)
	_expect(
		bool(store.register_asset(fallback_asset).get("ok", false)),
		"Generated asset with fallback could not be registered."
	)
	_expect(
		bool(store.register_asset(missing_asset).get("ok", false)),
		"Generated missing asset could not be registered."
	)
	var audit := store.audit_assets()
	_expect(bool(audit.get("ok", false)), audit.get("error", ""))
	var fallback_report := _find_record(
		audit.get("assets", []),
		"asset_id",
		"asset.generated.distress_pilot_portrait"
	)
	var rebuild_report := _find_record(
		audit.get("assets", []),
		"asset_id",
		"asset.generated.distress_ship_model"
	)
	_expect(
		fallback_report.get("validation_status") == "fallback",
		"Missing source did not select its approved fallback."
	)
	_expect(
		rebuild_report.get("validation_status") == "rebuild_required",
		"Missing source and fallback did not request deterministic rebuild."
	)

	var generation_after_audit := store.generation
	var reopened := ManifestStoreType.open(CAMPAIGN_PATH)
	var persisted_fallback := _find_record(
		reopened.assets.get("assets", []),
		"asset_id",
		"asset.generated.distress_pilot_portrait"
	)
	var persisted_missing := _find_record(
		reopened.assets.get("assets", []),
		"asset_id",
		"asset.generated.distress_ship_model"
	)
	_expect(
		reopened.is_valid() and reopened.generation == generation_after_audit,
		"Audited asset registry did not reopen at the committed generation."
	)
	_expect(
		persisted_fallback.get("generation_seed") == "seed-distress-pilot"
			and persisted_fallback.get("provenance_hash")
				== fallback_asset["provenance_hash"]
			and persisted_missing.get("generation_seed") == "seed-distress-ship"
			and persisted_missing.get("provenance_hash")
				== missing_asset["provenance_hash"],
		"Missing asset recovery rerolled permanent seed or provenance."
	)


func _generated_asset(
	asset_id: String,
	source_path: String,
	fallback_path: String,
	seed: String
) -> Dictionary:
	return {
		"asset_id": asset_id,
		"owner_entity_id": "npc.generated.distress_pilot_001",
		"generator_type": "test_generator",
		"generator_version": "1",
		"generation_seed": seed,
		"provenance_hash": "sha256:%s" % seed.sha256_text(),
		"source_path": source_path,
		"fallback_path": fallback_path,
		"validation_status": "missing",
		"rebuild_instruction": "Regenerate from the preserved seed and prompt.",
	}


func _find_record(records: Array, key: String, value: String) -> Dictionary:
	for raw in records:
		if raw is Dictionary and str(raw.get(key, "")) == value:
			return raw
	return {}


func _initial_state() -> Dictionary:
	return {
		"current_system_id": "system.start",
		"player": {
			"credits": 50,
			"health": 100.0,
			"shield": 0.0,
			"position": [0.0, 0.0, 0.0],
			"rotation": [0.0, 0.0, 0.0],
		},
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
