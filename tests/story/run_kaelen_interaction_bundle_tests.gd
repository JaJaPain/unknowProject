extends SceneTree

const KaelenKindsType := preload("res://scripts/story/KaelenInteractionKinds.gd")
const PacketBuilderType := preload(
	"res://scripts/story/KaelenInteractionPacketBuilder.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_test_phase_7_interaction_kinds_are_registered()
	_test_turn_in_and_reveal_groups_are_explicit()
	_test_existing_handoff_paths_use_interaction_constants()
	_test_story_manager_uses_scoped_handoff_pools()
	_test_kaelen_prompt_packet_includes_safe_context_without_secret_leaks()
	_test_live_kaelen_handoff_prompt_uses_safe_packet()
	_test_live_kaelen_prompts_do_not_read_protected_story_fields()
	_test_kaelen_reaction_bundle_is_mission_keyed()
	_test_kaelen_reaction_clarity_guard_blocks_unintroduced_next_tasks()

	if _failures.is_empty():
		print("[PASS] Kaelen interaction bundle tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_phase_7_interaction_kinds_are_registered() -> void:
	var expected: Array[String] = [
		"agent_handoff",
		"offer_comment",
		"acceptance_afterthought",
		"objective_complete_pending_turn_in",
		"turn_in_clean",
		"turn_in_rough",
		"turn_in_late",
		"partial_delivery",
		"abandon",
		"decline",
		"chapter_comment",
		"first_system_arrival",
	]
	var actual := KaelenKindsType.all()
	_expect(
		actual == expected,
		"Kaelen interaction kind registry does not match the Phase 7 contract."
	)
	for kind in expected:
		_expect(
			KaelenKindsType.is_valid(kind),
			"Registered Kaelen interaction kind was not valid: %s" % kind
		)
	_expect(
		not KaelenKindsType.is_valid("director_secret_reveal"),
		"Unknown Kaelen interaction kind was accepted."
	)


func _test_turn_in_and_reveal_groups_are_explicit() -> void:
	for kind in [
		"objective_complete_pending_turn_in",
		"turn_in_clean",
		"turn_in_rough",
		"turn_in_late",
		"partial_delivery",
		"abandon",
		"decline",
	]:
		_expect(
			KaelenKindsType.is_turn_in(kind),
			"Kaelen turn-in/mission-outcome kind missing from turn-in group: %s" %
				kind
		)
	for kind in [
		"agent_handoff",
		"offer_comment",
		"acceptance_afterthought",
		"chapter_comment",
		"first_system_arrival",
	]:
		_expect(
			not KaelenKindsType.is_turn_in(kind),
			"Non-turn-in Kaelen kind was treated as a turn-in: %s" % kind
		)
	for kind in [
		"objective_complete_pending_turn_in",
		"turn_in_clean",
		"turn_in_rough",
		"turn_in_late",
		"partial_delivery",
	]:
		_expect(
			KaelenKindsType.allows_safe_after_completion_reveal(kind),
			"Completion-safe aftermath reveal missing for kind: %s" % kind
		)
	for kind in ["agent_handoff", "offer_comment", "acceptance_afterthought"]:
		_expect(
			not KaelenKindsType.allows_safe_after_completion_reveal(kind),
			"Pre-completion Kaelen kind allowed aftermath reveal too early: %s" %
				kind
		)


func _test_existing_handoff_paths_use_interaction_constants() -> void:
	var game_root_file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	var ui_file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(
		game_root_file != null and ui_file != null,
		"Could not inspect existing Kaelen handoff constant wiring."
	)
	if game_root_file == null or ui_file == null:
		return
	var game_root_source := game_root_file.get_as_text()
	var ui_source := ui_file.get_as_text()
	_expect(
		game_root_source.contains("KaelenInteractionKindsType.AGENT_HANDOFF")
			and ui_source.contains("KaelenInteractionKindsType.AGENT_HANDOFF")
			and ui_source.contains("consume_cached_narrative_line_bank"),
		"Existing Kaelen handoff bank paths do not use the interaction-kind registry."
	)


func _test_story_manager_uses_scoped_handoff_pools() -> void:
	var file := FileAccess.open("res://scripts/story/StoryManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect StoryManager scoped handoff wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("draw_scoped")
			and source.contains("refill_scoped")
			and source.contains("pool_size_scoped")
			and source.contains("_kaelen_handoff_story_revision")
			and source.contains("_kaelen_handoff_system_id")
			and source.contains("_kaelen_handoff_relationship_band")
			and source.contains("_queue_handoff_pool_refill")
			and source.contains("queue_kaelen_handoff_pool_refill")
			and source.contains("refill_kaelen_handoff_pool_from_lines"),
		"StoryManager does not key Kaelen handoff pools by story/system/relationship scope."
	)


func _test_kaelen_prompt_packet_includes_safe_context_without_secret_leaks() -> void:
	var mission := _mission_fixture()
	var story_state := _story_state_fixture()
	var packet: Dictionary = PacketBuilderType.build_packet(
		KaelenKindsType.TURN_IN_CLEAN,
		mission,
		story_state,
		[_memory_fixture()],
		{"relationship_tier": "trusted"}
	)
	_expect(bool(packet.get("ok", false)), "Kaelen prompt packet did not build.")
	var mission_packet: Dictionary = packet.get("mission", {}) \
		if packet.get("mission", {}) is Dictionary else {}
	_expect(
		str(mission_packet.get("cause_id", "")) == "cause.city_attack"
			and str(mission_packet.get("stake", "")).contains("home city")
			and (mission_packet.get("asked_question_intents", []) as Array)
				.has("ask_risk")
			and str(mission_packet.get("accepted_terms", {}).get("choice_id", ""))
				== "choice.accept_standard",
		"Kaelen prompt packet did not include mission cause, stake, asked questions, and accepted terms."
	)
	_expect(
		bool(packet.get("allow_safe_after_completion_reveal", false))
			and str(packet.get("earned_aftermath", {}).get("world_consequence", ""))
				.contains("family district"),
		"Completion packet did not expose safe earned aftermath context."
	)
	_expect(
		str(packet.get("safe_kaelen_style", {}).get("kaelen_mood", ""))
			== "quietly relieved",
		"Kaelen packet did not include safe mood/style context."
	)
	_assert_no_secret_tokens(JSON.stringify(packet), "kaelen_prompt_packet")

	var pre_completion: Dictionary = PacketBuilderType.build_packet(
		KaelenKindsType.AGENT_HANDOFF,
		mission,
		story_state,
		[],
		{}
	)
	_expect(
		bool(pre_completion.get("ok", false))
			and not bool(pre_completion.get(
				"allow_safe_after_completion_reveal",
				true
			))
			and not pre_completion.has("earned_aftermath"),
		"Pre-completion Kaelen packet exposed aftermath context too early."
	)
	_expect(
		not bool(PacketBuilderType.build_packet(
			"invalid_kind",
			mission,
			story_state
		).get("ok", true)),
		"Invalid Kaelen interaction packet kind was accepted."
	)


func _test_live_kaelen_handoff_prompt_uses_safe_packet() -> void:
	var file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect LLMInterface Kaelen packet wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("KaelenInteractionPacketBuilderType.build_packet")
			and source.contains("KaelenInteractionKindsType.AGENT_HANDOFF")
			and source.contains("KaelenInteractionKindsType.TURN_IN_CLEAN")
			and source.contains("KaelenInteractionKindsType.ABANDON")
			and source.contains("safe earned aftermath may be mentioned only here")
			and source.contains("do not reveal completion aftermath here")
			and source.contains("Safe Kaelen interaction packet")
			and source.contains("_kaelen_interaction_packet_clause("),
		"Live Kaelen handoff/turn-in generation does not include the safe interaction packet."
	)


func _test_live_kaelen_prompts_do_not_read_protected_story_fields() -> void:
	var file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect LLMInterface Kaelen prompt safety.")
	if file == null:
		return
	var source := file.get_as_text()
	for forbidden in [
		"StoryManager.story_state.get(\"kaelen_hidden_angle\"",
		"StoryManager.story_state.get(\"player_does_not_know_yet\"",
		"StoryManager.story_state.get(\"kaelen_hidden_hints\"",
		"StoryManager.story_state.get(\"kaelen_never_reveal\"",
		"StoryManager.story_state[\"kaelen_hidden_angle\"]",
		"StoryManager.story_state[\"player_does_not_know_yet\"]",
		"StoryManager.story_state[\"kaelen_hidden_hints\"]",
		"StoryManager.story_state[\"kaelen_never_reveal\"]",
	]:
		_expect(
			not source.contains(forbidden),
			"Live Kaelen prompt code reads protected story field: %s" % forbidden
		)
	_expect(
		source.contains("Safe Kaelen interaction packet")
			and source.contains("_kaelen_interaction_packet_clause")
			and source.contains("Kaelen's current mood"),
		"Live Kaelen prompts are not limited to safe packet/context/mood inputs."
	)


func _test_kaelen_reaction_bundle_is_mission_keyed() -> void:
	var ui_file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	var quest_file := FileAccess.open("res://scripts/QuestManager.gd", FileAccess.READ)
	_expect(
		ui_file != null and quest_file != null,
		"Could not inspect Kaelen reaction bundle persistence wiring."
	)
	if ui_file == null or quest_file == null:
		return
	var ui_source := ui_file.get_as_text()
	var quest_source := quest_file.get_as_text()
	_expect(
		not ui_source.contains("cached_completion_line")
			and not ui_source.contains("cached_abandon_line")
			and ui_source.contains("store_active_kaelen_reaction_bundle")
			and ui_source.contains("active_kaelen_reaction_line(\"completion\")")
			and ui_source.contains("active_kaelen_reaction_line(\"abandon\")")
			and ui_source.contains("quest_objective_completed_details.connect")
			and ui_source.contains("_on_quest_objective_completed_details")
			and ui_source.contains("\"objective_complete\"")
			and ui_source.contains("kaelen_reaction_runtime_id")
			and quest_source.contains("func store_active_kaelen_reaction_bundle")
			and quest_source.contains("signal quest_objective_completed_details")
			and quest_source.contains("objective_complete_pending_turn_in")
			and quest_source.contains("_mark_objective_ready_if_completed")
			and quest_source.contains("\"kaelen_reaction_bundle\"")
			and quest_source.contains("mission_runtime_id")
			and quest_source.contains("func active_kaelen_reaction_line"),
		"Kaelen completion/abandon reactions are not stored as mission-keyed bundles."
	)


func _test_kaelen_reaction_clarity_guard_blocks_unintroduced_next_tasks() -> void:
	var file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	_expect(
		file != null,
		"Could not inspect LLMInterface Kaelen clarity guard."
	)
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("func _kaelen_reaction_player_clarity_issue")
			and source.contains("\"now fix\"")
			and source.contains("\"unexplained_next_task\"")
			and source.contains("\"relay\"")
			and source.contains("\"unintroduced_story_detail_\"")
			and source.contains("someone else has one less infrastructure problem")
			and source.contains("Never make the pilot responsible for that unseen problem"),
		"Kaelen clarity guard does not block unexplained next tasks while allowing generic resolved offscreen benefits."
	)
	_expect(
		not source.contains("Clean and Easy done? Good. Your credits hit my ledger"),
		"Screenshot regression text was accidentally hard-coded into production."
	)


