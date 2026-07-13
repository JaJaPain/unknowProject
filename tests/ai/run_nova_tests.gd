extends SceneTree

# Runtime load, not const preload: Nova.gd references autoload singletons
# (CombatManager, GlobalState), which don't exist yet at preload time in
# --script mode — the const would cache a failed compile and this suite would
# print PASS with zero assertions.
var NovaType: GDScript = null

var _failures: Array[String] = []


func _initialize() -> void:
	NovaType = load("res://scripts/ai/Nova.gd")
	if NovaType == null or not NovaType.can_instantiate():
		push_error("[FAIL] Nova.gd did not compile — suite cannot run.")
		quit(1)
		return
	_test_expression_frame_mapping()
	_test_region_math()
	_test_event_expression_and_preempt()
	_test_combat_warning_api_exists()
	_test_campaign_quirk_lifecycle()
	_test_arrival_can_consume_ready_line_bank()
	_test_global_speech_budget()

	if _failures.is_empty():
		print("[PASS] Nova tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_expression_frame_mapping() -> void:
	_expect(NovaType.frame_index_for("neutral") == 0, "neutral should be frame 0.")
	_expect(NovaType.frame_index_for("alert") == 5, "alert should be frame 5.")
	_expect(NovaType.frame_index_for("downcast") == 8, "downcast should be frame 8.")
	_expect(NovaType.frame_index_for("nonexistent") == 0, "unknown expression should fall back to 0.")


func _test_region_math() -> void:
	# 300x300 sheet, 3x3 -> 100x100 frames.
	var r0: Rect2 = NovaType.region_for_frame(0, 300.0, 300.0)
	_expect(r0.position == Vector2(0, 0) and r0.size == Vector2(100, 100), "frame 0 region wrong: %s" % r0)
	var r5: Rect2 = NovaType.region_for_frame(5, 300.0, 300.0)  # col 2, row 1
	_expect(r5.position == Vector2(200, 100), "frame 5 region position wrong: %s" % r5)
	var r8: Rect2 = NovaType.region_for_frame(8, 300.0, 300.0)  # col 2, row 2
	_expect(r8.position == Vector2(200, 200), "frame 8 region position wrong: %s" % r8)
	# Out-of-range clamps.
	var rc: Rect2 = NovaType.region_for_frame(99, 300.0, 300.0)
	_expect(rc.position == Vector2(200, 200), "out-of-range frame should clamp to last.")


func _test_event_expression_and_preempt() -> void:
	_expect(NovaType.expression_for_event("targeted") == "alert", "targeted -> alert.")
	_expect(NovaType.expression_for_event("too_powerful") == "worried", "too_powerful -> worried.")
	_expect(NovaType.expression_for_event("idle") == "calm", "idle -> calm.")
	_expect(NovaType.expression_for_event("mystery") == "wondering", "mystery -> wondering.")
	# Severity pre-emption: THREAT beats IDLE; equal does not pre-empt.
	_expect(
		NovaType.should_preempt(NovaType.Severity.THREAT, NovaType.Severity.IDLE),
		"THREAT should pre-empt IDLE."
	)
	_expect(
		not NovaType.should_preempt(NovaType.Severity.IDLE, NovaType.Severity.THREAT),
		"IDLE should not pre-empt THREAT."
	)
	_expect(
		not NovaType.should_preempt(NovaType.Severity.NAV, NovaType.Severity.NAV),
		"Equal severity should not pre-empt."
	)


func _test_combat_warning_api_exists() -> void:
	var nova: Node = NovaType.new()
	_expect(
		nova.has_method("warn_hostile_engagement"),
		"Nova should expose hostile engagement warning for NPC-initiated combat."
	)
	nova.free()


func _test_campaign_quirk_lifecycle() -> void:
	var nova: Node = NovaType.new()
	nova.set_campaign_quirk("  I inventory the escape pods twice. Trust issues.  ")
	_expect(
		str(nova._campaign_quirk) == "I inventory the escape pods twice. Trust issues.",
		"set_campaign_quirk should strip and store the quirk."
	)
	# Glitch lines: stored stripped, blanks dropped.
	nova.set_memory_glitch_lines(["  Static with a shape to it.  ", "", "A hum I almost recognize."])
	_expect(
		(nova._memory_glitch_lines as Array).size() == 2
			and str(nova._memory_glitch_lines[0]) == "Static with a shape to it.",
		"set_memory_glitch_lines should strip lines and drop blanks."
	)
	# Wipe contract: restart clears quirk, glitch lines, and repeat/streak memory.
	nova._last_line_index["dock"] = 2
	nova._event_memory["dock"] = {"streak": 3, "last_ms": 12345}
	nova.reset_for_restart()
	_expect(
		str(nova._campaign_quirk).is_empty()
			and (nova._memory_glitch_lines as Array).is_empty()
			and (nova._last_line_index as Dictionary).is_empty()
			and (nova._event_memory as Dictionary).is_empty(),
		"reset_for_restart should wipe quirk, glitch lines, line-picker memory, and streaks."
	)
	# Disarmed Nova never speaks a quirk line.
	_expect(
		not bool(nova._maybe_speak_quirk()),
		"An empty quirk must never produce a quirk line."
	)
	nova.free()


func _test_arrival_can_consume_ready_line_bank() -> void:
	var file := FileAccess.open("res://scripts/ai/Nova.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect Nova.gd line-bank wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("func _ready_line_bank_text")
			and source.contains("consume_cached_narrative_line_bank")
			and source.contains("prefetch:current_system_nova")
			and source.contains("\"startup_navigation\"")
			and source.contains("speak(bank_line, Severity.NAV"),
		"N.O.V.A. arrival path does not consume ready current-system line banks before stock lines."
	)


# Global speech budget: casual lines respect the window/gap; warnings bypass
# it but still count as speech; restart wipes the ledger.
func _test_global_speech_budget() -> void:
	var nova: Node = NovaType.new()
	var idle: int = NovaType.Severity.IDLE
	var threat: int = NovaType.Severity.THREAT

	# Fresh ledger: a casual line is allowed and recorded by the caller.
	_expect(
		bool(nova._speech_budget_allows(idle, 10000)),
		"Fresh budget should allow a casual line."
	)
	nova._recent_speech_ms.append(10000)
	# Too soon after the last line: blocked.
	_expect(
		not bool(nova._speech_budget_allows(idle, 20000)),
		"A casual line inside the minimum gap should be blocked."
	)
	# Past the gap: fine, until the window fills up.
	nova._recent_speech_ms.append(30000)
	nova._recent_speech_ms.append(50000)
	_expect(
		not bool(nova._speech_budget_allows(idle, 70000)),
		"Three lines inside the window should exhaust the casual budget."
	)
	# Threat warnings bypass the budget even when it is exhausted.
	_expect(
		bool(nova._speech_budget_allows(threat, 70000)),
		"THREAT must bypass an exhausted speech budget."
	)
	# Once the window slides past the old lines, casual speech returns.
	_expect(
		bool(nova._speech_budget_allows(idle, 180000)),
		"Casual budget should recover after the window expires."
	)
	# Restart wipes the ledger.
	nova._recent_speech_ms.append(180000)
	nova.reset_for_restart()
	_expect(
		(nova._recent_speech_ms as Array).is_empty(),
		"reset_for_restart should clear the speech budget ledger."
	)
	nova.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
