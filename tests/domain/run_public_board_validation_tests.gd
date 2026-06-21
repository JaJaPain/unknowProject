extends SceneTree

const OfferBuilderType := preload(
	"res://scripts/domain/PublicBoardOfferBuilder.gd"
)
const TextGenType := preload(
	"res://scripts/domain/PublicBoardTextGenerator.gd"
)
const AdapterType := preload("res://scripts/domain/MissionAdapter.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_builder_produces_all_templates()
	_test_builder_offers_have_required_fields()
	_test_pickup_offer_uses_current_system_outpost()
	_test_generated_system_without_outpost_does_not_use_starter_pickup()
	_test_generated_system_offers_use_story_pack()
	_test_full_service_station_assigns_faction_contacts_and_mechanic()
	_test_generated_contact_flavor_lines_do_not_repeat_immediately()
	_test_restart_clears_generated_contact_state()
	_test_ore_offer_is_urgent()
	_test_fallback_renders_all_placeholders()
	_test_fallback_preserves_board_metadata()
	_test_fallback_adapts_to_active_state()
	_test_generation_request_contains_placeholders()
	_test_missing_placeholder_rejected()
	_test_missing_field_rejected()
	_test_kaelen_authorship_rejected()
	_test_kaelen_disgust_required()
	_test_forbidden_mechanic_rejected()
	_test_recovery_drop_percentage_rejected()
	_test_field_length_limit_enforced()
	_test_multiple_fallback_salts()

	if _failures.is_empty():
		print("[PASS] Public board validation tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_builder_produces_all_templates() -> void:
	var offers := OfferBuilderType.build_offers(480)
	_expect(offers.size() >= 3, "builder_templates: fewer than 3 offers built.")
	var templates: Array[String] = []
	for offer in offers:
		templates.append(str(offer.get("template_id", "")))
	_expect(
		templates.has(OfferBuilderType.TEMPLATE_DELIVER_ORE)
			and templates.has(OfferBuilderType.TEMPLATE_PICKUP_SPECIAL)
			and templates.has(OfferBuilderType.TEMPLATE_RECOVER_COMBAT_DROP),
		"builder_templates: not all three templates were built."
	)


func _test_builder_offers_have_required_fields() -> void:
	var offers := OfferBuilderType.build_offers(480)
	for offer in offers:
		var has_fields := (
			str(offer.get("template_id", "")).length() > 0
			and str(offer.get("title", "")).length() > 0
			and str(offer.get("poster", "")).length() > 0
			and str(offer.get("body", "")).length() > 0
			and offer.has("quest_data")
			and offer.has("required_placeholders")
			and offer.has("placeholder_values")
		)
		_expect(
			has_fields,
			"required_fields: offer '%s' is missing required fields." %
			str(offer.get("template_id", "unknown"))
		)


func _test_pickup_offer_uses_current_system_outpost() -> void:
	var gs = root.get_node("GlobalState")
	var station := StaticBody3D.new()
	station.add_to_group("station")
	station.set_meta("station_type", "outpost")
	station.set_meta("world_id", "station.system_gen_test.s1")
	station.set_meta("display_name", "TEST RELAY")
	var generated_npcs: Array = gs.assign_generated_outpost_npcs(
		"station.system_gen_test.s1",
		1234
	)
	gs.active_system_entities.append(station)
	var offers := OfferBuilderType.build_offers(480)
	gs.active_system_entities.erase(station)
	gs.generated_outpost_npcs.erase("station.system_gen_test.s1")
	for npc_name in generated_npcs:
		gs.generated_outpost_npc_data.erase(npc_name)
	station.free()

	var pickup_offer: Dictionary = {}
	for offer in offers:
		if str(offer.get("template_id", "")) == OfferBuilderType.TEMPLATE_PICKUP_SPECIAL:
			pickup_offer = offer
			break
	_expect(not pickup_offer.is_empty(), "local_pickup: pickup offer was not found.")
	var quest_data: Dictionary = pickup_offer.get("quest_data", {})
	var objective: Dictionary = quest_data.get("objective", {})
	_expect(
		objective.get("target_outpost", "") == "station.system_gen_test.s1",
		"local_pickup: pickup offer did not use the current-system outpost."
	)
	_expect(
		str(objective.get("target_npc", "")) not in gs.MINOR_NPCS,
		"local_pickup: generated outpost reused an authored minor NPC."
	)


func _test_generated_system_without_outpost_does_not_use_starter_pickup() -> void:
	var gs = root.get_node("GlobalState")
	var previous_system_id: String = gs.current_system_id
	var previous_entities: Array = gs.active_system_entities.duplicate()
	gs.current_system_id = "system.gen.no_outpost_test"
	gs.active_system_entities.clear()
	var offers := OfferBuilderType.build_offers(480)
	gs.active_system_entities = previous_entities
	gs.current_system_id = previous_system_id

	for offer in offers:
		_expect(
			str(offer.get("template_id", "")) != OfferBuilderType.TEMPLATE_PICKUP_SPECIAL,
			"generated_no_outpost: pickup offer fell back to starter outposts."
		)


func _test_generated_system_offers_use_story_pack() -> void:
	var gs = root.get_node("GlobalState")
	var previous_system_id: String = gs.current_system_id
	var previous_entities: Array = gs.active_system_entities.duplicate()
	var system_id := "system.gen.board_story_test"
	var config := SystemConfig.from_seed("Board Story", system_id, 9191)
	config.faction_weights = {"dustborn": 0.65, "wraiths": 0.35}
	config.story_pack = {
		"system_id": system_id,
		"station_economy_problem": "ore claims are being sold with optimistic maps",
		"active_tension": "Dustborn and Wraith crews are arguing over quiet lanes",
		"resource_hook": "heat-scored ore seams",
		"mission_seeds": ["verify a disputed cargo route"],
	}
	OfferBuilderType.story_config_override_for_tests = config
	gs.current_system_id = system_id
	gs.active_system_entities.clear()
	var offers := OfferBuilderType.build_offers(480)
	OfferBuilderType.story_config_override_for_tests = null
	gs.active_system_entities = previous_entities
	gs.current_system_id = previous_system_id

	var ore_offer: Dictionary = {}
	var recovery_offer: Dictionary = {}
	for offer in offers:
		if str(offer.get("template_id", "")) == OfferBuilderType.TEMPLATE_DELIVER_ORE:
			ore_offer = offer
		if str(offer.get("template_id", "")) == OfferBuilderType.TEMPLATE_RECOVER_COMBAT_DROP:
			recovery_offer = offer
	_expect(
		not ore_offer.is_empty()
			and str(ore_offer.get("body", "")).contains("Local note:"),
		"story_pack_board: ore offer did not include local story context."
	)
	var quest_data: Dictionary = recovery_offer.get("quest_data", {})
	var objective: Dictionary = quest_data.get("objective", {})
	_expect(
		not recovery_offer.is_empty()
			and str(recovery_offer.get("body", "")).contains("Local note:")
			and str(objective.get("target_faction", "")) == "dustborn",
		"story_pack_board: recovery offer did not use local story/faction context."
	)


func _test_full_service_station_assigns_faction_contacts_and_mechanic() -> void:
	var gs = root.get_node("GlobalState")
	var station_id := "station.system_gen_test.s0"
	var contacts: Array = gs.assign_generated_station_npcs(
		station_id,
		5678,
		{
			"gen_glass_choir_00": 0.6,
			"gen_rust_index_01": 0.4,
		}
	)
	_expect(
		contacts.size() >= 3,
		"station_contacts: full-service station did not get faction contacts plus mechanic."
	)
	var mechanic_found := false
	var faction_contacts := 0
	for npc_name in contacts:
		var npc_data: Dictionary = gs.get_minor_npc_data(str(npc_name))
		if str(npc_data.get("role", "")) == "Station mechanic":
			mechanic_found = true
		if str(npc_data.get("role", "")) == "Faction contact":
			faction_contacts += 1
		gs.generated_outpost_npc_data.erase(str(npc_name))
	gs.generated_outpost_npcs.erase(station_id)
	_expect(mechanic_found, "station_contacts: mechanic contact was not assigned.")
	_expect(
		faction_contacts >= 2,
		"station_contacts: not enough faction contacts were assigned."
	)


func _test_generated_contact_flavor_lines_do_not_repeat_immediately() -> void:
	var gs = root.get_node("GlobalState")
	var station_id := "station.system_gen_test.repeat"
	var npc_name := "Repeat Test Contact"
	gs.generated_outpost_npcs[station_id] = [npc_name]
	gs.generated_outpost_npc_data[npc_name] = {
		"outpost": station_id,
		"display_name": npc_name,
		"flavor_lines": ["First line.", "Second line."],
		"line_memory_fingerprints": [],
		"voice_profile_id": "voice.neutral.v1",
		"flavor_color": Color.WHITE,
	}
	gs.npc_line_memory.erase(npc_name)
	var first: Dictionary = gs.get_random_npc_flavor_line(station_id)
	var second: Dictionary = gs.get_random_npc_flavor_line(station_id)
	_expect(
		not first.is_empty()
			and not second.is_empty()
			and str(first.get("line", "")) != str(second.get("line", "")),
		"contact_line_memory: generated contact repeated a flavor line immediately."
	)
	gs.generated_outpost_npc_data.erase(npc_name)
	gs.generated_outpost_npcs.erase(station_id)
	gs.npc_line_memory.erase(npc_name)


func _test_restart_clears_generated_contact_state() -> void:
	var gs = root.get_node("GlobalState")
	gs.generated_outpost_npcs["station.system_gen_test.stale"] = ["Stale Contact"]
	gs.generated_outpost_npc_data["Stale Contact"] = {
		"outpost": "station.system_gen_test.stale",
		"flavor_lines": ["Old news."],
	}
	gs.npc_line_memory["Stale Contact"] = ["old"]
	gs.reset_for_restart()
	_expect(
		gs.generated_outpost_npcs.is_empty()
			and gs.generated_outpost_npc_data.is_empty()
			and gs.npc_line_memory.is_empty(),
		"contact_reset: generated contact state survived a new-campaign reset."
	)


func _test_ore_offer_is_urgent() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var ore_offer: Dictionary = {}
	for offer in offers:
		if str(offer.get("template_id", "")) == OfferBuilderType.TEMPLATE_DELIVER_ORE:
			ore_offer = offer
			break
	_expect(not ore_offer.is_empty(), "ore_urgent: ore offer was not found.")
	var quest_data: Dictionary = ore_offer.get("quest_data", {})
	var timing: Dictionary = quest_data.get("timing", {})
	_expect(
		bool(timing.get("timed", false))
			and bool(timing.get("urgent", false))
			and int(timing.get("duration_minutes", 0)) > 0
			and float(timing.get("urgent_reward_multiplier", 1.0)) > 1.0,
		"ore_urgent: ore offer was not built as an urgent timed posting."
	)


func _test_fallback_renders_all_placeholders() -> void:
	var offers := OfferBuilderType.build_offers(480)
	for offer in offers:
		var rendered := TextGenType.fallback_offer(offer, 0)
		var title := str(rendered.get("title", ""))
		var body := str(rendered.get("body", ""))
		var briefing := str(rendered.get("generated_briefing", ""))
		var combined := title + body + briefing
		for placeholder in offer.get("required_placeholders", []):
			_expect(
				not combined.contains(str(placeholder)),
				"fallback_placeholders: '%s' still has raw placeholder %s." % [
					str(offer.get("template_id", "")),
					str(placeholder),
				]
			)


func _test_fallback_preserves_board_metadata() -> void:
	var offers := OfferBuilderType.build_offers(480)
	for offer in offers:
		var rendered := TextGenType.fallback_offer(offer, 0)
		var quest_data: Dictionary = rendered.get("quest_data", {})
		_expect(
			bool(quest_data.get("public_board", false))
				and str(quest_data.get("public_board_turn_in_line", "")).length() > 0,
			"fallback_metadata: '%s' lost public_board or turn_in_line." %
			str(offer.get("template_id", ""))
		)


func _test_fallback_adapts_to_active_state() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var offer: Dictionary = offers[0]
	var rendered := TextGenType.fallback_offer(offer, 0)
	var quest_data: Dictionary = rendered.get("quest_data", {})
	var choices: Array = quest_data.get("choices", [])
	_expect(
		not choices.is_empty(),
		"fallback_adapt: fallback quest_data had no choices."
	)
	var adapted := AdapterType.build_active_state(
		quest_data, choices[0],
		"mission.runtime.board_adapt_test", "start_system", 480
	)
	_expect(
		adapted["validation"].is_valid(),
		"fallback_adapt: fallback offer did not produce a valid active state."
	)
	_expect(
		bool(adapted["state"].get("public_board", false)),
		"fallback_adapt: public_board flag lost during adaptation."
	)


func _test_generation_request_contains_placeholders() -> void:
	var offers := OfferBuilderType.build_offers(480)
	for offer in offers:
		var request := TextGenType.build_generation_request(offer)
		var prompt := str(request.get("prompt", ""))
		for placeholder in offer.get("required_placeholders", []):
			_expect(
				prompt.contains(str(placeholder)),
				"gen_request: prompt for '%s' is missing %s." % [
					str(offer.get("template_id", "")),
					str(placeholder),
				]
			)


func _test_missing_placeholder_rejected() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var offer: Dictionary = offers[0]
	var bad_payload := {
		"title": "Ore job",
		"poster": "Someone",
		"body": "Bring ore.",
		"briefing": "Bring ore.",
		"kaelen_turn_in": "I processed the payout. Public board work, really? The grime alone has standards dropping.",
	}
	_expect(
		not bool(TextGenType.validate_payload(offer, bad_payload).get("ok", false)),
		"missing_placeholder: payload without required placeholders was accepted."
	)


func _test_missing_field_rejected() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var offer: Dictionary = offers[0]
	var incomplete := {
		"title": "Ore job with {ORE_AMOUNT} to {TURN_IN_LOCATION}",
		"poster": "Someone",
		"body": "Bring {ORE_AMOUNT} ore to {TURN_IN_LOCATION}.",
	}
	_expect(
		not bool(TextGenType.validate_payload(offer, incomplete).get("ok", false)),
		"missing_field: payload missing briefing and kaelen_turn_in was accepted."
	)


func _test_kaelen_authorship_rejected() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var offer: Dictionary = offers[0]
	var payload := TextGenType.fallback_payload(offer, 0)
	payload["kaelen_turn_in"] = (
		"I posted this contract for {ORE_AMOUNT} to {TURN_IN_LOCATION}. My job, my rules."
	)
	_expect(
		not bool(TextGenType.validate_payload(offer, payload).get("ok", false)),
		"kaelen_authorship: Kaelen claiming she posted the job was accepted."
	)


func _test_kaelen_disgust_required() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var offer: Dictionary = offers[0]
	var payload := TextGenType.fallback_payload(offer, 0)
	payload["kaelen_turn_in"] = (
		"Credits transferred for the {ORE_AMOUNT} delivery to {TURN_IN_LOCATION}. Good work."
	)
	_expect(
		not bool(TextGenType.validate_payload(offer, payload).get("ok", false)),
		"kaelen_disgust: Kaelen line without disgust cues was accepted."
	)


func _test_forbidden_mechanic_rejected() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var offer: Dictionary = offers[0]
	var payload := TextGenType.fallback_payload(offer, 0)
	payload["body"] = (
		"Land on the planet surface and deliver {ORE_AMOUNT} to {TURN_IN_LOCATION}."
	)
	_expect(
		not bool(TextGenType.validate_payload(offer, payload).get("ok", false)),
		"forbidden_mechanic: payload with unsupported mechanic was accepted."
	)


func _test_recovery_drop_percentage_rejected() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var recovery_offer: Dictionary = {}
	for offer in offers:
		if str(offer.get("template_id", "")) == OfferBuilderType.TEMPLATE_RECOVER_COMBAT_DROP:
			recovery_offer = offer
			break
	_expect(
		not recovery_offer.is_empty(),
		"drop_pct: recovery offer was not found."
	)
	var payload := TextGenType.fallback_payload(recovery_offer, 0)
	payload["body"] = (
		"Search {TARGET_FACTION} wreckage for {ITEM_NAME}. "
		+ "There is a 33% chance per wreck. Return to {TURN_IN_LOCATION}."
	)
	_expect(
		not bool(
			TextGenType.validate_payload(recovery_offer, payload).get("ok", false)
		),
		"drop_pct: payload exposing drop percentage was accepted."
	)


func _test_field_length_limit_enforced() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var offer: Dictionary = offers[0]
	var payload := TextGenType.fallback_payload(offer, 0)
	payload["title"] = "A".repeat(200)
	_expect(
		not bool(TextGenType.validate_payload(offer, payload).get("ok", false)),
		"field_length: title exceeding 96 chars was accepted."
	)


func _test_multiple_fallback_salts() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var ore_offer: Dictionary = {}
	for offer in offers:
		if str(offer.get("template_id", "")) == OfferBuilderType.TEMPLATE_DELIVER_ORE:
			ore_offer = offer
			break
	_expect(not ore_offer.is_empty(), "salts: ore offer not found.")
	var text_0 := str(TextGenType.fallback_payload(ore_offer, 0).get("title", ""))
	var text_1 := str(TextGenType.fallback_payload(ore_offer, 1).get("title", ""))
	_expect(
		text_0 != text_1,
		"salts: different salt values produced identical fallback text."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
