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
	_test_semantic_movement_consumes_banks_or_stays_silent()
	_test_repeated_events_mostly_produce_silence()

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


# Movement consumption: prepared bank lines or silence — no stock pools, no
# model. With no bank available (bare instance, no scene tree), every event
# must produce zero speech and zero errors.
func _test_semantic_movement_consumes_banks_or_stays_silent() -> void:
	var nova: Node = NovaType.new()
	var gs = root.get_node("GlobalState")
	var spoken: Array = []
	var listener := func(flavor: Dictionary) -> void:
		spoken.append(flavor)
	gs.npc_flavor_spoken.connect(listener)
	nova.on_semantic_movement_event("boost_again_quickly", {})
	nova.on_semantic_movement_event("rough_arrival", {"system_id": "x"})
	nova.on_semantic_movement_event("not_a_real_event", {})
	gs.npc_flavor_spoken.disconnect(listener)
	nova.free()
	_expect(
		spoken.is_empty(),
		"Movement events without a prepared bank must stay silent."
	)

	var nova_file := FileAccess.open("res://scripts/ai/Nova.gd", FileAccess.READ)
	var game_root_file := FileAccess.open(
		"res://scripts/GameRoot.gd", FileAccess.READ
	)
	_expect(
		nova_file != null and game_root_file != null,
		"Could not inspect semantic movement wiring."
	)
	if nova_file == null or game_root_file == null:
		return
	var nova_source := nova_file.get_as_text()
	var game_root_source := game_root_file.get_as_text()
	_expect(
		nova_source.contains("func on_semantic_movement_event")
			and nova_source.contains("for_semantic_event")
			and nova_source.contains("accepted_kinds"),
		"Movement handler does not route through NovaLineBankCategories."
	)
	# Phase 8A/8B tripwire: nothing in Nova.gd may touch the model layer.
	# If a legitimate LLM path is ever added for OTHER beats, it must live
	# outside this file so movement stays provably model-free.
	_expect(
		not nova_source.contains("LLMInterface")
			and not nova_source.contains("Ollama"),
		"Nova.gd references the model layer — movement is no longer provably model-free."
	)
	_expect(
		game_root_source.contains(
			"semantic_movement_event.connect"
		) and game_root_source.contains("Nova.on_semantic_movement_event"),
		"GameRoot does not route semantic movement events to N.O.V.A."
	)


# Phase 8B silence test: hammering the same beat must produce mostly
# silence, not a line per event. Six back-to-back docks pass the tier
# ladder's quiet zone AND the global speech budget's minimum gap, so only
# the first dock actually speaks. (Movement-side suppression after the
# rate-limit cap is covered in run_ship_behavior_observer_tests.gd.)
func _test_repeated_events_mostly_produce_silence() -> void:
	var nova: Node = NovaType.new()
	var gs = root.get_node("GlobalState")
	var previous_player = gs.player
	# _say_tiered reads player.destroyed / player.is_docked, so the stub
	# needs real properties (p.get() on a missing property returns null and
	# bool(null) is a runtime error).
	var stub := GDScript.new()
	stub.source_code = (
		"extends Node3D\n"
		+ "var destroyed := false\n"
		+ "var is_docked := false\n"
		+ "var health := 100.0\n"
		+ "var max_health := 100.0\n"
	)
	stub.reload()
	var dummy_player: Node3D = stub.new()
	gs.player = dummy_player

	var spoken: Array = []
	var listener := func(flavor: Dictionary) -> void:
		spoken.append(str(flavor.get("line", "")))
	gs.npc_flavor_spoken.connect(listener)
	for i in range(6):
		nova.on_docked("Kova Station")
	gs.npc_flavor_spoken.disconnect(listener)

	gs.player = previous_player
	dummy_player.free()
	nova.free()
	_expect(
		spoken.size() == 1,
		"Six instant docks should produce exactly one line, got %d: %s"
			% [spoken.size(), str(spoken)]
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
