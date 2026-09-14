extends SceneTree

const FactionStoreType := preload(
	"res://scripts/persistence/CampaignGeneratedFactionStore.gd"
)
var SlotRegistryType: GDScript
var SystemRegistryType: GDScript

const TEST_ROOT := "res://.tmp_godot_user/campaign_generated_faction_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	SlotRegistryType = load("res://scripts/persistence/CampaignSlotRegistry.gd")
	SystemRegistryType = load("res://scripts/registry/SystemRegistry.gd")
	_cleanup()
	_test_bootstrap_generate_reveal_and_reopen()
	_test_per_system_rosters_and_desires()
	_cleanup()
	_test_old_faction_records_normalize_on_load()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Campaign generated faction store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_bootstrap_generate_reveal_and_reopen() -> void:
	var slots = SlotRegistryType.open(TEST_ROOT)
	var created: Dictionary = slots.create_campaign(
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
	var first_faction: Dictionary = store.all_factions()[0]
	_expect(
		str(first_faction.get("badge_id", "")).begins_with("badge_sheet_"),
		"Generated faction did not use a badge ID from badge metadata."
	)
	var badge_source: Dictionary = first_faction.get("badge_source", {})
	_expect(
		str(badge_source.get("sheet_file", "")).begins_with("BadgeSheet"),
		"Generated faction did not keep badge sheet source metadata."
	)
	var voice_style: Dictionary = first_faction.get("voice_style", {})
	_expect(
		not str(voice_style.get("delivery", "")).is_empty()
			and not str(voice_style.get("profile_hint", "")).is_empty(),
		"Generated faction did not include voice style metadata."
	)
	var mission_preferences: Dictionary = first_faction.get("mission_preferences", {})
	_expect(
		(mission_preferences.get("preferred_types", []) as Array).size() > 0,
		"Generated faction did not include mission preferences."
	)
	_expect(
		store.prompt_context().contains("Generated frontier factions")
			and store.prompt_context().contains("voice:")
			and store.prompt_context().contains("missions:"),
		"Generated faction prompt context did not include voice and mission identity."
	)
	var revealed: Dictionary = store.reveal_next_for_system(
		"system.generated.alpha",
		2
	)
	_expect(bool(revealed.get("ok", false)), revealed.get("error", ""))
	_expect(
		store.revealed_faction_ids().size() == 2,
		"Reveal did not persist two faction IDs."
	)
	_expect(
		store.revealed_factions().size() == 2,
		"Reveal did not return two faction records."
	)
	_expect(
		store.factions_by_ids(revealed.get("revealed", [])).size() == 2,
		"Faction lookup by revealed IDs failed."
	)
	_expect(
		store.prompt_context(true).contains(str(store.revealed_factions()[0].get("display_name", ""))),
		"Revealed-only prompt context did not include the first revealed faction."
	)

	var reopened := FactionStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid() and reopened.all_factions().size() == 6,
		"Generated faction records did not persist after reopening."
	)
	_expect(
		reopened.revealed_faction_ids().size() == 2,
		"Revealed faction IDs did not persist after reopening."
	)


