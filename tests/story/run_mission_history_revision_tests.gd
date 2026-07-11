extends SceneTree

var _failures: Array[String] = []
var _story_manager: Node = null
var _quest_manager: Node = null
var _previous_state: Dictionary = {}
var _previous_store: Variant = null
var _seen_decline: bool = false
var _declined_reason: String = ""


func _initialize() -> void:
	_story_manager = get_root().get_node_or_null("StoryManager")
	_quest_manager = get_root().get_node_or_null("QuestManager")
	if _story_manager == null or _quest_manager == null:
		push_error("[FAIL] StoryManager and QuestManager autoloads should be available.")
		quit(1)
		return

	_previous_state = _story_manager.story_state.duplicate(true)
	_previous_store = _story_manager._story_state_store
	_story_manager._story_state_store = null
	_story_manager.story_state = {"mission_history_revision": 0}

	_test_story_manager_increments_revision()
	_test_story_and_knowledge_revision_methods_increment_owned_fields()
	_test_story_manager_promotes_fact_after_delivery()
	_test_quest_decline_increments_revision()

	_story_manager.story_state = _previous_state
	_story_manager._story_state_store = _previous_store

	if _failures.is_empty():
		print("[PASS] Mission history revision tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_story_manager_increments_revision() -> void:
	var revision: int = _story_manager.increment_mission_history_revision(
		"accepted",
		{"runtime_id": "mission.runtime.revision_test"}
	)
	_expect(
		revision == 1
			and int(_story_manager.story_state.get("mission_history_revision", 0)) == 1,
		"StoryManager did not increment mission_history_revision."
	)


func _test_story_and_knowledge_revision_methods_increment_owned_fields() -> void:
	_story_manager.story_state["story_revision"] = 0
	_story_manager.story_state["knowledge_revision"] = 0
	var story_revision: int = _story_manager.increment_story_revision(
		"test_story_change",
		{"title": "Story Revision Fixture"}
	)
	var knowledge_revision: int = _story_manager.increment_knowledge_revision(
		"test_knowledge_change",
		{"title": "Knowledge Revision Fixture"}
	)
	_expect(
		story_revision == 1
			and int(_story_manager.story_state.get("story_revision", 0)) == 1,
		"Story revision did not increment through its owned method."
	)
	_expect(
		knowledge_revision == 1
			and int(_story_manager.story_state.get("knowledge_revision", 0)) == 1,
		"Knowledge revision did not increment through its owned method."
	)


func _test_story_manager_promotes_fact_after_delivery() -> void:
	_story_manager.story_state["knowledge_revision"] = 0
	_story_manager.story_state["knowledge_states"] = {}
	var promoted: Dictionary = _story_manager.promote_fact_after_delivery(
		"fact.delivery.visible",
		"known",
		"mission_answer",
		"direct"
	)
	var states: Dictionary = _story_manager.story_state.get("knowledge_states", {})
	var record: Dictionary = states.get("fact.delivery.visible", {})
	_expect(
		bool(promoted.get("ok", false))
			and bool(promoted.get("changed", false))
			and record.get("state", "") == "known"
			and record.get("source", "") == "mission_answer"
			and int(_story_manager.story_state.get("knowledge_revision", 0)) == 1,
		"StoryManager did not promote a delivered fact through the ledger."
	)
	var duplicate: Dictionary = _story_manager.promote_fact_after_delivery(
		"fact.delivery.visible",
		"known",
		"mission_answer",
		"direct"
	)
	_expect(
		bool(duplicate.get("ok", false))
			and not bool(duplicate.get("changed", true))
			and int(_story_manager.story_state.get("knowledge_revision", 0)) == 1,
		"Repeated delivered fact promotion should not bump knowledge_revision."
	)


func _test_quest_decline_increments_revision() -> void:
	_quest_manager.quest_declined_details.connect(
		_on_quest_declined,
		CONNECT_ONE_SHOT
	)
	_quest_manager.decline_quest(
		{"title": "Declined Revision Offer"},
		"revision_test_decline"
	)
	_expect(
		_seen_decline and _declined_reason == "revision_test_decline",
		"QuestManager did not emit declined offer details."
	)
	_expect(
		int(_story_manager.story_state.get("mission_history_revision", 0)) == 2,
		"QuestManager decline did not increment mission_history_revision."
	)


func _on_quest_declined(quest_data: Dictionary) -> void:
	_seen_decline = true
	_declined_reason = str(quest_data.get("decline_reason", ""))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
