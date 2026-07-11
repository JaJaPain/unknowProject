extends SceneTree

var _failures: Array[String] = []
var _manager = null
var _previous_state: Dictionary = {}
var _previous_store = null


func _initialize() -> void:
	_manager = root.get_node("StoryManager")
	_previous_state = _manager.story_state.duplicate(true)
	_previous_store = _manager._story_state_store
	_manager._story_state_store = null
	_manager.clear_story_state()

	_test_register_packet_creates_rewindable_beat_states()
	_test_consumption_ratio_and_threshold()
	_test_next_packet_queue_marker_is_idempotent()

	_manager.story_state = _previous_state
	_manager._story_state_store = _previous_store

	if _failures.is_empty():
		print("[PASS] Chapter packet consumption tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_register_packet_creates_rewindable_beat_states() -> void:
	_manager.register_chapter_packet(_packet())
	var states: Dictionary = _manager.story_state.get("beat_states", {})
	_expect(states.has("beat.alpha"), "register_chapter_packet missing beat.alpha")
	_expect(states.has("beat.beta"), "register_chapter_packet missing beat.beta")
	_expect(
		str(states.get("beat.alpha", {}).get("packet_id", "")) == "chapter_packet.1",
		"beat state did not retain packet_id"
	)
	_expect(
		str(states.get("beat.alpha", {}).get("state", "")) == "available",
		"new beat state should start available"
	)


func _test_consumption_ratio_and_threshold() -> void:
	_manager.register_chapter_packet(_packet())
	_expect(
		is_equal_approx(_manager.chapter_packet_consumed_ratio(_packet()), 0.0),
		"fresh packet should have 0% consumption"
	)
	_manager.mark_chapter_beat_state("beat.alpha", "completed", "Won the escort.")
	_expect(
		is_equal_approx(_manager.chapter_packet_consumed_ratio(_packet()), 0.5),
		"one of two consumed beats should produce 50% consumption"
	)
	_expect(
		not _manager.should_queue_next_chapter_packet(_packet()),
		"50% consumption should not queue a 60% threshold"
	)
	_manager.mark_chapter_beat_state("beat.beta", "declined", "Chose another lead.")
	_expect(
		is_equal_approx(_manager.chapter_packet_consumed_ratio(_packet()), 1.0),
		"two consumed beats should produce 100% consumption"
	)
	_expect(
		_manager.should_queue_next_chapter_packet(_packet()),
		"100% consumption should queue next packet"
	)


func _test_next_packet_queue_marker_is_idempotent() -> void:
	_expect(
		not _manager.is_next_chapter_packet_queued(2),
		"chapter 2 should not start queued"
	)
	_expect(
		_manager.mark_next_chapter_packet_queued(2),
		"first queue marker write should report true"
	)
	_expect(
		_manager.is_next_chapter_packet_queued(2),
		"chapter 2 queue marker was not stored"
	)
	_expect(
		not _manager.mark_next_chapter_packet_queued(2),
		"second queue marker write should be idempotent"
	)


func _packet() -> Dictionary:
	return {
		"packet_id": "chapter_packet.1",
		"chapter": 1,
		"premise": "A pressure test.",
		"threads": [],
		"facts": [],
		"beats": [
			{"beat_id": "beat.alpha"},
			{"beat_id": "beat.beta"},
		],
		"next_packet_trigger": {
			"start_when_consumed_ratio_at_least": 0.6,
			"reason": "Keep the next arc warm.",
		},
	}
