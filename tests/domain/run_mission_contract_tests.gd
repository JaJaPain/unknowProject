extends SceneTree

const DefinitionType := preload(
	"res://scripts/domain/MissionDefinition.gd"
)
const AdapterType := preload(
	"res://scripts/domain/MissionAdapter.gd"
)
const PublicBoardOfferBuilderType := preload(
	"res://scripts/domain/PublicBoardOfferBuilder.gd"
)
const PublicBoardTextGeneratorType := preload(
	"res://scripts/domain/PublicBoardTextGenerator.gd"
)
const MissionCapabilityRegistryType := preload(
	"res://scripts/domain/MissionCapabilityRegistry.gd"
)
const MissionTemplateRegistryType := preload(
	"res://scripts/domain/MissionTemplateRegistry.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_test_ore_offer()
	_test_kill_offer()
	_test_agent_voice_profile_survives_acceptance()
	_test_selected_choice_id_survives_acceptance()
	_test_selected_choice_id_defaults_from_offer_position()
	_test_narrative_metadata_survives_acceptance_and_restore()
	_test_pickup_offer()
	_test_delivery_courier_offer()
	_test_purchase_delivery_offer()
	_test_recovery_offer()
	_test_generated_faction_display_name()
	_test_timed_offer()
	_test_agent_templates_cover_implemented_capabilities()
	_test_public_board_text_generation()
	_test_public_board_story_intents_prioritize_offers()
	_test_malformed_narrative_metadata_rejected()
	_test_malformed_offers()
	_test_legacy_runtime_state()
	_test_authored_tutorial_offer_loads_and_can_complete()
	_test_delivery_purchase_legacy_runtime_state()
	_test_invalid_runtime_state()

	if _failures.is_empty():
		print("[PASS] Mission contract tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_ore_offer() -> void:
	var adapted := AdapterType.build_active_state(
		_offer(
			"Ore Run",
			"zenith",
			"Director Voss",
			{
				"type": "DELIVER_ORE",
				"amount_required": 30.0,
				"reward_credits": 120,
			}
		),
		_choice(10, {"zenith": 2.0}, 1.0, 1.25),
		"mission.runtime.ore_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid ore offer failed validation."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		state.get("objective_type") == "DELIVER_ORE"
			and is_equal_approx(float(state.get("amount_required")), 30.0)
			and int(state.get("reward_credits")) == 120
			and is_equal_approx(
				float(state.get("reward_credits_multiplier")),
				1.25
			),
		"Ore offer did not produce the compatible runtime shape."
	)


func _test_kill_offer() -> void:
	var adapted := AdapterType.build_active_state(
		_offer(
			"Patrol Sweep",
			"vanguard",
			"Captain Dask",
			{
				"type": "KILL_SHIPS",
				"target_faction": "reavers",
				"count_required": 3,
				"reward_credits": 200,
			}
		),
		_choice(0, {}, 1.5, 1.0),
		"mission.runtime.kill_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid kill offer failed validation."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		state.get("objective_type") == "KILL_SHIPS"
			and state.get("target_faction") == "reavers"
			and state.get("target_faction_display") == "Reavers"
			and int(state.get("count_required")) == 4
			and int(state.get("current_count")) == 0,
		"Kill offer did not apply its combat multiplier correctly."
	)


func _test_agent_voice_profile_survives_acceptance() -> void:
	var offer := _offer(
		"Agent Voice Contract",
		"aurelia",
		"Liaison Ryn",
		{
			"type": "DELIVER_ORE",
			"amount_required": 18.0,
			"reward_credits": 140,
		}
	)
	offer["agent_voice_profile_id"] = "voice.agent.liaison_ryn.v1"
	var adapted := AdapterType.build_active_state(
		offer,
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.voice_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Voice-profile offer failed validation."
	)
	_expect(
		adapted["state"].get("agent_voice_profile_id", "")
			== "voice.agent.liaison_ryn.v1",
		"Agent voice profile was not preserved on accepted mission state."
	)


func _test_selected_choice_id_survives_acceptance() -> void:
	var offer := _offer(
		"Choice ID Contract",
		"zenith",
		"Director Voss",
		{
			"type": "DELIVER_ORE",
			"amount_required": 12.0,
			"reward_credits": 90,
		}
	)
	var selected := _choice(
		0,
		{"zenith": 1.0},
		1.0,
		1.0,
		"choice.accept_standard"
	)
	offer["choices"] = [selected]
	var adapted := AdapterType.build_active_state(
		offer,
		selected,
		"mission.runtime.choice_id_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Choice-ID offer failed validation."
	)
	_expect(
		adapted["state"].get("choice_id_selected", "")
			== "choice.accept_standard"
			and adapted["state"].get("choice_text_selected", "") == "Accepted.",
		"Accepted mission did not preserve selected choice ID and text."
	)


func _test_selected_choice_id_defaults_from_offer_position() -> void:
	var offer := _offer(
		"Choice Position Contract",
		"aurelia",
		"Liaison Ryn",
		{
			"type": "DELIVER_ORE",
			"amount_required": 14.0,
			"reward_credits": 95,
		}
	)
	var first := _choice(0, {}, 1.0, 1.0)
	var selected := _choice(5, {"aurelia": 1.0}, 1.0, 1.1)
	offer["choices"] = [first, selected]
	var adapted := AdapterType.build_active_state(
		offer,
		selected,
		"mission.runtime.choice_position_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Choice-position offer failed validation."
	)
	_expect(
		adapted["state"].get("choice_id_selected", "") == "choice.selected_01",
		"Accepted mission did not derive a stable selected choice ID."
	)


func _test_narrative_metadata_survives_acceptance_and_restore() -> void:
	var offer := _offer(
		"Narrative Thread Contract",
		"vanguard",
		"Captain Dask",
		{
			"type": "KILL_SHIPS",
			"target_faction": "reavers",
			"count_required": 2,
			"reward_credits": 180,
		}
	)
	offer["story_hook_ref"] = "hook:legacyabc123"
	offer["narrative_metadata"] = {
		"offer_id": "offer.narrative.alpha",
		"story_thread_id": "thread.alpha",
		"story_beat_id": "beat.opening",
		"cause_id": "cause.reaver_pressure",
		"public_because": "Reaver pressure is rising near the shipping lane.",
		"stake": "Keep the dock route open.",
		"question_fact_ids": ["fact.reaver_pressure"],
		"completion_fact_ids": ["fact.route_safe"],
		"conversation_cache_key": "conversation.cache.alpha",
		"conversation_state": "briefed",
		"outcome_snapshot": {"route": "safer"},
	}
	var adapted := AdapterType.build_active_state(
		offer,
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.narrative_metadata_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Narrative metadata offer failed validation."
	)
	var definition = adapted["definition"]
	var state: Dictionary = adapted["state"]
	var metadata: Dictionary = state.get("narrative_metadata", {})
	_expect(
		definition.narrative_metadata.get("offer_id", "") == "offer.narrative.alpha",
		"Narrative metadata did not survive offer -> definition."
	)
	_expect(
		metadata.get("story_hook_ref", "") == "hook:legacyabc123"
				and state.get("story_hook_ref", "") == "hook:legacyabc123",
		"Narrative metadata did not preserve legacy story_hook_ref on active state."
	)
	_expect(
		(metadata.get("question_fact_ids", []) as Array).size() == 1
				and metadata.get("outcome_snapshot", {}) is Dictionary,
		"Narrative metadata arrays/dictionaries did not survive active state."
	)
	var restored = MissionInstance.from_dict(MissionInstance.create_active(state).to_dict())
	_expect(
		restored.data.get("narrative_metadata", {}).get("cause_id", "")
				== "cause.reaver_pressure",
		"Narrative metadata did not survive mission instance restore."
	)
	var normalized := AdapterType.normalize_legacy_state(restored.data)
	_expect(
		normalized.get("narrative_metadata", {}).get("completion_fact_ids", []) is Array
				and normalized.get("completion_fact_ids", []) is Array,
		"Narrative metadata did not survive legacy normalization."
	)


func _test_malformed_narrative_metadata_rejected() -> void:
	var offer := _offer(
		"Bad Metadata Contract",
		"vanguard",
		"Captain Dask",
		{
			"type": "KILL_SHIPS",
			"target_faction": "reavers",
			"count_required": 2,
			"reward_credits": 180,
		}
	)
	offer["narrative_metadata"] = {
		"story_thread_id": "bad id with spaces",
		"question_fact_ids": "fact.should_be_array",
		"outcome_snapshot": [],
	}
	var adapted := AdapterType.build_active_state(
		offer,
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.bad_narrative_metadata_test",
		"start_system"
	)
	_expect(
		not adapted["validation"].is_valid(),
		"Malformed narrative metadata offer was accepted."
	)
	_expect(
		not AdapterType.validate_active_state(
			AdapterType.normalize_legacy_state({
				"runtime_id": "mission.runtime.bad_narrative_metadata_state",
				"definition_id": "mission.offer.bad_narrative_metadata_state",
				"title": "Bad Metadata State",
				"faction": "vanguard",
				"objective_type": "KILL_SHIPS",
				"reward_credits": 180,
				"target_faction": "reavers",
				"count_required": 2,
				"current_count": 0,
				"narrative_metadata": {"completion_fact_ids": [12]},
			})
		).is_valid(),
		"Malformed narrative metadata saved state was accepted."
	)


func _test_pickup_offer() -> void:
	var adapted := AdapterType.build_active_state(
		_offer(
			"Coupler Retrieval",
			"neutral",
			"Jenna Kross",
			{
				"type": "PICKUP_SPECIAL",
				"target_outpost": "kova",
				"target_outpost_display": "Kova Station",
				"target_npc": "Cassen Vane",
				"part_name": "Plasma Coupler",
				"destination": "Grease Monkeys",
				"reward_credits": 75,
			}
		),
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.pickup_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid pickup offer failed validation."
	)
	var definition = adapted["definition"]
	var state: Dictionary = adapted["state"]
	_expect(
		str(definition.giver_npc_id) == "npc.jenna_kross"
			and state.get("target_outpost") == "kova"
			and state.get("part_name") == "Plasma Coupler"
			and not bool(state.get("picked_up")),
		"Pickup offer lost stable giver or objective fields."
	)


func _test_delivery_courier_offer() -> void:
	var adapted := AdapterType.build_active_state(
		_offer(
			"Sealed Courier Run",
			"neutral",
			"Public Board",
			{
				"type": "DELIVERY_COURIER",
				"item_name": "Sealed Evidence Tube",
				"origin_station_id": "start_system",
				"origin_display": "Main Station",
				"destination_station_id": "kova",
				"destination_display": "Kova Station",
				"reward_credits": 160,
			}
		),
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.delivery_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid courier offer failed validation."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		state.get("objective_type") == "DELIVERY_COURIER"
			and state.get("item_name") == "Sealed Evidence Tube"
			and state.get("destination_station_id") == "kova"
			and bool(state.get("cargo_loaded", false)),
		"Courier offer did not produce delivery runtime fields."
	)


func _test_purchase_delivery_offer() -> void:
	var adapted := AdapterType.build_active_state(
		_offer(
			"Procurement Run",
			"neutral",
			"Public Board",
			{
				"type": "PURCHASE_DELIVERY",
				"item_id": "data_chip",
				"item_name": "Data Chip",
				"quantity_required": 1,
				"store_station_id": "haven",
				"store_display": "Main Station",
				"destination_station_id": "start_system",
				"destination_display": "Main Station",
				"reward_credits": 130,
			}
		),
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.purchase_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid purchase-delivery offer failed validation."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		state.get("objective_type") == "PURCHASE_DELIVERY"
			and state.get("item_id") == "data_chip"
			and int(state.get("quantity_required")) == 1,
		"Purchase offer did not produce inventory runtime fields."
	)


func _test_recovery_offer() -> void:
	var adapted := AdapterType.build_active_state(
		_offer(
			"Data Pack Recovery",
			"neutral",
			"Public Board",
			{
				"type": "RECOVER_COMBAT_DROP",
				"target_faction": "reavers",
				"count_required": 3,
				"drop_chance": 0.33,
				"item_name": "data pack",
				"turn_in_location": "main station",
				"reward_credits": 840,
			}
		),
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.recovery_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid recovery offer failed validation."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		state.get("objective_type") == "RECOVER_COMBAT_DROP"
			and state.get("target_faction") == "reavers"
			and state.get("target_faction_display") == "Reavers"
			and int(state.get("count_required")) == 3
			and is_equal_approx(float(state.get("drop_chance")), 0.33)
			and state.get("item_name") == "data pack"
			and not bool(state.get("ship_log_recovered", false)),
		"Recovery offer did not produce random-drop ship-log mission state."
	)


func _test_generated_faction_display_name() -> void:
	var adapted := AdapterType.build_active_state(
		_offer(
			"Generated Patrol Sweep",
			"neutral",
			"Latch Parish Juno Marl",
			{
				"type": "KILL_SHIPS",
				"target_faction": "gen_latch_parish_02",
				"count_required": 2,
				"reward_credits": 200,
			}
		),
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.generated_faction_test",
		"system.generated.test"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Generated faction offer failed validation."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		state.get("target_faction") == "gen_latch_parish_02"
			and state.get("target_faction_display") == "Latch Parish",
		"Generated faction display leaked raw ID: %s" %
			str(state.get("target_faction_display", ""))
	)


func _test_timed_offer() -> void:
	var offer := _offer(
		"Urgent Parts Run",
		"neutral",
		"Jenna Kross",
		{
			"type": "PICKUP_SPECIAL",
			"target_outpost": "iron_reach",
			"target_outpost_display": "Outpost Iron Reach",
			"target_npc": "Alaric Venn",
			"part_name": "Sealed Actuator",
			"destination": "Grease Monkeys",
			"reward_credits": 225,
		}
	)
	offer["timing"] = {
		"timed": true,
		"urgent": true,
		"duration_minutes": 180,
		"expiration_policy": "expire",
		"urgent_reward_multiplier": 1.5,
	}
	var adapted := AdapterType.build_active_state(
		offer,
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.timed_test",
		"start_system",
		480
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid timed offer failed validation."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		bool(state.get("is_timed", false))
			and bool(state.get("is_urgent", false))
			and int(state.get("accepted_time_minutes", 0)) == 480
			and int(state.get("deadline_time_minutes", 0)) == 660
			and is_equal_approx(
				float(state.get("urgent_reward_multiplier", 0.0)),
				1.5
			),
		"Timed offer did not produce campaign-time deadline metadata."
	)


func _test_public_board_text_generation() -> void:
	var offers := PublicBoardOfferBuilderType.build_offers(480)
	_expect(offers.size() >= 4, "Public board did not build varied offers.")
	_expect(
		_has_offer_template(
			offers,
			"DELIVERY_COURIER_PUBLIC"
		),
		"Public board did not include a courier offer."
	)
	_expect(
		_has_offer_template(
			offers,
			"PURCHASE_DELIVERY_PUBLIC"
		),
		"Public board did not include a purchase-delivery offer."
	)
	for generated_offer in offers:
		var rendered_offer := PublicBoardTextGeneratorType.fallback_offer(
			generated_offer,
			1
		)
		var generated_quest: Dictionary = rendered_offer.get("quest_data", {})
		var adapted_generated := AdapterType.build_active_state(
			generated_quest,
			generated_quest.get("choices", [])[0],
			"mission.runtime.board_%s" % str(
				generated_offer.get("template_id", "")
			).sha256_text().substr(0, 8),
			"start_system",
			480
		)
		_expect(
			adapted_generated["validation"].is_valid(),
			"Public-board offer failed active-state validation: %s" % str(
				generated_offer.get("template_id", "")
			)
		)
	var offer: Dictionary = offers[0]
	var request := PublicBoardTextGeneratorType.build_generation_request(offer)
	_expect(
		str(request.get("prompt", "")).contains("{ORE_AMOUNT}")
			and str(request.get("prompt", "")).contains("{TURN_IN_LOCATION}"),
		"Public-board LLM request did not include required placeholders."
	)
	var rendered := PublicBoardTextGeneratorType.fallback_offer(offer, 0)
	_expect(
		not str(rendered.get("title", "")).contains("{ORE_AMOUNT}")
			and not str(rendered.get("body", "")).contains("{ORE_AMOUNT}"),
		"Public-board fallback offer did not render code-owned placeholders."
	)
	var quest_data: Dictionary = rendered.get("quest_data", {})
	_expect(
		bool(quest_data.get("public_board", false))
			and str(quest_data.get("public_board_turn_in_line", "")).length() > 0,
		"Public-board fallback did not attach turn-in metadata."
	)
	var adapted := AdapterType.build_active_state(
		quest_data,
		quest_data.get("choices", [])[0],
		"mission.runtime.public_board_text_test",
		"start_system",
		480
	)
	_expect(
		adapted["validation"].is_valid()
			and bool(adapted["state"].get("public_board", false))
			and str(adapted["state"].get("public_board_turn_in_line", "")).length() > 0,
		"Public-board metadata did not survive active mission adaptation."
	)
	var missing_placeholder := {
		"title": "Ore job",
		"poster": "Someone",
		"body": "Bring ore.",
		"briefing": "Bring ore.",
		"kaelen_turn_in": "I processed the payout. Public board work, really?",
	}
	_expect(
		not bool(
			PublicBoardTextGeneratorType.validate_payload(
				offer,
				missing_placeholder
			).get("ok", false)
		),
		"Public-board text accepted output missing required placeholders."
	)
	var authorship_payload := PublicBoardTextGeneratorType.fallback_payload(
		offer,
		0
	)
	authorship_payload["kaelen_turn_in"] = (
		"I posted my contract for {ORE_AMOUNT} to {TURN_IN_LOCATION}."
	)
	_expect(
		not bool(
			PublicBoardTextGeneratorType.validate_payload(
				offer,
				authorship_payload
			).get("ok", false)
		),
		"Public-board text accepted Kaelen authorship drift."
	)


func _test_agent_templates_cover_implemented_capabilities() -> void:
	var expected := {
		MissionTemplateRegistryType.TEMPLATE_DELIVERY_COURIER_AGENT: "DELIVERY_COURIER",
		MissionTemplateRegistryType.TEMPLATE_PURCHASE_DELIVERY_AGENT: "PURCHASE_DELIVERY",
		MissionTemplateRegistryType.TEMPLATE_RECOVER_COMBAT_DROP_AGENT: "RECOVER_COMBAT_DROP",
		MissionTemplateRegistryType.TEMPLATE_TARGET_WITH_COMMS_REVERSAL_AGENT: "TARGET_WITH_COMMS_REVERSAL",
	}
	for template_id in expected.keys():
		var template = MissionTemplateRegistryType.get_template(str(template_id))
		_expect(
			template != null,
			"Missing agent template: %s" % str(template_id)
		)
		if template == null:
			continue
		_expect(
			template.source_lane == "AGENT"
				and template.objective_type == str(expected[template_id]),
			"Agent template %s has wrong lane/objective." % str(template_id)
		)


func _test_public_board_story_intents_prioritize_offers() -> void:
	var config: SystemConfig = SystemConfig.new()
	config.system_id = "story_intent_test"
	config.story_pack = {
		"system_id": "story_intent_test",
		"mission_intents": ["purchase", "delivery", "combat"],
		"mission_seeds": [],
	}
	PublicBoardOfferBuilderType.story_config_override_for_tests = config
	var offers: Array[Dictionary] = PublicBoardOfferBuilderType.build_offers(480)
	PublicBoardOfferBuilderType.story_config_override_for_tests = null
	_expect(
		offers.size() >= 2,
		"Story-intent board did not build enough offers."
	)
	_expect(
		str(offers[0].get("template_id", "")) == "PURCHASE_DELIVERY_PUBLIC",
		"Story intent did not promote purchase offer first."
	)
	_expect(
		str(offers[1].get("template_id", "")) == "DELIVERY_COURIER_PUBLIC",
		"Story intent did not promote delivery offer second."
	)


func _test_malformed_offers() -> void:
	var bad_type := _offer(
		"Impossible",
		"zenith",
		"Director Voss",
		{"type": "LAND_ON_PLANET", "reward_credits": 10}
	)
	_expect(
		not DefinitionType.new().load_from_offer(bad_type).is_valid(),
		"Unsupported objective type was accepted."
	)

	var missing_pickup := _offer(
		"Missing Cargo",
		"neutral",
		"Jenna Kross",
		{
			"type": "PICKUP_SPECIAL",
			"target_outpost": "kova",
			"reward_credits": 10,
		}
	)
	_expect(
		not DefinitionType.new().load_from_offer(missing_pickup).is_valid(),
		"Incomplete pickup objective was accepted."
	)

	var negative_reward := _offer(
		"Debt Trap",
		"zenith",
		"Director Voss",
		{
			"type": "DELIVER_ORE",
			"amount_required": 10,
			"reward_credits": -50,
		}
	)
	_expect(
		not DefinitionType.new().load_from_offer(negative_reward).is_valid(),
		"Negative mission reward was accepted."
	)

	var bad_timing := _offer(
		"Broken Timer",
		"zenith",
		"Director Voss",
		{
			"type": "DELIVER_ORE",
			"amount_required": 10,
			"reward_credits": 50,
		}
	)
	bad_timing["timing"] = {
		"timed": true,
		"duration_minutes": 0,
	}
	_expect(
		not DefinitionType.new().load_from_offer(bad_timing).is_valid(),
		"Timed mission without positive duration was accepted."
	)


func _test_legacy_runtime_state() -> void:
	var normalized := AdapterType.normalize_legacy_state({
		"title": "Legacy Ore",
		"faction": "zenith",
		"objective_type": "DELIVER_ORE",
		"amount_required": 40.0,
		"partial_delivered": 11.0,
	})
	_expect(
		AdapterType.validate_active_state(normalized).is_valid(),
		"Valid legacy runtime state did not normalize."
	)
	_expect(
		str(normalized.get("runtime_id", "")).begins_with("mission.legacy.")
			and str(normalized.get("definition_id", "")).begins_with(
				"mission.offer."
			)
			and int(normalized.get("mission_schema_version", 0)) == 1,
		"Legacy runtime state did not receive typed identity metadata."
	)
	var metadata: Dictionary = normalized.get("narrative_metadata", {})
	_expect(
		metadata.get("offer_id", "") == ""
			and metadata.get("story_hook_ref", "") == ""
			and metadata.get("question_fact_ids", []) is Array
			and (metadata.get("question_fact_ids", []) as Array).is_empty()
			and metadata.get("outcome_snapshot", {}) is Dictionary
			and (metadata.get("outcome_snapshot", {}) as Dictionary).is_empty(),
		"Legacy runtime state did not receive empty narrative metadata defaults."
	)


func _test_authored_tutorial_offer_loads_and_can_complete() -> void:
	var tutorial_offer := {
		"title": "Clean and Easy",
		"faction": "neutral",
		"agent_name": "Broker Kaelen",
		"dialogue": "One Reaver problem. Handle it quiet.",
		"objective": {
			"type": "KILL_SHIPS",
			"target_faction": "reavers",
			"count_required": 1,
			"reward_credits": 350,
		},
		"choices": [],
		"time_limit_min": 20.0,
	}
	var adapted := AdapterType.build_active_state(
		tutorial_offer,
		{
			"text": "I'll take it.",
			"consequence": {
				"credits_immediate": 0,
				"reputation_change": {},
				"reward_credits_multiplier": 1.0,
			},
		},
		"mission.runtime.clean_easy_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Authored tutorial offer failed acceptance validation."
	)
	var restored: Dictionary = AdapterType.normalize_legacy_state(
		JSON.parse_string(JSON.stringify(adapted["state"]))
	)
	restored["current_count"] = int(restored.get("count_required", 1))
	_expect(
		AdapterType.validate_active_state(restored).is_valid(),
		"Authored tutorial mission did not load as a valid restored state."
	)
	var cap = MissionCapabilityRegistryType.get_for_type(
		str(restored.get("objective_type", ""))
	)
	_expect(
		cap != null and cap.is_completed(restored),
		"Authored tutorial mission could not complete after restored progress."
	)


func _test_delivery_purchase_legacy_runtime_state() -> void:
	var courier := AdapterType.normalize_legacy_state({
		"title": "Legacy Courier",
		"faction": "neutral",
		"objective_type": "DELIVERY_COURIER",
		"item_name": "Sealed Evidence Tube",
		"origin_station_id": "station.start.main",
		"origin_display": "Main Station",
		"destination_station_id": "station.start.kova",
		"destination_display": "Kova Station",
	})
	_expect(
		AdapterType.validate_active_state(courier).is_valid()
			and bool(courier.get("cargo_loaded", false)),
		"Legacy courier state did not normalize with loaded cargo."
	)
	var purchase := AdapterType.normalize_legacy_state({
		"title": "Legacy Purchase",
		"faction": "neutral",
		"objective_type": "PURCHASE_DELIVERY",
		"item_id": "data_chip",
		"item_name": "Data Chip",
		"quantity_required": 0,
		"store_station_id": "station.start.main",
		"destination_station_id": "station.start.main",
		"destination_display": "Main Station",
	})
	_expect(
		AdapterType.validate_active_state(purchase).is_valid()
			and int(purchase.get("quantity_required", 0)) == 1,
		"Legacy purchase state did not normalize required quantity."
	)


func _test_invalid_runtime_state() -> void:
	var invalid := AdapterType.normalize_legacy_state({
		"title": "Broken",
		"faction": "zenith",
		"objective_type": "DELIVER_ORE",
		"amount_required": 0.0,
	})
	_expect(
		not AdapterType.validate_active_state(invalid).is_valid(),
		"Malformed active mission state was accepted."
	)


func _offer(
	title: String,
	faction: String,
	agent_name: String,
	objective: Dictionary
) -> Dictionary:
	return {
		"title": title,
		"faction": faction,
		"agent_name": agent_name,
		"dialogue": "Contract briefing.",
		"objective": objective,
		"choices": [],
	}


func _choice(
	credits: int,
	reputation: Dictionary,
	combat_multiplier: float,
	reward_multiplier: float,
	choice_id: String = ""
) -> Dictionary:
	var choice := {
		"text": "Accepted.",
		"consequence": {
			"credits_immediate": credits,
			"reputation_change": reputation,
			"combat_multiplier": combat_multiplier,
			"reward_credits_multiplier": reward_multiplier,
			"dialogue_response": "Proceed.",
		},
	}
	if not choice_id.is_empty():
		choice["choice_id"] = choice_id
	return choice


func _has_offer_template(offers: Array, template_id: String) -> bool:
	for offer in offers:
		if str(offer.get("template_id", "")) == template_id:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
