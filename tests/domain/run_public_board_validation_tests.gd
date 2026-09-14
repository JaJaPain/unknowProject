extends SceneTree

const OfferBuilderType := preload(
	"res://scripts/domain/PublicBoardOfferBuilder.gd"
)
const TextGenType := preload(
	"res://scripts/domain/PublicBoardTextGenerator.gd"
)
const AdapterType := preload("res://scripts/domain/MissionAdapter.gd")
const CausalContractType := preload("res://scripts/domain/QuestCausalContract.gd")
const PlausibilityType := preload(
	"res://scripts/domain/QuestPlausibilityValidator.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_test_builder_produces_all_templates()
	_test_builder_offers_have_required_fields()
	_test_courier_and_purchase_offers_adapt_to_active_state()
	_test_starter_world_ids_resolve_to_authored_pickup_contacts()
	_test_pickup_offer_uses_current_system_outpost()
	_test_generated_system_without_outpost_does_not_use_starter_pickup()
	_test_generated_system_offers_use_story_pack()
	_test_public_board_offers_carry_story_cause_metadata()
	_test_generated_system_offers_compile_a_valid_causal_contract()
	_test_causal_publication_states_are_explicit()
	_test_invalid_contract_offers_are_withheld()
	_test_incoherent_generated_causes_are_withheld()
	_test_full_service_station_assigns_faction_contacts_and_mechanic()
	_test_generated_contact_portrait_voice_gender_matches()
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


func _test_incoherent_generated_causes_are_withheld() -> void:
	var gs = root.get_node("GlobalState")
	var previous_id: String = gs.current_system_id
	var config := SystemConfig.from_seed("Coherence", "system.coherence", 8080)
	gs.current_system_id = "system.coherence"
	OfferBuilderType.story_config_override_for_tests = config
	var valid_offers := OfferBuilderType.build_offers(480)
	_expect(not valid_offers.is_empty(), "Coherent system produced no offers to test.")
	var ids: Array[String] = []
	for agenda: Dictionary in config.story_pack.get("faction_agendas", []):
		ids.append(str(agenda.get("faction_id", "")))
		var desire: Dictionary = agenda.get("desire", {})
		desire["goal"] = "prove a rival's manifest is fiction"
		desire["need"] = "fuel it can afford"
		var draft := {"objective": {"type": "DELIVERY_COURIER"}, "narrative_metadata": {}}
		OfferBuilderType._attach_causal_contract(draft, {"cause_faction_id": agenda["faction_id"]})
		_expect(draft.get("causal_publication_state", "") == OfferBuilderType.PUBLICATION_WITHHELD, "Broken goal/need published as uncaused compatibility.")
		_expect("unsupported_goal_need" in draft.get("causal_withheld_issue_codes", []), "Withheld cause lost its diagnostic.")
	_expect(not ids.is_empty(), "No generated factions exercised the publication guard.")
	for offer in OfferBuilderType.build_offers(480):
		var metadata: Dictionary = offer.get("quest_data", {}).get("narrative_metadata", {})
		_expect(str(metadata.get("cause_faction_id", "")) not in ids, "Real board publication bypassed coherence rejection.")
	OfferBuilderType.story_config_override_for_tests = null
	gs.current_system_id = previous_id


func _test_builder_produces_all_templates() -> void:
	var offers := OfferBuilderType.build_offers(480)
	_expect(offers.size() >= 3, "builder_templates: fewer than 3 offers built.")
	var templates: Array[String] = []
	for offer in offers:
		templates.append(str(offer.get("template_id", "")))
	_expect(
		templates.has(OfferBuilderType.TEMPLATE_DELIVER_ORE)
			and templates.has(OfferBuilderType.TEMPLATE_PICKUP_SPECIAL)
			and templates.has(OfferBuilderType.TEMPLATE_DELIVERY_COURIER)
			and templates.has(OfferBuilderType.TEMPLATE_PURCHASE_DELIVERY)
			and templates.has(OfferBuilderType.TEMPLATE_RECOVER_COMBAT_DROP),
		"builder_templates: not all public board templates were built."
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


func _test_courier_and_purchase_offers_adapt_to_active_state() -> void:
	var offers := OfferBuilderType.build_offers(480)
	var courier_offer: Dictionary = {}
	var purchase_offer: Dictionary = {}
	for offer in offers:
		if str(offer.get("template_id", "")) == OfferBuilderType.TEMPLATE_DELIVERY_COURIER:
			courier_offer = offer
		if str(offer.get("template_id", "")) == OfferBuilderType.TEMPLATE_PURCHASE_DELIVERY:
			purchase_offer = offer
	_expect(not courier_offer.is_empty(), "delivery_offer: courier offer was not built.")
	_expect(not purchase_offer.is_empty(), "purchase_offer: purchase offer was not built.")
	if not courier_offer.is_empty():
		_expect(
			_adapted_offer_has_objective(
				courier_offer,
				"mission.runtime.board_delivery_test",
				"DELIVERY_COURIER"
			),
			"delivery_offer: courier offer did not adapt to valid active state."
		)
	if not purchase_offer.is_empty():
		_expect(
			_adapted_offer_has_objective(
				purchase_offer,
				"mission.runtime.board_purchase_test",
				"PURCHASE_DELIVERY"
			),
			"purchase_offer: purchase offer did not adapt to valid active state."
		)


func _adapted_offer_has_objective(
	offer: Dictionary,
	runtime_id: String,
	objective_type: String
) -> bool:
	var quest_data: Dictionary = offer.get("quest_data", {})
	var choices: Array = quest_data.get("choices", [])
	if choices.is_empty():
		return false
	var adapted := AdapterType.build_active_state(
		quest_data,
		choices[0],
		runtime_id,
		"start_system",
		480
	)
	return adapted["validation"].is_valid() \
		and str(adapted["state"].get("objective_type", "")) == objective_type


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


func _test_starter_world_ids_resolve_to_authored_pickup_contacts() -> void:
	var gs = root.get_node("GlobalState")
	_expect(
		not gs.get_minor_npcs_at_outpost("station.start.iron_reach").is_empty(),
		"starter_pickup: Iron Reach world id did not resolve to authored pickup contacts."
	)
	_expect(
		not gs.get_minor_npcs_at_outpost("station.start.kova").is_empty(),
		"starter_pickup: Kova world id did not resolve to authored pickup contacts."
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


func _test_public_board_offers_carry_story_cause_metadata() -> void:
	var manager = root.get_node("StoryManager")
	var previous_state: Dictionary = manager.story_state.duplicate(true)
	manager.story_state["active_tensions"] = ["Dock strikes are spreading past the inner ring."]
	manager.story_state["pending_hooks"] = ["A missing coolant relay keeps changing hands."]
	var offers := OfferBuilderType.build_offers(480)
	manager.story_state = previous_state
	_expect(not offers.is_empty(), "story_metadata: no public-board offers built.")
	if offers.is_empty():
		return
	var quest_data: Dictionary = offers[0].get("quest_data", {})
	var metadata: Dictionary = quest_data.get("narrative_metadata", {})
	_expect(
		str(metadata.get("cause_id", "")).begins_with("cause.public_board."),
		"story_metadata: public-board offer missing cause_id."
	)
	_expect(
		str(metadata.get("public_because", "")).contains("Dock strikes"),
		"story_metadata: public-board offer missing public pressure text."
	)
	_expect(
		str(metadata.get("story_hook_ref", "")).begins_with("hook:"),
		"story_metadata: public-board offer missing story_hook_ref."
	)
	var rendered := TextGenType.fallback_offer(offers[0], 0)
	var turn_in_line := str(
		rendered.get("quest_data", {}).get("public_board_turn_in_line", "")
	)
	_expect(
		turn_in_line.contains(str(offers[0].get("poster", "")))
			and turn_in_line.contains("Dock strikes")
			and not turn_in_line.contains("{STORY_PRESSURE}")
			and not turn_in_line.contains("{POSTER_HANDLE}"),
		"story_metadata: Kaelen public-board fallback did not name poster and local pressure."
	)
	var choices: Array = quest_data.get("choices", [])
	if choices.is_empty():
		_expect(false, "story_metadata: offer had no choices to adapt.")
		return
	var adapted := AdapterType.build_active_state(
		quest_data,
		choices[0],
		"mission.runtime.board_story_metadata",
		"start_system",
		480
	)
	_expect(
		adapted["validation"].is_valid()
			and str(
				adapted["state"].get("narrative_metadata", {}).get("cause_id", "")
			).begins_with("cause.public_board."),
		"story_metadata: narrative metadata did not survive active-state adaptation."
	)



## The integration that matters: a REAL offer built by the REAL builder in a
## generated system must carry a causal contract that passes the plausibility
## gate, and that contract must survive being adapted into active mission state.
func _test_generated_system_offers_compile_a_valid_causal_contract() -> void:
	var gs = root.get_node("GlobalState")
	var previous_system_id: String = gs.current_system_id
	var previous_entities: Array = gs.active_system_entities.duplicate()
	var system_id := "system.gen.causal_contract_test"
	# Specify the causal scenario this test needs. A random seed no longer owes
	# us a recovery job: compatible needs may legitimately yield only deliveries,
	# which this fixture's deliberately empty world cannot publish.
	var store_type = load("res://scripts/persistence/CampaignGeneratedFactionStore.gd")
	var desire_type = load("res://scripts/persistence/GeneratedFactionDesire.gd")
	var factions: Array = store_type.generate_system_factions("causal.fixture", system_id, 2)
	for faction: Dictionary in factions:
		var desire: Dictionary = faction["desire"]
		desire["goal"] = desire_type.GOALS[6]
		desire["success_condition"] = desire_type.SUCCESS_CONDITIONS[6]
		desire["need"] = "filed claim evidence"
		desire["need_reason"] = desire_type.Constraints.need_reason(6, desire["need"])
		desire["mission_intents"] = ["recovery", "pickup"]
	var config := SystemConfig.from_seed("Causal Contract", system_id, 4242, factions)
	OfferBuilderType.story_config_override_for_tests = config
	gs.current_system_id = system_id
	gs.active_system_entities.clear()
	var offers := OfferBuilderType.build_offers(480)
	OfferBuilderType.story_config_override_for_tests = null
	gs.active_system_entities = previous_entities
	gs.current_system_id = previous_system_id

	var contracted := 0
	for offer in offers:
		var quest_data: Dictionary = offer.get("quest_data", {})
		var contract: Variant = quest_data.get("causal_contract", {})
		if not CausalContractType.is_present(contract):
			continue
		contracted += 1
		var normalized := CausalContractType.normalize(contract)
		# Whatever the builder attached must already have passed the gate.
		var report: Dictionary = PlausibilityType.check(normalized, {})
		_expect(
			bool(report.get("ok", false)),
			"causal_contract: published offer '%s' carries an invalid contract: %s" % [
				str(offer.get("title", "")),
				str(report.get("issue_codes", [])),
			]
		)
		# The requester must be a LOCAL generated faction, not a tutorial one.
		var requester := str(normalized.get("requester_id", ""))
		_expect(
			requester.begins_with("faction.generated."),
			"causal_contract: offer '%s' was caused by a non-local faction '%s'." % [
				str(offer.get("title", "")), requester
			]
		)
		# Facts must be real, not placeholders.
		_expect(
			(normalized.get("facts", {}) as Dictionary).size() > 0,
			"causal_contract: offer '%s' compiled a contract with no facts." % str(offer.get("title", ""))
		)
		_expect(
			CausalContractType.missing_fact_ids(normalized).is_empty(),
			"causal_contract: offer '%s' references facts it does not record." % str(offer.get("title", ""))
		)
		# Nothing may invent urgency the objective does not actually have.
		var binding: Dictionary = normalized.get("objective_binding", {})
		if int(binding.get("deadline_minutes", 0)) <= 0:
			_expect(
				(normalized.get("urgency_fact_ids", []) as Array).is_empty(),
				"causal_contract: offer '%s' recorded urgency with no deadline." % str(offer.get("title", ""))
			)
		# And the contract must survive the real adapter into mission state.
		var choices: Array = quest_data.get("choices", [])
		if choices.is_empty():
			continue
		var adapted: Dictionary = AdapterType.build_active_state(
			quest_data,
			choices[0],
			"mission.test.causal_contract",
			system_id,
			480
		)
		var validation = adapted.get("validation")
		_expect(
			validation != null and validation.is_valid(),
			"causal_contract: a contracted offer failed mission adaptation."
		)
		var state: Dictionary = adapted.get("state", {})
		var carried: Variant = state.get("narrative_metadata", {}).get("causal_contract", {})
		_expect(
			CausalContractType.is_present(carried),
			"causal_contract: the contract was lost adapting offer '%s' into mission state." % str(offer.get("title", ""))
		)

	_expect(
		contracted > 0,
		"causal_contract: no generated-system board offer compiled a causal contract at all."
	)
	# The honest fallback, asserted rather than assumed: an offer whose cause no
	# local faction actually holds -- or whose recipient cannot be resolved yet --
	# publishes WITHOUT a contract and is still a complete, valid, acceptable job.
	# Withholding those offers would empty the board for no player benefit.
	for offer in offers:
		var data: Dictionary = offer.get("quest_data", {})
		if CausalContractType.is_present(data.get("causal_contract", {})):
			continue
		_expect(
			not str(data.get("dialogue", "")).strip_edges().is_empty()
				and not (data.get("objective", {}) as Dictionary).is_empty(),
			"causal_contract: an offer without a contract lost its template content."
		)
		var uncontracted_choices: Array = data.get("choices", [])
		if uncontracted_choices.is_empty():
			continue
		var adapted_plain: Dictionary = AdapterType.build_active_state(
			data, uncontracted_choices[0], "mission.test.no_contract", system_id, 480
		)
		var plain_validation = adapted_plain.get("validation")
		_expect(
			plain_validation != null and plain_validation.is_valid(),
			"causal_contract: an offer without a contract stopped being acceptable."
		)


## Every built offer must say WHY it is publishable. "No local cause" and
## "contract failed validation" are different situations and must not share a
## silent code path.
func _test_causal_publication_states_are_explicit() -> void:
	var gs = root.get_node("GlobalState")
	var previous_system_id: String = gs.current_system_id
	var previous_entities: Array = gs.active_system_entities.duplicate()
	var system_id := "system.gen.publication_state_test"
	var config := SystemConfig.from_seed("Publication State", system_id, 31337)
	OfferBuilderType.story_config_override_for_tests = config
	gs.current_system_id = system_id
	gs.active_system_entities.clear()
	var offers := OfferBuilderType.build_offers(480)
	OfferBuilderType.story_config_override_for_tests = null
	gs.active_system_entities = previous_entities
	gs.current_system_id = previous_system_id

	var valid_states := [
		OfferBuilderType.PUBLICATION_VALIDATED,
		OfferBuilderType.PUBLICATION_UNCAUSED,
	]
	for offer in offers:
		var quest_data: Dictionary = offer.get("quest_data", {})
		var state := str(quest_data.get("causal_publication_state", ""))
		_expect(
			state in valid_states,
			"publication_state: offer '%s' published with state '%s'." % [
				str(offer.get("title", "")), state
			]
		)
		# A withheld offer must never reach the published list.
		_expect(
			state != OfferBuilderType.PUBLICATION_WITHHELD,
			"publication_state: a withheld offer was published anyway."
		)
		if state == OfferBuilderType.PUBLICATION_VALIDATED:
			_expect(
				CausalContractType.is_present(quest_data.get("causal_contract", {})),
				"publication_state: an offer marked validated carries no contract."
			)
		else:
			_expect(
				not CausalContractType.is_present(quest_data.get("causal_contract", {})),
				"publication_state: an uncaused offer carries a contract."
			)


## An offer whose contract fails validation has broken mechanics or an unbound
## cause. It must not become a new discretionary job -- but an ALREADY ACCEPTED
## mission is governed by its saved terms and must stay completable.
func _test_invalid_contract_offers_are_withheld() -> void:
	var offers: Array[Dictionary] = [
		{
			"template_id": "keeps.validated",
			"quest_data": {
				"title": "Valid Job",
				"causal_publication_state": OfferBuilderType.PUBLICATION_VALIDATED,
			},
		},
		{
			"template_id": "keeps.uncaused",
			"quest_data": {
				"title": "Ordinary Board Job",
				"causal_publication_state": OfferBuilderType.PUBLICATION_UNCAUSED,
			},
		},
		{
			"template_id": "drops.invalid",
			"quest_data": {
				"title": "Impossible Job",
				"causal_publication_state": OfferBuilderType.PUBLICATION_WITHHELD,
				"causal_withheld_issue_codes": ["unreachable_location"],
			},
		},
		{
			"template_id": "keeps.legacy_no_state",
			"quest_data": {"title": "Legacy Offer With No State At All"},
		},
	]
	OfferBuilderType._withhold_invalid_offers(offers)
	var ids: Array[String] = []
	for offer in offers:
		ids.append(str(offer.get("template_id", "")))
	_expect(
		"drops.invalid" not in ids,
		"withhold: an offer with an invalid contract was still published."
	)
	for expected in ["keeps.validated", "keeps.uncaused", "keeps.legacy_no_state"]:
		_expect(
			expected in ids,
			"withhold: '%s' was removed when it should have been kept." % expected
		)
	# An offer carrying no state at all is a legacy shape and must survive.
	_expect(offers.size() == 3, "withhold: wrong number of offers survived.")

	# The withheld offer must still be a complete, adaptable job -- withholding
	# is a PUBLICATION decision, not corruption of the mission data. An already
	# accepted copy of the same job must remain completable.
	var accepted := {
		"title": "Impossible Job",
		"campaign_name": "Test",
		"faction": "neutral",
		"agent_name": "Board",
		"agent_role": "Public Board",
		"dialogue": "Saved terms from when this was accepted.",
		"objective": {"type": "DELIVER_ORE", "amount_required": 20.0, "reward_credits": 100},
		"choices": [{"id": "choice.accept", "label": "Accept", "action": "accept"}],
		"causal_publication_state": OfferBuilderType.PUBLICATION_WITHHELD,
	}
	var adapted: Dictionary = AdapterType.build_active_state(
		accepted, accepted["choices"][0], "mission.test.withheld_but_accepted", "start_system", 480
	)
	var validation = adapted.get("validation")
	_expect(
		validation != null and validation.is_valid(),
		"withhold: an already-accepted job stopped being completable because today's rules would withhold it."
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


func _test_generated_contact_portrait_voice_gender_matches() -> void:
	var gs = root.get_node("GlobalState")
	var station_ids: Array[String] = []
	for seed_index in range(8):
		var station_id := "station.system_gen_test.presentation_%d" % seed_index
		station_ids.append(station_id)
		var contacts: Array = gs.assign_generated_station_npcs(
			station_id,
			7600 + seed_index,
			{
				"gen_glass_choir_00": 0.6,
				"gen_rust_index_01": 0.4,
			}
		)
		for npc_name in contacts:
			var npc_data: Dictionary = gs.get_minor_npc_data(str(npc_name))
			var portrait_gender := _presentation_gender(
				str(npc_data.get("portrait_id", ""))
			)
			var voice_gender := _presentation_gender(
				str(npc_data.get("voice_profile_id", ""))
			)
			_expect(
				portrait_gender.is_empty()
					or voice_gender.is_empty()
					or portrait_gender == voice_gender,
				"station_contacts: generated contact portrait and voice genders do not match."
			)
			gs.generated_outpost_npc_data.erase(str(npc_name))
	for station_id in station_ids:
		gs.generated_outpost_npcs.erase(station_id)


func _presentation_gender(presentation_id: String) -> String:
	if presentation_id in [
		"portrait.minor_npc_01.cassen_vane",
		"portrait.minor_npc_01.korvin_shaw",
		"portrait.minor_npc_02.oleg_stroud",
		"portrait.minor_npc_02.alaric_venn",
		"voice.cassen_vane.v1",
		"voice.korvin_shaw.v1",
		"voice.oleg_stroud.v1",
		"voice.alaric_venn.v1",
	]:
		return "male"
	if presentation_id in [
		"portrait.minor_npc_01.mariska_vonn",
		"portrait.minor_npc_01.hana_quill",
		"portrait.minor_npc_02.dasha_invar",
		"voice.mariska_vonn.v1",
		"voice.hana_quill.v1",
		"voice.dasha_invar.v1",
	]:
		return "female"
	return ""


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
		_expect(
			prompt.contains("{POSTER_HANDLE}"),
			"gen_request: prompt for '%s' is missing poster placeholder." %
			str(offer.get("template_id", ""))
		)
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
