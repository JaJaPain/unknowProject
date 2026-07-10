extends SceneTree

const AgentMemoryStoreType := preload(
	"res://scripts/persistence/CampaignAgentMemorySnippetStore.gd"
)
const SlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)

const TEST_ROOT := "user://campaign_agent_memory_fixture"
const CAMPAIGN_PATH := TEST_ROOT + "/slot_01"

var _failures: Array[String] = []
var SystemRegistryType: GDScript = null


func _initialize() -> void:
	SystemRegistryType = load("res://scripts/registry/SystemRegistry.gd")
	if SystemRegistryType == null:
		push_error("[FAIL] SystemRegistry.gd did not compile - suite cannot run.")
		quit(1)
		return
	_cleanup()
	_test_agent_memory_bootstrap_append_context_and_reopen()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Campaign agent memory snippet store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_agent_memory_bootstrap_append_context_and_reopen() -> void:
	var slots := SlotRegistryType.open(TEST_ROOT)
	var created := slots.create_campaign(
		"slot_01",
		"Agent Memory Fixture",
		"agent-memory-test",
		_initial_state(),
		SystemRegistryType.load_default()
	)
	_expect(bool(created.get("ok", false)), created.get("error", ""))
	if not bool(created.get("ok", false)):
		return

	var store := AgentMemoryStoreType.open(CAMPAIGN_PATH)
	_expect(
		store.is_valid(),
		"Agent memory store is invalid: %s" %
			JSON.stringify(store.validation.to_dict())
	)
	if not store.is_valid():
		return
	_expect(
		int(store.summary().get("total_snippets", -1)) == 0,
		"Agent memory did not bootstrap empty."
	)
	_expect(
		store.prompt_context("agent.director_voss").contains("No prior contracts"),
		"Empty agent memory did not instruct first-contact tone."
	)

	var first: Dictionary = store.append_snippet(
		"agent.director_voss",
		"Director Voss",
		"zenith",
		"Indy recovered a hazardous container after Zenith reported supply shortages.",
		["pickup", "logistics_shortage"],
		{
			"objective_type": "PICKUP_SPECIAL",
			"narrative_metadata": {
				"story_hook_ref": "hook:agentmemory123",
				"completion_fact_ids": ["fact.hazardous_container_recovered"],
			},
		}
	)
	_expect(bool(first.get("ok", false)), first.get("error", ""))
	var duplicate: Dictionary = store.append_snippet(
		"agent.director_voss",
		"Director Voss",
		"zenith",
		"Indy recovered a hazardous container after Zenith reported supply shortages.",
		["pickup"],
		{}
	)
	_expect(
		bool(duplicate.get("duplicate", false)),
		"Duplicate agent memory snippet was not detected."
	)
	var second: Dictionary = store.append_snippet(
		"agent.liaison_ryn",
		"Liaison Ryn",
		"aurelia",
		"Indy cleared Wraith ships that were slowing down Aurelia miners.",
		["combat", "wraiths", "miners"]
	)
	_expect(bool(second.get("ok", false)), second.get("error", ""))

	var prompt: String = store.prompt_context("agent.director_voss")
	_expect(
		prompt.contains("Director Voss")
			and prompt.contains("hazardous container")
			and not prompt.contains("Aurelia miners"),
		"Agent prompt context did not stay scoped to one agent."
	)
	var kaelen_pull: Array = store.kaelen_memory_pull(4)
	_expect(
		kaelen_pull.size() == 2,
		"Kaelen pull did not include recent snippets across agents."
	)

	var reopened := AgentMemoryStoreType.open(CAMPAIGN_PATH)
	_expect(
		reopened.is_valid()
			and int(reopened.summary().get("total_snippets", 0)) == 2,
		"Agent memory snippets did not persist after reopening."
	)
	_expect(
		reopened.prompt_context("agent.liaison_ryn").contains("Wraith ships"),
		"Reopened agent memory could not retrieve Liaison Ryn snippet."
	)
	var director_snippets: Array = reopened.snippets_for_agent("agent.director_voss", 1)
	var director_metadata: Dictionary = (
		director_snippets[0].get("metadata", {})
		if not director_snippets.is_empty() else {}
	)
	var narrative_metadata: Dictionary = director_metadata.get("narrative_metadata", {})
	_expect(
		narrative_metadata.get("story_hook_ref", "") == "hook:agentmemory123"
			and (narrative_metadata.get("completion_fact_ids", []) as Array).has(
				"fact.hazardous_container_recovered"
			),
		"Agent memory snippet metadata did not preserve narrative metadata."
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
