extends SceneTree

const KaelenKindsType := preload("res://scripts/story/KaelenInteractionKinds.gd")
const PacketBuilderType := preload(
	"res://scripts/story/KaelenInteractionPacketBuilder.gd"
)

var _failures: Array[String] = []
var StoryManagerType: GDScript = null


func _initialize() -> void:
	StoryManagerType = load("res://scripts/story/StoryManager.gd")
	_test_phase_7_interaction_kinds_are_registered()
	_test_turn_in_and_reveal_groups_are_explicit()
	_test_existing_handoff_paths_use_interaction_constants()
	_test_story_manager_uses_scoped_handoff_pools()
	_test_handoff_batches_are_serialized_and_deferred_for_campaign_bible()
	_test_kaelen_prompt_packet_includes_safe_context_without_secret_leaks()
	_test_kaelen_turn_in_outcome_profile_classifies_variants()
	_test_kaelen_relationship_events_drive_future_tone()
	_test_live_kaelen_handoff_prompt_uses_safe_packet()
	_test_live_kaelen_prompts_do_not_read_protected_story_fields()
	_test_kaelen_reaction_bundle_is_mission_keyed()
	_test_kaelen_reaction_clarity_guard_blocks_unintroduced_next_tasks()
	_test_kaelen_reaction_grounding_rejects_false_rescue_outcomes()
	_test_generated_kaelen_lines_use_quality_gate_without_touching_tutorial()

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


func _test_handoff_batches_are_serialized_and_deferred_for_campaign_bible() -> void:
	var file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect Kaelen handoff batch scheduling.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("_kaelen_handoff_batch_queue")
			and source.contains("_kaelen_handoff_batch_in_flight")
			and source.contains("func _process_next_kaelen_handoff_batch")
			and source.contains("if campaign_bible_priority_active:")
			and source.contains("Deferring Kaelen handoff batch while campaign bible is generating")
			and source.contains("func _finish_kaelen_handoff_batch")
			and source.contains("call_deferred(\"_process_next_kaelen_handoff_batch\")"),
		"Kaelen handoff batches are not serialized and deferred behind campaign-bible priority."
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
	var earned_aftermath: Dictionary = packet.get("earned_aftermath", {}) \
		if packet.get("earned_aftermath", {}) is Dictionary else {}
	var earned_visible_effect: Dictionary = earned_aftermath.get("visible_effect", {}) \
		if earned_aftermath.get("visible_effect", {}) is Dictionary else {}
	var earned_background: Dictionary = earned_aftermath.get("earned_background", {}) \
		if earned_aftermath.get("earned_background", {}) is Dictionary else {}
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
			and str(earned_aftermath.get("world_consequence", ""))
				.contains("family district")
			and bool(earned_visible_effect.get("has_visible_effect", false))
			and str(earned_visible_effect.get("effect_type", "")) == "people_safe",
		"Completion packet did not expose safe earned aftermath context."
	)
	_expect(
		bool(earned_background.get("can_reveal", false))
			and str(earned_background.get("background_text", ""))
				.contains("staging outside the city lane")
			and (earned_background.get("completion_fact_ids", []) as Array)
				.has("fact.family_district_saved")
			and str(earned_background.get("reveal_boundary", ""))
				.contains("Completion-only safe background"),
		"Completion packet did not expose bounded earned background."
	)
	_expect(
		str(packet.get("safe_kaelen_style", {}).get("kaelen_mood", ""))
			== "quietly relieved",
		"Kaelen packet did not include safe mood/style context."
	)
	_assert_no_secret_tokens(JSON.stringify(packet), "kaelen_prompt_packet")
	var outcome_profile: Dictionary = mission_packet.get("outcome_profile", {}) \
		if mission_packet.get("outcome_profile", {}) is Dictionary else {}
	var profile_visible_effect: Dictionary = outcome_profile.get("visible_effect", {}) \
		if outcome_profile.get("visible_effect", {}) is Dictionary else {}
	_expect(
		str(outcome_profile.get("turn_in_variant", ""))
			== KaelenKindsType.TURN_IN_CLEAN
			and str(outcome_profile.get("outcome_tone", ""))
				== "clean_with_story_fact"
			and bool(outcome_profile.get("learned_story_fact", false))
			and bool(profile_visible_effect.get("has_visible_effect", false)),
		"Kaelen packet did not classify a clean turn-in with story facts."
	)

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


