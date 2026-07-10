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
