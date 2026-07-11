extends SceneTree

var StoryManagerType: GDScript = null

var _failures: Array[String] = []


func _initialize() -> void:
	StoryManagerType = load("res://scripts/story/StoryManager.gd")
	if StoryManagerType == null or not StoryManagerType.can_instantiate():
		push_error("[FAIL] StoryManager.gd did not compile — suite cannot run.")
		quit(1)
		return
	_test_story_state_checkpoint_restore_rewinds_later_timeline()

	if _failures.is_empty():
		print("[PASS] Narrative checkpoint story_state tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_story_state_checkpoint_restore_rewinds_later_timeline() -> void:
	var manager: Node = StoryManagerType.new()
	root.add_child(manager)
	manager.clear_story_state()
	manager.story_state["chapter"] = 2
	manager.story_state["story_revision"] = 4
	manager.story_state["knowledge_revision"] = 7
	manager.story_state["mission_history_revision"] = 3
	manager.story_state["knowledge_states"] = {
		"fact.before_checkpoint": {
			"state": "known",
			"source": "mission_answer",
			"learned_at_minute": 90,
			"confidence": "direct",
			"public_text": "Before checkpoint fact.",
		},
	}
	manager.story_state["beat_states"] = {
		"beat.before_checkpoint": {
			"state": "completed",
			"completed_at_minute": 91,
		},
	}

	var captured: Dictionary = manager.capture_story_state_for_checkpoint()

	manager.story_state["chapter"] = 3
	manager.story_state["story_revision"] = 9
	manager.story_state["knowledge_revision"] = 12
	manager.story_state["mission_history_revision"] = 6
	manager.story_state["knowledge_states"]["fact.after_checkpoint"] = {
		"state": "known",
		"source": "post_checkpoint_mission",
		"learned_at_minute": 130,
		"confidence": "direct",
		"public_text": "After checkpoint fact.",
	}
	manager.story_state["beat_states"]["beat.after_checkpoint"] = {
		"state": "completed",
		"completed_at_minute": 131,
	}

	_expect(
		manager.restore_story_state_from_checkpoint(captured),
		"StoryManager rejected a captured checkpoint story_state."
	)
	var restored: Dictionary = manager.story_state
	var knowledge: Dictionary = restored.get("knowledge_states", {})
	var beats: Dictionary = restored.get("beat_states", {})
	_expect(
		int(restored.get("chapter", 0)) == 2
			and int(restored.get("story_revision", 0)) == 4
			and int(restored.get("knowledge_revision", 0)) == 7
			and int(restored.get("mission_history_revision", 0)) == 3,
		"Checkpoint story_state restore did not rewind chapter/revisions."
	)
	_expect(
		knowledge.has("fact.before_checkpoint")
			and not knowledge.has("fact.after_checkpoint"),
		"Checkpoint story_state restore did not rewind knowledge facts."
	)
	_expect(
		beats.has("beat.before_checkpoint")
			and not beats.has("beat.after_checkpoint"),
		"Checkpoint story_state restore did not rewind beat progress."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