func _test_kaelen_turn_in_outcome_profile_classifies_variants() -> void:
	var rough := _mission_fixture()
	rough["partial_delivery_count"] = 2
	rough["partial_delivered"] = 20.0
	var rough_packet: Dictionary = PacketBuilderType.build_packet(
		KaelenKindsType.TURN_IN_ROUGH,
		rough,
		_story_state_fixture()
	)
	var rough_mission: Dictionary = rough_packet.get("mission", {}) \
		if rough_packet.get("mission", {}) is Dictionary else {}
	var rough_profile: Dictionary = rough_mission.get("outcome_profile", {}) \
		if rough_mission.get("outcome_profile", {}) is Dictionary else {}
	var rough_partial: Dictionary = rough_profile.get("partial_delivery", {}) \
		if rough_profile.get("partial_delivery", {}) is Dictionary else {}
	_expect(
		str(rough_profile.get("turn_in_variant", ""))
			== KaelenKindsType.TURN_IN_ROUGH
			and bool(rough_partial.get("completed_in_multiple_drops", false)),
		"Kaelen outcome profile did not classify multiple partial deliveries as rough."
	)

	var late := _mission_fixture()
	late["objective_completed_time_minutes"] = 300
	late["deadline_time_minutes"] = 260
	var late_packet: Dictionary = PacketBuilderType.build_packet(
		KaelenKindsType.TURN_IN_LATE,
		late,
		_story_state_fixture()
	)
	var late_mission: Dictionary = late_packet.get("mission", {}) \
		if late_packet.get("mission", {}) is Dictionary else {}
	var late_profile: Dictionary = late_mission.get("outcome_profile", {}) \
		if late_mission.get("outcome_profile", {}) is Dictionary else {}
	var late_timing: Dictionary = late_profile.get("timing", {}) \
		if late_profile.get("timing", {}) is Dictionary else {}
	_expect(
		str(late_profile.get("turn_in_variant", ""))
			== KaelenKindsType.TURN_IN_LATE
			and str(late_timing.get("label", "")) == "late",
		"Kaelen outcome profile did not classify late completion."
	)


func _test_kaelen_relationship_events_drive_future_tone() -> void:
	_expect(
		StoryManagerType != null and StoryManagerType.can_instantiate(),
		"Could not instantiate StoryManager for Kaelen relationship continuity."
	)
	if StoryManagerType == null or not StoryManagerType.can_instantiate():
		return
	var manager: Node = StoryManagerType.new()
	manager.story_state = {
		"mission_history_revision": 0,
		"kaelen_current_mood": "guarded",
		"kaelen_relationship": {
			"respect": 0,
			"band": "neutral",
			"revision": 0,
			"last_outcome": "",
			"last_mission_title": "",
			"recent_reason": "",
			"last_changed_minute": 0,
		},
	}
	manager.increment_mission_history_revision(
		"completed",
		{"title": "Clean Win", "runtime_id": "mission.relationship.1"}
	)
	manager.increment_mission_history_revision(
		"declined",
		{
			"title": "Not Today",
			"runtime_id": "mission.relationship.2",
			"decline_reason": "choice.decline",
		}
	)
	manager.increment_mission_history_revision(
		"abandoned",
		{
			"title": "Dropped Cargo",
			"runtime_id": "mission.relationship.3",
			"outcome_detail": "walked_away",
		}
	)
	var relationship: Dictionary = manager.kaelen_relationship_state()
	_expect(
		int(relationship.get("respect", 0)) == -2
			and str(relationship.get("band", "")) == "wary"
			and int(relationship.get("revision", 0)) == 3
			and str(relationship.get("last_outcome", "")) == "abandoned"
			and str(relationship.get("last_mission_title", "")) == "Dropped Cargo"
			and manager.kaelen_relationship_band() == "wary"
			and manager.call("_kaelen_handoff_relationship_band", "Agent X") == "wary",
		"Kaelen relationship state did not preserve decline/abandon continuity."
	)

	var story_state := _story_state_fixture()
	story_state["kaelen_relationship"] = relationship
	var packet: Dictionary = PacketBuilderType.build_packet(
		KaelenKindsType.ABANDON,
		_mission_fixture(),
		story_state
	)
	var style: Dictionary = packet.get("safe_kaelen_style", {}) \
		if packet.get("safe_kaelen_style", {}) is Dictionary else {}
	_expect(
		str(style.get("relationship_tier", "")) == "wary"
			and int(style.get("relationship_respect", 0)) == -2
			and str(style.get("last_contract_outcome", "")) == "abandoned",
		"Kaelen packet style did not receive relationship continuity."
	)
	manager.free()


