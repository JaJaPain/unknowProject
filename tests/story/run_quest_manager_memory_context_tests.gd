extends SceneTree

var _failures: Array[String] = []
var _previous_store: Variant = null
var _global_state: Node = null
var _quest_manager: Node = null


class FakeAgentMemoryStore:
	var requested_agent_ids: Array[String] = []
	var contexts: Dictionary = {}

	func prompt_context(agent_id: String, _limit: int = 4) -> String:
		requested_agent_ids.append(agent_id)
		return str(contexts.get(agent_id, ""))


func _initialize() -> void:
	_global_state = get_root().get_node_or_null("GlobalState")
	if _global_state == null:
		push_error("[FAIL] GlobalState autoload should be available.")
		quit(1)
		return
	_quest_manager = get_root().get_node_or_null("QuestManager")
	if _quest_manager == null:
		push_error("[FAIL] QuestManager autoload should be available.")
		quit(1)
		return
	_previous_store = _global_state.campaign_agent_memory_store
	_test_filter_history_reads_campaign_agent_memory()
	_test_filter_history_honors_persisted_agent_memory_id()
	_test_generation_history_uses_profile_agent_memory()
	_test_empty_store_uses_first_contact_context()
	_test_campaign_memory_context_does_not_cross_stores()
	_global_state.campaign_agent_memory_store = _previous_store

	if _failures.is_empty():
		print("[PASS] Quest manager memory context tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_filter_history_reads_campaign_agent_memory() -> void:
	var fake := FakeAgentMemoryStore.new()
	fake.contexts["agent.fixed.zenith.director_voss"] = (
		"Director Voss remembers Indy recovering a hazardous container."
	)
	_global_state.campaign_agent_memory_store = fake

	var context: String = _quest_manager.filter_history_for_agent("Director Voss", "zenith")
	_expect(
		context.contains("hazardous container"),
		"QuestManager did not return structured campaign memory for Director Voss."
	)
	_expect(
		fake.requested_agent_ids == ["agent.fixed.zenith.director_voss"],
		"QuestManager queried the wrong agent memory id: %s" %
			JSON.stringify(fake.requested_agent_ids)
	)


func _test_filter_history_honors_persisted_agent_memory_id() -> void:
	var fake := FakeAgentMemoryStore.new()
	fake.contexts["agent.generated.local_fixer"] = (
		"The local fixer remembers the stolen beacon job."
	)
	_global_state.campaign_agent_memory_store = fake

	var context: String = _quest_manager.filter_history_for_agent(
		"Mara Venn",
		"neutral",
		{"agent_memory_id": "agent.generated.local_fixer"}
	)
	_expect(
		context.contains("stolen beacon"),
		"QuestManager ignored a quest's persisted agent_memory_id."
	)
	_expect(
		fake.requested_agent_ids == ["agent.generated.local_fixer"],
		"QuestManager did not query the persisted agent_memory_id."
	)


func _test_generation_history_uses_profile_agent_memory() -> void:
	var fake := FakeAgentMemoryStore.new()
	fake.contexts["agent.station.mara_venn"] = (
		"Mara Venn remembers Indy refusing a dangerous shortcut."
	)
	_global_state.campaign_agent_memory_store = fake

	var context: String = _quest_manager._generation_history_context(
		"neutral",
		{
			"name": "Mara Venn",
			"faction": "neutral",
			"agent_id": "agent.station.mara_venn",
		}
	)
	_expect(
		context.contains("dangerous shortcut"),
		"Quest generation history did not use the station agent profile memory."
	)
	_expect(
		fake.requested_agent_ids == ["agent.station.mara_venn"],
		"Quest generation history queried the wrong profile memory id."
	)


func _test_empty_store_uses_first_contact_context() -> void:
	_global_state.campaign_agent_memory_store = null
	var context: String = _quest_manager.filter_history_for_agent(
		"Broker Kaelen",
		"neutral"
	)
	_expect(
		context.contains("No prior contracts"),
		"Missing campaign memory store did not produce first-contact context."
	)


func _test_campaign_memory_context_does_not_cross_stores() -> void:
	var campaign_a := FakeAgentMemoryStore.new()
	campaign_a.contexts["agent.fixed.zenith.director_voss"] = (
		"Campaign A memory: Indy recovered the red beacon."
	)
	var campaign_b := FakeAgentMemoryStore.new()
	campaign_b.contexts["agent.fixed.zenith.director_voss"] = (
		"Campaign B memory: Indy escorted the blue convoy."
	)

	_global_state.campaign_agent_memory_store = campaign_a
	var context_a: String = _quest_manager.filter_history_for_agent(
		"Director Voss",
		"zenith"
	)
	_global_state.campaign_agent_memory_store = campaign_b
	var context_b: String = _quest_manager.filter_history_for_agent(
		"Director Voss",
		"zenith"
	)

	_expect(
		context_a.contains("red beacon")
			and not context_a.contains("blue convoy"),
		"Campaign A prompt context leaked Campaign B memory."
	)
	_expect(
		context_b.contains("blue convoy")
			and not context_b.contains("red beacon"),
		"Campaign B prompt context leaked Campaign A memory."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
