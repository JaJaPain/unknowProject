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
	_test_repair_aware_undock_warning_rotation()
	_test_gate_glitch_bank_is_protected()
	_test_mission_hunt_reactions_are_prepared_and_progressive()

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


func _test_mission_hunt_reactions_are_prepared_and_progressive() -> void:
	var nova: Node = NovaType.new()
	var gs = root.get_node("GlobalState")
	var hunt := {
		"objective": {"type": "KILL_SHIPS", "target_faction": "reavers"},
	}
	var prepared: Dictionary = nova.prepare_mission_hunt_reaction(hunt)
	_expect(
		not str(prepared.get("nova_mission_hunt_reaction", "")).is_empty()
			and int(prepared.get("nova_mission_hunt_reaction_stage", -1)) == 0,
		"First-system hunt contracts should pre-cache a pacifist N.O.V.A. reaction."
	)
	_expect(
		str(hunt.get("nova_mission_hunt_reaction", "")).is_empty(),
		"Preparing a mission reaction must not mutate the source offer."
	)
	var seen: Array = gs.get("kaelen_arrival_systems_seen")
	seen.clear()
	seen.append_array(["system.one", "system.two", "system.three"])
	var late: Dictionary = nova.prepare_mission_hunt_reaction(hunt)
	_expect(
		int(late.get("nova_mission_hunt_reaction_stage", -1)) == 2,
		"N.O.V.A. should not become combat-eager before the fourth system."
	)
	seen.clear()
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
			and source.contains("accepted_kinds")
			and source.contains(
				"_bank_line_or_stock(NovaBankCategoriesType.SYSTEM_ARRIVAL"
			),
		"N.O.V.A. arrival path does not consume ready current-system line banks before stock lines."
	)
	# Every flat-pool beat routes bank-first with logged stock degradation;
	# the combat tutorial stays authored and never touches the bank helper.
	_expect(
		source.contains("func _bank_line_or_stock"),
		"Bank-first stock degradation helper is missing."
	)
	for beat_marker in [
		"NovaBankCategoriesType.GATE_TRANSIT",
		"NovaBankCategoriesType.WELCOME_BACK",
		"NovaBankCategoriesType.HULL_CRITICAL",
		"NovaBankCategoriesType.COMBAT_RETREAT",
		"NovaBankCategoriesType.COMBAT_VICTORY_BATTERED",
		"NovaBankCategoriesType.COMBAT_VICTORY_CLEAN",
	]:
		_expect(
			source.contains(beat_marker),
			"Beat is not routed bank-first: %s" % beat_marker
		)
	_expect(
		source.contains("\"stock_line_used\""),
		"Stock line usage is not logged as degraded content."
	)
	var tutorial_start := source.find("func on_combat_tutorial")
	var tutorial_end := source.find("func ", tutorial_start + 10)
	var tutorial_body := source.substr(tutorial_start, tutorial_end - tutorial_start)
	_expect(
		not tutorial_body.contains("_bank_line_or_stock")
			and not tutorial_body.contains("_ready_line_bank_text"),
		"Tutorial lines must stay authored, not bank-driven."
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
	_expect(
		nova_source.contains("real_beat_live")
			and nova_source.contains("mission_beat")
			and nova_source.contains("prefer_story_aware"),
		"Movement handler lost its relevance scoring (story-aware preference)."
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


func _test_repair_aware_undock_warning_rotation() -> void:
	var nova: Node = NovaType.new()
	var gs = root.get_node("GlobalState")
	var previous_player = gs.player
	var previous_rotation: Dictionary = gs.nova_repair_warning_rotation.duplicate(true)
	var stub := GDScript.new()
	stub.source_code = (
		"extends Node3D\n"
		+ "var destroyed := false\n"
		+ "var is_docked := true\n"
		+ "var health := 55.0\n"
		+ "var max_health := 100.0\n"
	)
	stub.reload()
	var dummy_player: Node3D = stub.new()
	gs.player = dummy_player
	gs.nova_repair_warning_rotation = {"yellow": 0, "red": 0}

	var first_yellow := str(nova.get_unrepaired_undock_warning(true, false).get("line", ""))
	var second_yellow := str(nova.get_unrepaired_undock_warning(true, false).get("line", ""))
	_expect(
		NovaType.REPAIR_WARNING_YELLOW_LINES.has(first_yellow)
			and NovaType.REPAIR_WARNING_YELLOW_LINES.has(second_yellow)
			and first_yellow != second_yellow,
		"Yellow repair warnings must use a non-repeating round-robin pool."
	)
	_expect(
		int(gs.nova_repair_warning_rotation.get("yellow", -1)) == 2,
		"Yellow repair-warning cursor did not advance persistently."
	)
	dummy_player.health = 20.0
	var red := str(nova.get_unrepaired_undock_warning(true, false).get("line", ""))
	_expect(
		NovaType.REPAIR_WARNING_RED_LINES.has(red)
			and int(gs.nova_repair_warning_rotation.get("red", -1)) == 1,
		"Red repair warning did not use its independent persistent cursor."
	)
	_expect(
		nova.get_unrepaired_undock_warning(false, false).is_empty()
			and nova.get_unrepaired_undock_warning(true, true).is_empty(),
		"Repair warning must stay silent without station repairs or after a repair visit."
	)
	_expect(
		NovaType.repair_warning_band(100.0, 100.0).is_empty()
			and NovaType.repair_warning_band(60.0, 100.0) == "yellow"
			and NovaType.repair_warning_band(25.0, 100.0) == "red",
		"Repair warning health bands do not match the yellow/red contract."
	)
	var root_file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	_expect(root_file != null, "Could not inspect repair-warning save persistence.")
	if root_file != null:
		var root_source := root_file.get_as_text()
		_expect(
			root_source.count("nova_repair_warning_rotation") >= 2,
			"Repair-warning round-robin cursor is not captured and restored with the campaign."
		)
	var ui_file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(ui_file != null, "Could not inspect repair-aware undock wiring.")
	if ui_file != null:
		var ui_source := ui_file.get_as_text()
		var undock_start := ui_source.find("func undock_player")
		var undock_end := ui_source.find("func _sell_ore", undock_start)
		var undock_source := ui_source.substr(undock_start, undock_end - undock_start) \
			if undock_start >= 0 and undock_end > undock_start else ""
		_expect(
			ui_source.contains("Nova.get_unrepaired_undock_warning")
				and ui_source.contains("_current_station_has_repair_services")
				and ui_source.contains("_repaired_this_dock = true")
				and ui_source.contains("Go to repairs")
				and ui_source.contains("Undock anyway"),
			"Undock does not keep damaged players docked for N.O.V.A.'s repair decision."
		)
		_expect(
			undock_source.find("_show_nova_repair_undock_prompt()") \
				< undock_source.find("AudioManager.exit_lounge_music()")
				and undock_source.contains("current_submenu = DockSubmenu.MAINTENANCE")
				and undock_source.contains("_render_dock_submenu()")
				and undock_source.contains("undock_player(true)"),
			"Repair prompt must block cleanup, enter Maintenance, or explicitly honor Undock anyway."
		)
		_expect(
			not undock_source.contains("LLMInterface"),
			"Repair warning flow must not start a model request at undock time."
		)
	gs.player = previous_player
	gs.nova_repair_warning_rotation = previous_rotation
	dummy_player.free()
	nova.free()


# Protected special bank: gate-glitch lines are only served on an explicit
# request, and the director-only memory flicker stays large-model-only.
func _test_gate_glitch_bank_is_protected() -> void:
	var nova: Node = NovaType.new()
	var empty_filter: Array[String] = []
	var glitch_filter: Array[String] = ["gate_glitch"]
	var arrival_filter: Array[String] = ["system_arrival"]
	_expect(
		bool(nova._line_kind_allowed("system_arrival", empty_filter)),
		"A normal kind should be served on an unfiltered request."
	)
	_expect(
		not bool(nova._line_kind_allowed("gate_glitch", empty_filter)),
		"A protected kind must never be served implicitly."
	)
	_expect(
		not bool(nova._line_kind_allowed("gate_glitch", arrival_filter)),
		"A protected kind must not ride along on another beat's filter."
	)
	_expect(
		bool(nova._line_kind_allowed("gate_glitch", glitch_filter)),
		"An explicit request for the protected kind should be honored."
	)
	nova.free()

	# The glitch pipeline itself: generated once per campaign on the large
	# model, leak-guarded line by line, with absence (not filler) on failure.
	var story_file := FileAccess.open(
		"res://scripts/story/StoryManager.gd", FileAccess.READ
	)
	var llm_file := FileAccess.open(
		"res://scripts/LLMInterface.gd", FileAccess.READ
	)
	_expect(
		story_file != null and llm_file != null,
		"Could not inspect the gate-glitch pipeline."
	)
	if story_file == null or llm_file == null:
		return
	var story_source := story_file.get_as_text()
	var llm_source := llm_file.get_as_text()
	_expect(
		story_source.contains("func _ensure_nova_glitch_hints")
			and story_source.contains("request_nova_glitch_hints")
			and story_source.contains("glitch_line_leaks_flicker")
			and story_source.contains("nova_memory_flicker"),
		"StoryManager gate-glitch pipeline lost its large-model/leak-guard path."
	)
	_expect(
		llm_source.contains("func request_nova_glitch_hints")
			and llm_source.contains("\"nova_glitch\"")
			and llm_source.contains(
				"HIDDEN DIRECTOR-ONLY FRAGMENT"
			),
		"LLMInterface glitch generation is no longer a guarded large-model call."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