func _test_live_kaelen_handoff_prompt_uses_safe_packet() -> void:
	var file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect LLMInterface Kaelen packet wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("KaelenInteractionPacketBuilderType.build_packet")
			and source.contains("KaelenInteractionKindsType.AGENT_HANDOFF")
			and source.contains("turn_in_kind_for_mission")
			and source.contains("outcome_profile")
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
	var game_root_file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	_expect(
		ui_file != null and quest_file != null and game_root_file != null,
		"Could not inspect Kaelen reaction bundle persistence wiring."
	)
	if ui_file == null or quest_file == null or game_root_file == null:
		return
	var ui_source := ui_file.get_as_text()
	var quest_source := quest_file.get_as_text()
	var game_root_source := game_root_file.get_as_text()
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
	_expect(
		ui_source.contains("func _record_kaelen_line_playback")
			and ui_source.contains("record_kaelen_line_playback")
			and ui_source.contains("mission_completion")
			and ui_source.contains("mission_abandon")
			and ui_source.contains("agent_handoff")
			and game_root_source.contains("func record_kaelen_line_playback")
			and game_root_source.contains("\"kaelen_line_delivered\"")
			and game_root_source.contains("\"line_fingerprint\"")
			and game_root_source.contains("campaign_kaelen_memory_store.append_memory"),
		"Kaelen delivered lines are not recorded as chronicle/memory playback events."
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
			and source.contains("func _kaelen_reaction_task_anchor_issue")
			and source.contains("missing_task_anchor:")
			and source.contains("func _kaelen_reaction_claims_generic_safety")
			and source.contains("generic_safety_outcome")
			and source.contains("\"DELIVER_ORE\"")
			and source.contains("\"ore\", \"delivery\"")
			and source.contains("\"now fix\"")
			and source.contains("\"unexplained_next_task\"")
			and source.contains("\"relay\"")
			and source.contains("\"unintroduced_story_detail_\"")
			and source.contains("someone else has one less infrastructure problem")
			and source.contains("Never make the pilot responsible for that unseen problem"),
		"Kaelen clarity guard does not ground outcomes in the actual task or block generic rescue language."
	)
	_expect(
		source.contains("keep any warmth understated")
			and source.contains("return to broker business")
			and source.contains("never emotionally confessional or sentimental")
			and not source.contains("let a little heart show for one beat"),
		"Kaelen completion prompt does not preserve the understated broker voice constraint."
	)
	_expect(
		source.contains("earned_aftermath.visible_effect.has_visible_effect")
			and source.contains("name that effect once in plain language")
			and source.contains("do not invent shields, convoys, contacts, evidence"),
		"Kaelen completion prompt does not gate visible-effect naming on the safe packet."
	)
	_expect(
		source.contains("earned_aftermath.earned_background.can_reveal")
			and source.contains("one short plain-language clause")
			and source.contains("never add secret motives, identities, origins"),
		"Kaelen completion prompt does not bound earned background reveals."
	)
	_expect(
		not source.contains("Clean and Easy done? Good. Your credits hit my ledger"),
		"Screenshot regression text was accidentally hard-coded into production."
	)


