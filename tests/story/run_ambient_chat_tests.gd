extends SceneTree

# Runtime load, not const preload: AmbientChatGenerator references autoload
# singletons (StoryManager, LLMInterface, CombatManager), which don't exist at
# preload time in --script mode (see run_story_state_bible_seed_tests note).
var GenType: GDScript = null
var StoryManagerType: GDScript = null

var _failures: Array[String] = []


func _initialize() -> void:
	GenType = load("res://scripts/story/AmbientChatGenerator.gd")
	StoryManagerType = load("res://scripts/story/StoryManager.gd")
	if GenType == null or not GenType.can_instantiate() \
			or StoryManagerType == null or not StoryManagerType.can_instantiate():
		push_error("[FAIL] Ambient chat scripts did not compile — suite cannot run.")
		quit(1)
		return
	_test_bucket_boundaries()
	_test_candidates_per_bucket_and_privacy()
	_test_select_topic_dedup()
	_test_prompt_content()
	_test_parse_chat_lines()
	_test_story_manager_topic_bookkeeping()

	if _failures.is_empty():
		print("[PASS] Ambient chat tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_bucket_boundaries() -> void:
	_expect(GenType.pick_bucket(0.0) == GenType.BUCKET_MUNDANE, "roll 0.0 should be mundane.")
	_expect(GenType.pick_bucket(0.49) == GenType.BUCKET_MUNDANE, "roll 0.49 should be mundane.")
	_expect(GenType.pick_bucket(0.5) == GenType.BUCKET_STORY, "roll 0.5 should be story-adjacent.")
	_expect(GenType.pick_bucket(0.79) == GenType.BUCKET_STORY, "roll 0.79 should be story-adjacent.")
	_expect(GenType.pick_bucket(0.8) == GenType.BUCKET_INTEL, "roll 0.8 should be overheard intel.")
	_expect(GenType.pick_bucket(0.99) == GenType.BUCKET_INTEL, "roll 0.99 should be overheard intel.")


# One fake story state carrying BOTH player-safe and director-only content; no
# candidate in any bucket may ever surface the director-only strings.
func _fake_story_state() -> Dictionary:
	return {
		"active_tensions": ["Dock strikes are spreading past the inner ring."],
		"current_foreshadow": "Every third manifest out of Kova reads a day early.",
		"player_knows": ["The refinery audit was staged."],
		"pending_hooks": ["A crate stenciled VALE keeps moving between berths."],
		"kaelen_hidden_angle": "SECRET_ANGLE_TOKEN",
		"player_does_not_know_yet": ["SECRET_TRUTH_TOKEN"],
		"nova_memory_flicker": "SECRET_FLICKER_TOKEN",
	}


func _test_candidates_per_bucket_and_privacy() -> void:
	var state := _fake_story_state()
	var story: Array = GenType.build_topic_candidates(GenType.BUCKET_STORY, state)
	_expect(story.size() == 3, "Story bucket should offer tension + foreshadow + known truth (got %d)." % story.size())
	var intel: Array = GenType.build_topic_candidates(GenType.BUCKET_INTEL, state)
	_expect(intel.size() == 1, "Intel bucket should offer the pending hook (got %d)." % intel.size())
	var mundane: Array = GenType.build_topic_candidates(GenType.BUCKET_MUNDANE, state)
	_expect(mundane.size() >= 20, "Mundane pool should be deep (got %d)." % mundane.size())
	for bucket_list in [story, intel, mundane]:
		for candidate in bucket_list:
			var subject := str((candidate as Dictionary).get("subject", ""))
			_expect(
				not subject.contains("SECRET_ANGLE_TOKEN")
					and not subject.contains("SECRET_TRUTH_TOKEN")
					and not subject.contains("SECRET_FLICKER_TOKEN"),
				"A director-only field leaked into ambient topic candidates: %s" % subject
			)
			_expect(
				str((candidate as Dictionary).get("id", "")).begins_with("ambient:"),
				"Candidate id missing ambient: prefix."
			)


func _test_select_topic_dedup() -> void:
	var candidates := [
		{"id": "ambient:mundane:aaa", "bucket": "mundane", "subject": "A"},
		{"id": "ambient:mundane:bbb", "bucket": "mundane", "subject": "B"},
		{"id": "ambient:mundane:ccc", "bucket": "mundane", "subject": "C"},
	]
	var picked: Dictionary = GenType.select_topic(candidates, ["ambient:mundane:aaa"])
	_expect(str(picked.get("id", "")) == "ambient:mundane:bbb", "select_topic should skip used ids.")
	var wrapped: Dictionary = GenType.select_topic(candidates, ["ambient:mundane:ccc"], 2)
	_expect(
		str(wrapped.get("id", "")) == "ambient:mundane:aaa",
		"select_topic should wrap around from start_index (got %s)." % str(wrapped.get("id", ""))
	)
	var exhausted: Dictionary = GenType.select_topic(
		candidates,
		["ambient:mundane:aaa", "ambient:mundane:bbb", "ambient:mundane:ccc"]
	)
	_expect(exhausted.is_empty(), "select_topic should return {} when every candidate is used.")
	_expect(GenType.select_topic([], []).is_empty(), "select_topic on empty candidates should return {}.")


func _test_prompt_content() -> void:
	var topic := {
		"id": "ambient:overheard_intel:xyz",
		"bucket": GenType.BUCKET_INTEL,
		"subject": "A crate stenciled VALE keeps moving between berths.",
	}
	var a := {"name": "Ivet", "role": "dock controller"}
	var b := {"name": "Skiff", "role": "tug pilot"}
	var prompt: String = GenType.build_prompt(topic, a, b, "Campaign tone: dry, wary.")
	_expect(prompt.contains("Ivet") and prompt.contains("dock controller"), "Prompt missing speaker A identity.")
	_expect(prompt.contains("Skiff") and prompt.contains("tug pilot"), "Prompt missing speaker B identity.")
	_expect(prompt.contains("crate stenciled VALE"), "Prompt missing the topic subject.")
	_expect(prompt.contains("FRAGMENT"), "Intel prompt missing the overheard-fragment framing.")
	_expect(prompt.contains("Campaign tone: dry, wary."), "Prompt missing the flavor block.")
	_expect(prompt.contains("never mention the player"), "Prompt missing the no-meta rule.")
	_expect(prompt.contains("\"lines\""), "Prompt missing the JSON shape spec.")
	# Mundane framing differs and flavor is optional.
	var mundane_prompt: String = GenType.build_prompt(
		{"id": "x", "bucket": GenType.BUCKET_MUNDANE, "subject": "the cafeteria's mystery stew rotation"},
		a, b, ""
	)
	_expect(
		mundane_prompt.contains("genuinely mundane") and not mundane_prompt.contains("Campaign flavor"),
		"Mundane prompt framing/optional-flavor handling wrong."
	)


func _test_parse_chat_lines() -> void:
	var good := JSON.stringify({"lines": [
		{"speaker": "a", "text": "Third crate this week. Same stencil."},
		{"speaker": "b", "text": "You counted? That's adorable."},
		{"speaker": "a", "text": "Someone has to. Manifest says it's towels."},
	]})
	var parsed: Dictionary = GenType.parse_chat_lines(good)
	_expect(bool(parsed.get("ok", false)), "Valid 3-line conversation was rejected: %s" % str(parsed.get("reason", "")))
	_expect((parsed.get("lines", []) as Array).size() == 3, "Valid conversation lost lines in parsing.")
	# Speaker label variants coerce.
	var variants := JSON.stringify({"lines": [
		{"speaker": "A", "text": "Fees went up again this cycle."},
		{"speaker": "speaker_b", "text": "And the coffee got worse. Coincidence?"},
	]})
	_expect(
		bool((GenType.parse_chat_lines(variants) as Dictionary).get("ok", false)),
		"Speaker label variants (A / speaker_b) should be coerced, not rejected."
	)
	# Over 4 lines truncates instead of failing.
	var long_lines := []
	for i in range(6):
		long_lines.append({"speaker": "a" if i % 2 == 0 else "b", "text": "Line number %d of the conversation." % i})
	var truncated: Dictionary = GenType.parse_chat_lines(JSON.stringify({"lines": long_lines}))
	_expect(
		bool(truncated.get("ok", false)) and (truncated.get("lines", []) as Array).size() == 4,
		"6-line conversation should truncate to 4."
	)
	# Rejections: single voice, one line, junk.
	var monologue := JSON.stringify({"lines": [
		{"speaker": "a", "text": "Talking to myself again."},
		{"speaker": "a", "text": "At least the company's good."},
	]})
	_expect(
		str((GenType.parse_chat_lines(monologue) as Dictionary).get("reason", "")) == "single_voice",
		"A one-speaker exchange should be rejected as single_voice."
	)
	_expect(
		not bool((GenType.parse_chat_lines(JSON.stringify({"lines": [{"speaker": "a", "text": "Just me."}]})) as Dictionary).get("ok", false)),
		"A single line should be rejected."
	)
	_expect(
		not bool((GenType.parse_chat_lines("not json at all") as Dictionary).get("ok", false)),
		"Junk text should be rejected."
	)


func _test_story_manager_topic_bookkeeping() -> void:
	var manager: Node = StoryManagerType.new()
	root.add_child(manager)
	manager.record_ambient_topic_used("ambient:mundane:aaa")
	manager.record_ambient_topic_used("ambient:mundane:aaa")  # dedup
	manager.record_ambient_topic_used("ambient:story_adjacent:bbb")
	var used: Array = manager.story_state.get("ambient_used_topics", [])
	_expect(used.size() == 2, "record_ambient_topic_used should dedup (got %d entries)." % used.size())
	# Chapter advance retires the whole list.
	manager.advance_chapter(0, ["fresh tension"], ["fresh hook"])
	_expect(
		(manager.story_state.get("ambient_used_topics", []) as Array).is_empty(),
		"advance_chapter should clear ambient_used_topics."
	)
	manager.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