func _mission_fixture() -> Dictionary:
	return {
		"runtime_id": "mission.runtime.kaelen_packet",
		"title": "Cut the Raid Vector",
		"objective_type": "KILL_SHIPS",
		"agent_name": "Agent X",
		"agent_id": "agent.x",
		"faction": "neutral",
		"story_thread_id": "thread.border_pressure",
		"story_beat_id": "beat.city_attack",
		"cause_id": "cause.city_attack",
		"stake": "Agent X's home city is exposed if the raiders regroup.",
		"conversation_asked_intents": ["ask_risk"],
		"conversation_learned_fact_ids": ["fact.raid_window.public"],
		"choice_id_selected": "choice.accept_standard",
		"choice_text_selected": "I'll take it.",
		"conversation_intent_id_selected": "accept_standard",
		"is_urgent": true,
		"is_timed": true,
		"deadline_time_minutes": 260,
		"narrative_metadata": {
			"public_because": "The raiders were staging outside the city lane.",
			"stake": "Agent X's home city is exposed if the raiders regroup.",
			"completion_fact_ids": ["fact.family_district_saved"],
			"outcome_snapshot": {
				"world_consequence": "The family district does not burn tonight.",
				"completion_status": "clean",
				"outcome_band": "saved_more_than_expected",
				"director_only_note": "SECRET_OUTCOME_DIRECTOR_TOKEN",
			},
			"director_only_fact_ids": ["SECRET_DIRECTOR_FACT_TOKEN"],
		},
	}