func _test_kaelen_reaction_grounding_rejects_false_rescue_outcomes() -> void:
	var interface := get_root().get_node_or_null("LLMInterface")
	_expect(
		interface != null and interface.has_method("_kaelen_reaction_player_clarity_issue"),
		"Live LLMInterface clarity guard is unavailable for Kaelen grounding checks."
	)
	if interface == null or not interface.has_method("_kaelen_reaction_player_clarity_issue"):
		return
	var ore_quest := {
		"objective": {"type": "DELIVER_ORE", "amount_required": 20},
		"narrative_metadata": {"outcome_snapshot": {}},
	}
	var false_rescue := str(interface.call(
		"_kaelen_reaction_player_clarity_issue",
		"The ore delivery is logged. They're safe now.", ore_quest, "completion"
	))
	_expect(
		false_rescue == "generic_safety_outcome",
		"Ore delivery must reject a generic rescue/safety conclusion: %s" % false_rescue
	)
	var generic_completion := str(interface.call(
		"_kaelen_reaction_player_clarity_issue",
		"Contract closed. Credits are clear.", ore_quest, "completion"
	))
	_expect(
		generic_completion == "missing_task_anchor:deliver_ore",
		"Kaelen completion must name the actual ore/delivery work: %s" % generic_completion
	)
	var safe_outcome := ore_quest.duplicate(true)
	safe_outcome["narrative_metadata"]["outcome_snapshot"] = {
		"world_consequence": "The evacuation lanes are safe again.",
	}
	var still_generic := str(interface.call(
		"_kaelen_reaction_player_clarity_issue",
		"The ore delivery is in. They're safe now, and the credits cleared.",
		safe_outcome,
		"completion"
	))
	_expect(
		still_generic == "generic_safety_outcome",
		"An earned outcome must not license Kaelen's generic rescue wording: %s" % still_generic
	)
	var concrete_aftermath := str(interface.call(
		"_kaelen_reaction_player_clarity_issue",
		"The ore delivery is in. Those evacuation lanes stay open, and the credits cleared.",
		safe_outcome,
		"completion"
	))
	_expect(
		concrete_aftermath.is_empty(),
		"Kaelen should be allowed to reveal the concrete earned aftermath: %s" % concrete_aftermath
	)


func _test_generated_kaelen_lines_use_quality_gate_without_touching_tutorial() -> void:
	var ui_file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	var root_file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	_expect(
		ui_file != null and root_file != null,
		"Could not inspect Kaelen campaign quality-gate wiring."
	)
	if ui_file == null or root_file == null:
		return
	var ui_source := ui_file.get_as_text()
	var root_source := root_file.get_as_text()
	ui_file.close()
	root_file.close()
	var request_start := ui_source.find("func _request_kaelen_reaction_bundle_for_mission")
	var request_end := ui_source.find("\nfunc ", request_start + 10)
	var request_body := ui_source.substr(request_start, request_end - request_start)
	_expect(
		request_body.contains("_validate_generated_narrative_lines")
			and request_body.contains("kaelen_reaction")
			and request_body.find("_validate_generated_narrative_lines")
				< request_body.find("store_active_kaelen_reaction_bundle"),
		"Generated Kaelen reaction bundles are stored before campaign quality validation."
	)
	_expect(
		root_source.contains("func _accept_generated_kaelen_bank_line")
			and root_source.contains("kaelen_bank:%s")
			and request_body.contains("is_intro_tutorial_contract")
			and request_body.find("is_intro_tutorial_contract")
				< request_body.find("_validate_generated_narrative_lines"),
		"Kaelen quality gate must cover generated lines while preserving authored tutorial reactions."
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
