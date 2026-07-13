extends SceneTree

const StoryAgentOfferBuilderType := preload("res://scripts/story/StoryAgentOfferBuilder.gd")
const MissionAdapterType := preload("res://scripts/domain/MissionAdapter.gd")
const DialogueBundleValidatorType := preload("res://scripts/story/DialogueBundleValidator.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var diagnostics := _generation_diagnostics()
	if diagnostics != null and diagnostics.has_method("reset"):
		diagnostics.reset()
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
		_assert_story_offer_identity(offer, objective_type)
		_assert_story_offer_conversation_bundle(offer, objective_type)
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
		_assert_story_offer_identity(
			adapted.get("state", {}) if adapted.get("state", {}) is Dictionary else {},
			objective_type,
			"adapted state"
		)


func _assert_story_offer_identity(
	source: Dictionary,
	objective_type: String,
	source_label: String = "offer"
) -> void:
	var metadata: Dictionary = source.get("narrative_metadata", {}) \
		if source.get("narrative_metadata", {}) is Dictionary else {}
	var expected_beat_id := "beat.%s" % objective_type.to_lower()
	_expect(
		str(source.get("story_thread_id", "")) == "thread.pressure",
		"%s missing valid story thread id for %s." % [source_label, objective_type]
	)
	_expect(
		str(source.get("story_beat_id", "")) == expected_beat_id,
		"%s missing valid story beat id for %s." % [source_label, objective_type]
	)
	_expect(
		str(source.get("cause_id", "")) == "cause.shortage",
		"%s missing valid cause id for %s." % [source_label, objective_type]
	)
	_expect(
		str(metadata.get("story_thread_id", "")) == "thread.pressure",
		"%s metadata missing valid story thread id for %s." % [source_label, objective_type]
	)
	_expect(
		str(metadata.get("story_beat_id", "")) == expected_beat_id,
		"%s metadata missing valid story beat id for %s." % [source_label, objective_type]
	)
	_expect(
		str(metadata.get("cause_id", "")) == "cause.shortage",
		"%s metadata missing valid cause id for %s." % [source_label, objective_type]
	)
	_expect(
		not str(metadata.get("public_because", "")).strip_edges().is_empty(),
		"%s metadata missing player-safe public cause for %s." % [
			source_label,
			objective_type,
		]
	)


func _assert_story_offer_conversation_bundle(
	offer: Dictionary,
	objective_type: String
) -> void:
	var plan: Dictionary = offer.get("mission_conversation_plan", {}) \
		if offer.get("mission_conversation_plan", {}) is Dictionary else {}
	var bundle: Dictionary = offer.get("mission_dialogue_bundle", {}) \
		if offer.get("mission_dialogue_bundle", {}) is Dictionary else {}
	_expect(not plan.is_empty(), "Offer missing conversation plan for %s." % objective_type)
	_expect(not bundle.is_empty(), "Offer missing dialogue bundle for %s." % objective_type)
	if plan.is_empty() or bundle.is_empty():
		return
	var validation: Dictionary = DialogueBundleValidatorType.validate_bundle(
		bundle,
		plan,
		{"name": str(offer.get("agent_name", ""))}
	)
	_expect(
		bool(validation.get("ok", false)),
		"Offer dialogue bundle failed validation for %s: %s" % [
			objective_type,
			str(validation.get("errors", [])),
		]
	)
	var intent_ids: Array = plan.get("intent_ids", [])
	_expect(
		intent_ids.has("clarify_term") and intent_ids.has("accept_standard"),
		"Offer conversation plan missing required intents for %s." % objective_type
	)
	_expect(
		str(bundle.get("opening", "")).contains(str(offer.get("title", ""))),
		"Offer dialogue bundle opening does not reference its title for %s." % objective_type
	)
	_expect(
		str(bundle.get("opening", "")).contains("trusted"),
		"Offer dialogue bundle opening does not preserve relationship tier for %s." % objective_type
	)
	_expect(
		str(offer.get("mission_dialogue_bundle_source", ""))
				== "deterministic_fallback"
			and bool(offer.get("mission_dialogue_bundle_degraded", false))
			and str(offer.get("mission_dialogue_bundle_degraded_reason", ""))
				== "template_safe_emergency_composer",
		"Offer dialogue bundle fallback provenance was not explicit for %s." %
			objective_type
	)
	var diagnostics := _generation_diagnostics()
	if diagnostics != null and diagnostics.has_method("summary"):
		var summary: Dictionary = diagnostics.summary()
		var by_type: Dictionary = summary.get("by_type", {}) \
			if summary.get("by_type", {}) is Dictionary else {}
		var by_reason: Dictionary = summary.get("by_reason", {}) \
			if summary.get("by_reason", {}) is Dictionary else {}
		_expect(
			int(by_type.get("mission_conversation_bundle", 0)) > 0
				and int(by_reason.get(
					"template_safe_emergency_composer",
					0
				)) > 0,
			"Offer dialogue fallback was not recorded in generation diagnostics."
		)


func _profile_for_objective(objective_type: String) -> Dictionary:
	return {
		"agent_id": "agent.test",
		"agent_name": "Jenna Kross",
		"agent_role": "Frontier Station Contact",
		"relationship_respect": 7,
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


func _generation_diagnostics() -> Node:
	return root.get_node_or_null("GenerationDiagnostics")
