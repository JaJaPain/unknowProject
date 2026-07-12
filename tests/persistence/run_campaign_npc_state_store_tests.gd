extends SceneTree

const NpcStateStoreType := preload(
	"res://scripts/persistence/CampaignNpcStateStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const SystemRegistryType := preload(
	"res://scripts/registry/SystemRegistry.gd"
)

const TEST_ROOT := "user://campaign_npc_state_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"
const NPC_ID := "npc.gen.fixture.mara"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_bootstrap_update_and_reopen_npc_state()
	_cleanup()
	_test_structured_event_memory_projection()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Campaign NPC state store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_bootstrap_update_and_reopen_npc_state() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"NPC State Fixture",
		"npc-state-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return

	var store := NpcStateStoreType.open(CAMPAIGN_PATH)
	_expect(
		store.is_valid(),
		"NPC state store is invalid: %s" %
			JSON.stringify(store.validation.to_dict())
	)
	if not store.is_valid():
		return
	_expect(
		int(store.data.get("schema_version", 0)) == 1,
		"NPC state store did not bootstrap schema v1."
	)
	_expect(
		(store.data.get("npc_states", {}) as Dictionary).is_empty(),
		"NPC state store did not bootstrap empty."
	)

	var ensured: Dictionary = store.ensure_state(NPC_ID)
	_expect(bool(ensured.get("ok", false)), ensured.get("error", ""))
	var initial_state: Dictionary = ensured.get("state", {})
	_expect(
		int(initial_state.get("state_revision", -1)) == 0,
		"Fresh NPC state should begin at revision 0."
	)
	_expect(
		not initial_state.has("persona") and not initial_state.has("voice_rules"),
		"Rewindable NPC state must not duplicate permanent identity/persona/voice."
	)

	var relationship: Dictionary = store.update_relationship(
		NPC_ID,
		{"trust": 2, "warmth": 1, "debt": -1},
		"helpful"
	)
	_expect(bool(relationship.get("ok", false)), relationship.get("error", ""))
	var relationship_state: Dictionary = relationship.get("state", {})
	var scores: Dictionary = relationship_state.get("relationship", {})
	_expect(
		int(scores.get("trust", 0)) == 2
			and int(scores.get("warmth", 0)) == 1
			and int(scores.get("debt", 0)) == -1
			and str(scores.get("last_player_stance", "")) == "helpful",
		"Relationship update did not persist bounded scores and stance."
	)

	var stake: Dictionary = store.set_current_stake(
		NPC_ID,
		{
			"thread_id": "thread.convoy_shortage",
			"why_it_matters_to_them": "A failed relay puts dock crews on manual vectors.",
			"urgency": 7,
		}
	)
	_expect(bool(stake.get("ok", false)), stake.get("error", ""))
	var current_stake: Dictionary = stake.get("state", {}).get("current_stake", {})
	_expect(
		str(current_stake.get("thread_id", "")) == "thread.convoy_shortage"
			and int(current_stake.get("urgency", -1)) == 5,
		"Current stake did not persist with clamped urgency."
	)

	var memory: Dictionary = store.record_memory_projection(
		NPC_ID,
		["event.local.fixture.first", "event.local.fixture.second"],
		"Mara remembers the relay inspection.",
		"Manual vectors are where pride goes to get audited."
	)
	_expect(bool(memory.get("ok", false)), memory.get("error", ""))
	var memory_state: Dictionary = memory.get("state", {})
	_expect(
		(memory_state.get("memory_event_ids", []) as Array).size() == 2
			and str(memory_state.get("memory_summary", "")) == "Mara remembers the relay inspection."
			and (memory_state.get("line_memory_fingerprints", []) as Array).size() == 1,
		"Memory projection did not store event refs, summary, and line fingerprint."
	)
	_expect(
		int(memory_state.get("state_revision", 0)) == 3,
		"NPC state revision did not advance once per mutation."
	)
	var captured: Dictionary = store.capture_state_for_checkpoint()
	var post_checkpoint: Dictionary = store.update_relationship(
		NPC_ID,
		{"trust": 3, "warmth": 2},
		"post_checkpoint_help"
	)
	_expect(bool(post_checkpoint.get("ok", false)), post_checkpoint.get("error", ""))
	_expect(
		store.restore_state_from_checkpoint(captured),
		"NPC state store rejected its captured checkpoint state."
	)
	var restored_state: Dictionary = store.state_for(NPC_ID)
	var restored_relationship: Dictionary = restored_state.get("relationship", {})
	_expect(
		int(restored_relationship.get("trust", 0)) == 2
			and int(restored_relationship.get("warmth", 0)) == 1
			and str(restored_relationship.get("last_player_stance", "")) == "helpful"
			and int(restored_state.get("state_revision", 0)) == 3,
		"NPC state checkpoint restore did not rewind post-checkpoint relationship changes."
	)

	var reopened := NpcStateStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid(),
		"Reopened NPC state store is invalid: %s" %
			JSON.stringify(reopened.validation.to_dict())
	)
	var reopened_state: Dictionary = reopened.state_for(NPC_ID)
	_expect(
		int(reopened_state.get("state_revision", 0)) == 3
			and str(reopened_state.get("memory_summary", "")) == "Mara remembers the relay inspection.",
		"NPC state did not persist after reopen."
	)


func _test_structured_event_memory_projection() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"NPC Structured Memory Fixture",
		"npc-state-structured-memory-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return
	var store := NpcStateStoreType.open(CAMPAIGN_PATH)
	_expect(store.is_valid(), "NPC state store was invalid for structured memory test.")
	if not store.is_valid():
		return
	var memory: Dictionary = store.record_memory_events(
		NPC_ID,
		[
			{
				"event_id": "event.local.fixture.unrelated",
				"event_type": "mission_completed",
				"subject_ids": ["npc.gen.fixture.other"],
				"payload": {"title": "Other job"},
			},
			{
				"event_id": "event.local.fixture.drink",
				"event_type": "lounge_drink_bought",
				"subject_ids": [NPC_ID],
				"payload": {"summary": "The pilot bought Mara a drink."},
			},
			{
				"event_id": "event.local.fixture.relay",
				"event_type": "mission_completed",
				"subject_ids": [NPC_ID, "thread.convoy_shortage"],
				"payload": {"title": "Relay inspection completed"},
			},
		],
		"She keeps a private ledger of useful pilots."
	)
	_expect(bool(memory.get("ok", false)), memory.get("error", ""))
	var state: Dictionary = memory.get("state", {})
	var refs: Array = state.get("memory_event_ids", [])
	_expect(
		refs == ["event.local.fixture.drink", "event.local.fixture.relay"],
		"Structured NPC memory projection did not keep only relevant event refs."
	)
	_expect(
		str(state.get("memory_summary", "")).contains("bought Mara a drink")
			and str(state.get("memory_summary", "")).contains("Relay inspection completed"),
		"Structured NPC memory projection did not build a code-owned summary."
	)
	_expect(
		(state.get("line_memory_fingerprints", []) as Array).size() == 1,
		"Structured NPC memory projection did not remember the generated line fingerprint."
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
