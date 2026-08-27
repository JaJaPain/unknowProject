extends SceneTree

# Gates around the first five minutes: which speaker owns the first dock, and
# what must never repeat. These rot quietly -- the tutorial-gating pass already
# found intro_quest_delivered being used as "has the player finished the first
# job" when it actually means "has the player accepted it" -- so they are
# pinned here rather than left to a playtest to catch.

var _failures: Array[String] = []
var _story: Node = null


func _initialize() -> void:
	await process_frame
	_story = root.get_node_or_null("StoryManager")
	if _story == null:
		push_error("[FAIL] StoryManager autoload unavailable.")
		quit(1)
		return
	_test_first_dock_line_is_once_per_campaign()
	_test_new_campaign_resets_the_latch()
	_test_filler_is_blocked_during_loading()

	if _failures.is_empty():
		print("[PASS] Intro dock gating tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


# The repro: dock, undock WITHOUT visiting Kaelen, dock again. kaelen_briefing_seen
# is still false at that point, so the authored line's own latch is the only
# thing standing between the player and hearing it twice.
func _test_first_dock_line_is_once_per_campaign() -> void:
	_story.story_state["intro_first_dock_line_spoken"] = false
	_expect(
		_story.claim_intro_first_dock_line(),
		"The first dock must be allowed to serve the authored line."
	)
	_expect(
		not _story.claim_intro_first_dock_line(),
		"A second dock before meeting Kaelen must NOT replay the authored line."
	)
	_expect(
		not _story.claim_intro_first_dock_line(),
		"A third dock must not replay it either."
	)
	_expect(
		_story.has_spoken_intro_first_dock_line(),
		"The latch must read back as spoken."
	)


# A brand-new campaign has to hear it again, so the flag must be part of the
# per-campaign defaults rather than a global.
func _test_new_campaign_resets_the_latch() -> void:
	var defaults: Dictionary = _story.get("DEFAULT_STORY_STATE") \
		if _story.get("DEFAULT_STORY_STATE") is Dictionary else {}
	if defaults.is_empty():
		# Fall back to the reset path when the constant is not exposed.
		if _story.has_method("reset_for_new_campaign"):
			_story.call("reset_for_new_campaign")
		else:
			_story.story_state["intro_first_dock_line_spoken"] = false
	else:
		_expect(
			defaults.has("intro_first_dock_line_spoken") \
				and not bool(defaults["intro_first_dock_line_spoken"]),
			"A fresh campaign must default to not-yet-spoken."
		)
	_story.story_state["intro_first_dock_line_spoken"] = false
	_expect(
		_story.claim_intro_first_dock_line(),
		"After a campaign reset the line must be available again."
	)


# The filler ban is a policy about when the game may make a non-semantic noise,
# so it is asserted on SpeechService itself. It used to live in one UIManager
# helper, where any other caller bypassed it silently.
func _test_filler_is_blocked_during_loading() -> void:
	var speech: Node = root.get_node_or_null("SpeechService")
	if speech == null:
		_failures.append("SpeechService autoload unavailable.")
		return
	# A wait that would normally earn a filler clip.
	var allowed: Dictionary = speech.latency_filler_clip_request(
		"N.O.V.A.", "voice.nova.v1", "llm_generation", 0.8, false, 0
	)
	_expect(
		bool(allowed.get("ok", false)),
		"A normal in-interaction wait should still earn a filler: %s" % str(allowed)
	)
	speech.set_latency_filler_suppressed(true, "loading_screen")
	var blocked: Dictionary = speech.latency_filler_clip_request(
		"N.O.V.A.", "voice.nova.v1", "llm_generation", 0.8, false, 0
	)
	_expect(
		not bool(blocked.get("ok", false)),
		"Filler must be refused while the opening sequence is running."
	)
	_expect(
		str(blocked.get("reason", "")).contains("loading_screen"),
		"The refusal should name the suppressing sequence, got '%s'." % str(blocked.get("reason", ""))
	)
	# Kaelen is covered by the same ban -- the old guard only wrapped N.O.V.A.
	var kaelen_blocked: Dictionary = speech.latency_filler_clip_request(
		"Broker Kaelen", GlobalState.KAELEN_VOICE_PROFILE_ID, "llm_generation", 0.8, false, 0
	)
	_expect(
		not bool(kaelen_blocked.get("ok", false)),
		"The ban must cover every speaker, not just the one call site it used to guard."
	)
	speech.set_latency_filler_suppressed(false)
	var released: Dictionary = speech.latency_filler_clip_request(
		"N.O.V.A.", "voice.nova.v1", "llm_generation", 0.8, false, 0
	)
	_expect(
		bool(released.get("ok", false)),
		"Filler must work again once gameplay starts: %s" % str(released)
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
