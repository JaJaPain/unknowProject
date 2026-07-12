extends SceneTree

const StoryAgentOfferBuilderType := preload("res://scripts/story/StoryAgentOfferBuilder.gd")
const MissionAdapterType := preload("res://scripts/domain/MissionAdapter.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_template_backed_story_agent_offers_validate()

	if _failures.is_empty():
		print("[PASS] Story agent offer builder tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_template_backed_story_agent_offers_validate() -> void:
	for objective_type in [
		"DELIVERY_COURIER",
		"PURCHASE_DELIVERY",
		"RECOVER_COMBAT_DROP",
		"TARGET_WITH_COMMS_REVERSAL",
	]:
		var profile := _profile_for_objective(objective_type)
		_expect(
			StoryAgentOfferBuilderType.can_build(profile),
			"Builder did not recognize %s as template-backed." % objective_type
		)
		var offer := StoryAgentOfferBuilderType.build_offer(
			"neutral",
			profile,
			480
		)
		_expect(not offer.is_empty(), "Builder returned empty offer for %s." % objective_type)
		if offer.is_empty():
			continue
		_expect(
			str(offer.get("story_beat_id", "")) == "beat.%s" % objective_type.to_lower(),
			"Offer missing story beat id for %s." % objective_type
		)
		var choices: Array = offer.get("choices", []) if offer.get("choices", []) is Array else []
		var adapted := MissionAdapterType.build_active_state(
			offer,
			choices[0] if not choices.is_empty() else {},
			"mission.runtime.test.%s" % objective_type.to_lower(),
			"start_system",
			480
		)
		_expect(
			(adapted.get("validation") != null)
				and adapted.get("validation").is_valid(),
			"Built story agent offer failed validation for %s." % objective_type
		)


func _profile_for_objective(objective_type: String) -> Dictionary:
	return {
		"agent_id": "agent.test",
		"agent_name": "Jenna Kross",
		"agent_role": "Frontier Station Contact",
		"faction": "neutral",
		"story_agent_offer_context": {
			"ok": true,
			"candidate": {
				"packet_id": "chapter_packet.1",
				"chapter": 1,
				"beat_id": "beat.%s" % objective_type.to_lower(),
				"thread_id": "thread.pressure",
				"cause_id": "cause.shortage",
				"objective_type": objective_type,
				"giver_id": "agent.test",
				"location_id": "station.start.kova",
				"faction_id": "reavers",
				"stake": "The clinic needs the pressure relieved before panic spreads.",
				"complication": "The manifest has already leaked.",
				"disclosure_fact_ids": ["fact.public"],
				"completion_fact_ids": ["fact.prototype_core"],
				"world_consequence": "The clinic keeps treating refugees.",
				"premise_fingerprint": "clinic.%s" % objective_type.to_lower(),
			},
			"budget": {
				"difficulty_band": "pressured",
				"target_duration_minutes": 30,
				"ore_amount": 0.0,
				"kill_count": 3,
				"deadline_minutes": 90,
				"reward_multiplier": 1.25,
			},
		},
	}