func _test_per_system_rosters_and_desires() -> void:
	var store := FactionStoreType.open(CAMPAIGN_PATH)
	var seen := {}
	for index in range(12):
		var system_id := "system.generated.fixture_%d" % index
		var result := store.reveal_next_for_system(system_id, 3)
		_expect(bool(result.get("ok", false)), "Per-system roster must persist beyond the former six-faction pool")
		var ids: Array = result.get("revealed", [])
		_expect(ids.size() == 3, "Each system must receive three local factions")
		for id in ids:
			_expect(not seen.has(id), "New systems must not reuse another system's factions")
			seen[id] = true
		var before := store.all_factions().size()
		_expect(store.reveal_next_for_system(system_id, 4).get("revealed", []) == ids, "Retry/revisit must retain original roster even if requested count changes")
		_expect(store.all_factions().size() == before, "Revisit must not generate extra records")
		var records := store.factions_by_ids(ids)
		var config_type = load("res://scripts/generation/SystemConfig.gd")
		var config = config_type.from_seed("Fixture %d" % index, system_id, index + 10, records)
		for key in config.faction_weights:
			_expect(str(config.canonical_faction_id(key)).begins_with("faction.generated."), "Generated configuration must not inject tutorial factions")
		_expect(not config.story_pack.get("mission_causes", {}).is_empty(), "Local desires must reach actual mission causes")
		for cause in config.story_pack["mission_causes"].values():
			_expect(cause.get("cause_faction_id", "") in ids and not str(cause.get("desire_id", "")).is_empty(), "Mission cause must name a local faction's actual desire")
		var restored = config_type.from_dict(JSON.parse_string(JSON.stringify(config.to_dict())))
		_expect(restored.faction_identities == JSON.parse_string(JSON.stringify(config.faction_identities)), "Faction desires and relations must survive config save/load")
		var board = load("res://scripts/domain/PublicBoardOfferBuilder.gd")
		board.story_config_override_for_tests = config
		var intent: String = config.story_pack["mission_causes"].keys()[0]
		_expect(board._story_cause_metadata(intent).get("desire_id", "") == config.story_pack["mission_causes"][intent]["desire_id"], "Real board builder must use local desire instead of unrelated campaign boilerplate")
		board.story_config_override_for_tests = null
		var metadata_type = load("res://scripts/domain/NarrativeMetadata.gd")
		var cause: Dictionary = config.story_pack["mission_causes"][intent]
		var metadata: Dictionary = metadata_type.from_source({"narrative_metadata": cause})
		_expect(metadata["desire_id"] == cause["desire_id"] and metadata["cause_faction_id"] == cause["cause_faction_id"], "Mission normalization must preserve desire ownership")
	var reopened := FactionStoreType.open(CAMPAIGN_PATH)
	_expect(reopened.is_valid() and reopened.reveal_next_for_system("system.generated.fixture_0", 3)["created"] == 0, "Persisted roster must survive reopening")
	var broken := reopened.data.duplicate(true)
	for faction in broken["factions"]:
		if faction.has("home_system_id"):
			faction["relationships"][0]["faction_id"] = "faction.zenith"
			break
	_expect(not FactionStoreType._validate_data(broken, str(broken["campaign_id"])).is_valid(), "Persistence must reject foreign relationship targets")
	var first := FactionStoreType.generate_system_factions("seed.a", "system.x", 3)
	_expect(first == FactionStoreType.generate_system_factions("seed.a", "system.x", 3), "Generation must be deterministic")
	_expect(first != FactionStoreType.generate_system_factions("seed.b", "system.x", 3), "Campaign seed must change identities and desires")
	# Superseded 2026-09-11: this used to require EVERY faction to have a negative
	# relationship, which is the forced-hostility pattern the campaign-uniqueness
	# plan removes. Cooperation, dependency and indifference are now legitimate.
	# What the system still owes us is ONE adversarial pair to hang a story on,
	# plus a stated reason behind every opinion rather than a bare number.
	# Superseded 2026-09-12: the forced adversarial pair is gone. A system may be
	# entirely non-hostile; its work comes from obstacles and unmet needs, not
	# from mandatory enemies. What every opinion still owes us is a stated reason
	# and a recorded kind rather than a bare standing number.
	for faction in first:
		_expect(faction["relationships"].size() == 2, "Each faction needs opinions about both local peers")
		_expect(not str(faction["desire"].get("obstacle", "")).strip_edges().is_empty(), "Each faction needs an obstacle so work exists without enemies")
		for relation in faction["relationships"]:
			_expect(not str(relation.get("reason", "")).strip_edges().is_empty(), "Every opinion must cite a concrete local reason")
			_expect(not str(relation.get("kind", "")).strip_edges().is_empty(), "Every opinion must record what kind of relationship it is")


func _test_old_faction_records_normalize_on_load() -> void:
	var slots = SlotRegistryType.open(TEST_ROOT)
	var created: Dictionary = slots.create_campaign(
		"slot_01",
		"Old Faction Fixture",
		"old-generated-faction-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return

	var store := FactionStoreType.open(CAMPAIGN_PATH)
	_expect(store.is_valid(), "Generated faction store did not bootstrap before old fixture write.")
	var old_record := {
		"schema_version": 1,
		"document_type": "generated_factions",
		"campaign_id": str(store.campaign.get("id", "")),
		"campaign_seed": "old-generated-faction-test",
		"source": "legacy_fixture",
		"factions": [
			{
				"id": "faction.generated.old_compact_00",
				"legacy_id": "old_compact_00",
				"display_name": "Old Compact",
				"abbreviation": "OC",
				"classification": "generated",
				"descriptor": "Salvage Compact",
				"ideology": "contracts above blood",
				"business_model": "salvage rights",
				"taboo": "free repairs",
				"humor_style": "dry gallows wit",
				"badge_id": "badge.generated.01",
				"ship_style": {"texture": "metal.png", "emblem": "none"},
				"ui_color": [0.2, 0.4, 0.7, 1.0],
			},
		],
		"revealed_faction_ids": ["faction.generated.old_compact_00"],
		"reveal_history": [],
	}
	_write_generated_factions_fixture(old_record)

	var reopened := FactionStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid(),
		"Old generated faction record did not normalize: %s" %
			JSON.stringify(reopened.validation.to_dict())
	)
	if not reopened.is_valid() or reopened.all_factions().is_empty():
		return
	var normalized: Dictionary = reopened.all_factions()[0]
	_expect(
		str(normalized.get("badge_id", "")).begins_with("badge_sheet_"),
		"Old generated faction did not upgrade to real badge metadata."
	)
	var badge_source: Dictionary = normalized.get("badge_source", {})
	_expect(
		str(badge_source.get("sheet_file", "")).begins_with("BadgeSheet"),
		"Old generated faction did not gain badge source metadata."
	)
	var voice_style: Dictionary = normalized.get("voice_style", {})
	_expect(
		not str(voice_style.get("profile_hint", "")).is_empty()
			and not str(voice_style.get("delivery", "")).is_empty(),
		"Old generated faction did not gain voice style metadata."
	)
	var mission_preferences: Dictionary = normalized.get("mission_preferences", {})
	_expect(
		(mission_preferences.get("preferred_types", []) as Array).size() > 0,
		"Old generated faction did not gain mission preferences."
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


func _write_generated_factions_fixture(data: Dictionary) -> void:
	var file := FileAccess.open("%s/generated_factions.json" % CAMPAIGN_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write old generated faction fixture.")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


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
