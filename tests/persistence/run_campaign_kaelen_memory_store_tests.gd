extends SceneTree

const ChronicleStoreType := preload(
	"res://scripts/persistence/CampaignChronicleStore.gd"
)
const MemoryStoreType := preload(
	"res://scripts/persistence/CampaignKaelenMemoryStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://campaign_kaelen_memory_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_death_memory_and_rollback_classification()
	_cleanup()
	if _failures.is_empty():
		print("[PASS] Campaign Kaelen memory tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_death_memory_and_rollback_classification() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"Kaelen Fixture",
		"phase-2-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return
	var checkpoint: Dictionary = created["checkpoint"]
	var chronicle := ChronicleStoreType.open(CAMPAIGN_PATH)
	var memory_store := MemoryStoreType.open(CAMPAIGN_PATH)
	_expect(chronicle.is_valid(), "Chronicle fixture is invalid.")
	_expect(
		memory_store.is_valid(),
		"Kaelen store is invalid: %s" %
			JSON.stringify(memory_store.validation.to_dict())
	)
	if not chronicle.is_valid() or not memory_store.is_valid():
		return

	var observation_event := chronicle.append_event(
		"mission_completed",
		[chronicle.campaign["id"]],
		{"title": "Future Contract"},
		checkpoint["id"]
	)
	var observation := memory_store.append_memory(
		"observation",
		"Shiny completed a contract.",
		[],
		chronicle.current_timeline_id(),
		checkpoint["id"],
		observation_event.get("event", {}).get("sequence", -1),
		"",
		{
			"line_fingerprint": "Kaelen line.".sha256_text(),
			"event_kind": "turn_in_clean",
		}
	)
	_expect(bool(observation.get("ok", false)), observation.get("error", ""))
	var observation_memory: Dictionary = observation.get("memory", {}) \
		if observation.get("memory", {}) is Dictionary else {}
	_expect(
		str(observation_memory.get("line_fingerprint", "")) \
			== "Kaelen line.".sha256_text()
			and str(observation_memory.get("event_kind", "")) == "turn_in_clean",
		"Kaelen memory did not retain delivered line metadata."
	)
	var reopened_before_rollback := MemoryStoreType.open(CAMPAIGN_PATH)
	_expect(
		_contains_line_memory(
			reopened_before_rollback.current_memories(),
			"Kaelen line.".sha256_text(),
			"turn_in_clean"
		),
		"Kaelen delivered-line metadata did not persist through ordinary reopen."
	)

	var invalid_death := memory_store.append_memory(
		"death",
		"Unverified destruction.",
		[],
		chronicle.current_timeline_id(),
		checkpoint["id"],
		chronicle.current_head_sequence()
	)
	_expect(
		not bool(invalid_death.get("ok", false)),
		"An unverified death memory was accepted."
	)

	var death_event := chronicle.append_event(
		"player_death",
		[chronicle.campaign["id"]],
		{"death_category": "combat"},
		checkpoint["id"]
	)
	var death := memory_store.append_memory(
		"death",
		"Shiny's ship was destroyed in combat.",
		[],
		chronicle.current_timeline_id(),
		checkpoint["id"],
		death_event.get("event", {}).get("sequence", -1),
		"combat"
	)
	_expect(bool(death.get("ok", false)), death.get("error", ""))
	_expect(
		memory_store.current_memories().size() == 3,
		"Current memory view did not include the retained future."
	)

	var boundary := chronicle.event_sequence(
		checkpoint["chronicle_head_event_id"]
	)
	var classified := memory_store.classify_rollback(
		checkpoint["timeline_id"],
		checkpoint["id"],
		boundary
	)
	_expect(
		bool(classified.get("ok", false))
			and int(classified.get("archived", 0)) == 2
			and memory_store.reversal_count() == 1,
		"Rollback did not classify the discarded future exactly once."
	)
	var current := memory_store.current_memories()
	var discarded := memory_store.diagnostic_discarded_memories()
	_expect(
		current.size() == 1
			and current[0].get("category", "") == "observation",
		"Discarded memories leaked into the ordinary current-memory view."
	)
	_expect(
		discarded.size() == 2
			and discarded[-1].get("death_category", "") == "combat",
		"Verified death memory was not preserved as discarded history."
	)
	var classified_again := memory_store.classify_rollback(
		checkpoint["timeline_id"],
		checkpoint["id"],
		boundary
	)
	_expect(
		bool(classified_again.get("ok", false))
			and not bool(classified_again.get("reversal_counted", true))
			and memory_store.reversal_count() == 1,
		"Repeated rollback classification incremented the reversal counter."
	)
	var reopened := MemoryStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid()
			and reopened.reversal_count() == 1
			and reopened.current_memories().size() == 1,
		"Kaelen rollback classification did not persist."
	)
	_expect(
		_contains_line_memory(
			reopened.current_memories() + reopened.diagnostic_discarded_memories(),
			"Kaelen line.".sha256_text(),
			"turn_in_clean"
		),
		"Kaelen delivered-line metadata did not persist through rollback reopen."
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


func _contains_line_memory(
	memories: Array,
	line_fingerprint: String,
	event_kind: String
) -> bool:
	for memory in memories:
		if not memory is Dictionary:
			continue
		if str(memory.get("line_fingerprint", "")) == line_fingerprint \
				and str(memory.get("event_kind", "")) == event_kind:
			return true
	return false


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