func _story_state_fixture() -> Dictionary:
	return {
		"chapter": 2,
		"active_tensions": ["The city lane is under pressure."],
		"player_knows": ["Agent X looked scared for personal reasons."],
		"kaelen_current_mood": "quietly relieved",
		"kaelen_hidden_angle": "SECRET_KAELEN_ANGLE_TOKEN",
		"kaelen_hidden_hints": ["SECRET_HINT_TOKEN"],
		"player_does_not_know_yet": ["SECRET_UNKNOWN_TRUTH_TOKEN"],
	}


func _memory_fixture() -> Dictionary:
	return {
		"memory_id": "memory.kaelen.0001",
		"category": "relationship",
		"summary": "Shiny asked why the family district mattered.",
		"fact_refs": ["fact.family_district_saved"],
		"director_note": "SECRET_MEMORY_DIRECTOR_TOKEN",
	}


func _assert_no_secret_tokens(source: String, label: String) -> void:
	for secret in [
		"SECRET_KAELEN_ANGLE_TOKEN",
		"SECRET_HINT_TOKEN",
		"SECRET_UNKNOWN_TRUTH_TOKEN",
		"SECRET_OUTCOME_DIRECTOR_TOKEN",
		"SECRET_DIRECTOR_FACT_TOKEN",
		"SECRET_MEMORY_DIRECTOR_TOKEN",
	]:
		_expect(
			not source.contains(secret),
			"%s leaked secret token: %s" % [label, secret]
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
