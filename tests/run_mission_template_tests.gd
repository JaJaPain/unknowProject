extends SceneTree

const MissionTemplateType := preload("res://scripts/domain/MissionTemplate.gd")
const MissionTemplateRegistryType := preload("res://scripts/domain/MissionTemplateRegistry.gd")
const MissionTextGeneratorType := preload("res://scripts/domain/MissionTextGenerator.gd")
const PublicBoardTextGeneratorType := preload("res://scripts/domain/PublicBoardTextGenerator.gd")
const PublicBoardOfferBuilderType := preload("res://scripts/domain/PublicBoardOfferBuilder.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_registry_has_all_templates()
	_test_template_fields()
	_test_board_validation_accepts_good_payload()
	_test_board_validation_rejects_missing_field()
	_test_board_validation_rejects_missing_placeholder()
	_test_board_validation_rejects_forbidden_mechanic()
	_test_board_validation_rejects_drop_percent()
	_test_kaelen_disgust_required()
	_test_kaelen_authorship_blocked()
	_test_fallback_payload_returns_valid()
	_test_apply_payload_renders_placeholders()
	_test_wrapper_delegates_correctly()
	_test_offer_builder_constants_match()
	_test_agent_template_no_kaelen_rule()

	if _failures.is_empty():
		print("OK: All mission template tests passed.")
	else:
		for f in _failures:
			push_error(f)
		print("FAIL: %d mission template test(s) failed." % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_registry_has_all_templates() -> void:
	var ids := [
		MissionTemplateRegistryType.TEMPLATE_DELIVER_ORE_PUBLIC,
		MissionTemplateRegistryType.TEMPLATE_PICKUP_SPECIAL_PUBLIC,
		MissionTemplateRegistryType.TEMPLATE_RECOVER_COMBAT_DROP,
		MissionTemplateRegistryType.TEMPLATE_DELIVER_ORE_AGENT,
		MissionTemplateRegistryType.TEMPLATE_KILL_SHIPS_AGENT,
		MissionTemplateRegistryType.TEMPLATE_PICKUP_SPECIAL_AGENT,
		MissionTemplateRegistryType.TEMPLATE_TARGET_WITH_COMMS_REVERSAL,
	]
	for id in ids:
		_expect(
			MissionTemplateRegistryType.has_template(id),
			"Registry missing template: %s" % id
		)
		var t = MissionTemplateRegistryType.get_template(id)
		_expect(t != null, "get_template returned null for: %s" % id)


func _test_template_fields() -> void:
	var t = MissionTemplateRegistryType.get_template("DELIVER_ORE_PUBLIC")
	_expect(t.objective_type == "DELIVER_ORE", "Wrong objective_type")
	_expect(t.source_lane == "BOARD", "Wrong source_lane")
	_expect(t.write_fields.size() == 5, "Board template should have 5 write_fields")
	_expect(t.get_field_limit("title") == 96, "Title limit should be 96")
	_expect(t.has_rule(MissionTemplateRegistryType.KAELEN_DISGUST_RULE), "Should have kaelen_disgust rule")


func _test_board_validation_accepts_good_payload() -> void:
	var t = MissionTemplateRegistryType.get_template("DELIVER_ORE_PUBLIC")
	var offer := {"required_placeholders": ["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"], "placeholder_values": {}}
	var payload := {
		"title": "Need {ORE_AMOUNT} Ore",
		"poster": "Some Guy",
		"body": "Deliver to {TURN_IN_LOCATION}.",
		"briefing": "Bring {ORE_AMOUNT} to {TURN_IN_LOCATION}.",
		"kaelen_turn_in": "Public board work. I can smell the standards dropping from here.",
	}
	var result = MissionTextGeneratorType.validate_payload(t, offer, payload)
	_expect(bool(result.get("ok", false)), "Good payload should validate: %s" % str(result))


func _test_board_validation_rejects_missing_field() -> void:
	var t = MissionTemplateRegistryType.get_template("DELIVER_ORE_PUBLIC")
	var offer := {"required_placeholders": ["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"], "placeholder_values": {}}
	var payload := {
		"title": "Need Ore",
		"poster": "Guy",
		"body": "Deliver.",
		"briefing": "Do it.",
	}
	var result = MissionTextGeneratorType.validate_payload(t, offer, payload)
	_expect(not bool(result.get("ok", false)), "Missing kaelen_turn_in should fail")


func _test_board_validation_rejects_missing_placeholder() -> void:
	var t = MissionTemplateRegistryType.get_template("DELIVER_ORE_PUBLIC")
	var offer := {"required_placeholders": ["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"], "placeholder_values": {}}
	var payload := {
		"title": "Need Ore",
		"poster": "Guy",
		"body": "Deliver to station.",
		"briefing": "Bring ore.",
		"kaelen_turn_in": "Public board slumming it.",
	}
	var result = MissionTextGeneratorType.validate_payload(t, offer, payload)
	_expect(not bool(result.get("ok", false)), "Missing placeholders should fail")


func _test_board_validation_rejects_forbidden_mechanic() -> void:
	var t = MissionTemplateRegistryType.get_template("DELIVER_ORE_PUBLIC")
	var offer := {"required_placeholders": ["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"], "placeholder_values": {}}
	var payload := {
		"title": "Need {ORE_AMOUNT} Ore",
		"poster": "Guy",
		"body": "Land on the planet surface and deliver to {TURN_IN_LOCATION}.",
		"briefing": "Bring {ORE_AMOUNT} to {TURN_IN_LOCATION}.",
		"kaelen_turn_in": "Public board slumming it.",
	}
	var result = MissionTextGeneratorType.validate_payload(t, offer, payload)
	_expect(not bool(result.get("ok", false)), "Forbidden mechanic should fail")


func _test_board_validation_rejects_drop_percent() -> void:
	var t = MissionTemplateRegistryType.get_template("RECOVER_COMBAT_DROP")
	var offer := {"required_placeholders": ["{TARGET_FACTION}", "{ITEM_NAME}", "{TURN_IN_LOCATION}"], "placeholder_values": {}}
	var payload := {
		"title": "Find {ITEM_NAME} in {TARGET_FACTION} Wrecks",
		"poster": "Adjuster",
		"body": "33% drop chance from {TARGET_FACTION} to get {ITEM_NAME} at {TURN_IN_LOCATION}.",
		"briefing": "Search for {ITEM_NAME}.",
		"kaelen_turn_in": "Public board slumming. I can smell the grime.",
	}
	var result = MissionTextGeneratorType.validate_payload(t, offer, payload)
	_expect(not bool(result.get("ok", false)), "Drop percent should fail for recovery template")


func _test_kaelen_disgust_required() -> void:
	var t = MissionTemplateRegistryType.get_template("DELIVER_ORE_PUBLIC")
	var offer := {"required_placeholders": ["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"], "placeholder_values": {}}
	var payload := {
		"title": "Need {ORE_AMOUNT} Ore",
		"poster": "Guy",
		"body": "Deliver to {TURN_IN_LOCATION}.",
		"briefing": "Bring {ORE_AMOUNT} to {TURN_IN_LOCATION}.",
		"kaelen_turn_in": "Job done. Credits cleared.",
	}
	var result = MissionTextGeneratorType.validate_payload(t, offer, payload)
	_expect(not bool(result.get("ok", false)), "Kaelen without disgust cues should fail")


func _test_kaelen_authorship_blocked() -> void:
	var t = MissionTemplateRegistryType.get_template("DELIVER_ORE_PUBLIC")
	var offer := {"required_placeholders": ["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"], "placeholder_values": {}}
	var payload := {
		"title": "Need {ORE_AMOUNT} Ore",
		"poster": "Guy",
		"body": "Deliver to {TURN_IN_LOCATION}.",
		"briefing": "Bring {ORE_AMOUNT} to {TURN_IN_LOCATION}.",
		"kaelen_turn_in": "I posted this job and the public board stains are showing.",
	}
	var result = MissionTextGeneratorType.validate_payload(t, offer, payload)
	_expect(not bool(result.get("ok", false)), "Kaelen authorship claim should fail")


func _test_fallback_payload_returns_valid() -> void:
	var ids := [
		MissionTemplateRegistryType.TEMPLATE_DELIVER_ORE_PUBLIC,
		MissionTemplateRegistryType.TEMPLATE_PICKUP_SPECIAL_PUBLIC,
		MissionTemplateRegistryType.TEMPLATE_RECOVER_COMBAT_DROP,
		MissionTemplateRegistryType.TEMPLATE_TARGET_WITH_COMMS_REVERSAL,
	]
	for id in ids:
		var t = MissionTemplateRegistryType.get_template(id)
		var fb = MissionTextGeneratorType.fallback_payload(t, {}, 0)
		_expect(not fb.is_empty(), "Fallback for %s should not be empty" % id)
		for field in t.write_fields:
			_expect(fb.has(field), "Fallback for %s missing field %s" % [id, field])


func _test_apply_payload_renders_placeholders() -> void:
	var t = MissionTemplateRegistryType.get_template("DELIVER_ORE_PUBLIC")
	var offer := {
		"template_id": "DELIVER_ORE_PUBLIC",
		"required_placeholders": ["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"],
		"placeholder_values": {
			"{ORE_AMOUNT}": "40 m3",
			"{TURN_IN_LOCATION}": "the main station",
		},
		"quest_data": {
			"title": "placeholder",
			"dialogue": "placeholder",
			"objective": {"type": "DELIVER_ORE"},
		},
	}
	var payload := {
		"title": "[URGENT] {ORE_AMOUNT} Ore Needed",
		"poster": "Dockhand",
		"body": "Need {ORE_AMOUNT} at {TURN_IN_LOCATION}.",
		"briefing": "Bring {ORE_AMOUNT} to {TURN_IN_LOCATION}.",
		"kaelen_turn_in": "The {ORE_AMOUNT} ore is logged. Public board slumming, really?",
	}
	var result = MissionTextGeneratorType.apply_payload_to_offer(t, offer, payload, false)
	_expect(bool(result.get("ok", false)), "Apply should succeed: %s" % str(result))
	var rendered_offer: Dictionary = result.get("offer", {})
	_expect(
		str(rendered_offer.get("title", "")).contains("40 m3"),
		"Title should have rendered placeholder"
	)
	_expect(
		not str(rendered_offer.get("title", "")).contains("{ORE_AMOUNT}"),
		"Title should not contain raw placeholder"
	)
	var qd: Dictionary = rendered_offer.get("quest_data", {})
	_expect(qd.get("public_board", false) == true, "quest_data should have public_board flag")
	_expect(str(qd.get("title", "")).contains("40 m3"), "quest_data title should be rendered")


func _test_wrapper_delegates_correctly() -> void:
	var offer := {
		"template_id": "DELIVER_ORE_PUBLIC",
		"required_placeholders": ["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"],
		"placeholder_values": {},
	}
	var req = PublicBoardTextGeneratorType.build_generation_request(offer)
	_expect(not str(req.get("prompt", "")).is_empty(), "Wrapper build_generation_request should return prompt")
	_expect(req.get("template_id", "") == "DELIVER_ORE_PUBLIC", "Should pass through template_id")

	var fb = PublicBoardTextGeneratorType.fallback_payload(offer, 0)
	_expect(fb.has("title"), "Wrapper fallback should have title")

	var bad_payload := {"title": "x"}
	var result = PublicBoardTextGeneratorType.validate_payload(offer, bad_payload)
	_expect(not bool(result.get("ok", false)), "Wrapper validate should reject bad payload")


func _test_offer_builder_constants_match() -> void:
	_expect(
		PublicBoardOfferBuilderType.TEMPLATE_DELIVER_ORE == MissionTemplateRegistryType.TEMPLATE_DELIVER_ORE_PUBLIC,
		"OfferBuilder DELIVER_ORE constant should match registry"
	)
	_expect(
		PublicBoardOfferBuilderType.TEMPLATE_PICKUP_SPECIAL == MissionTemplateRegistryType.TEMPLATE_PICKUP_SPECIAL_PUBLIC,
		"OfferBuilder PICKUP_SPECIAL constant should match registry"
	)
	_expect(
		PublicBoardOfferBuilderType.TEMPLATE_RECOVER_COMBAT_DROP == MissionTemplateRegistryType.TEMPLATE_RECOVER_COMBAT_DROP,
		"OfferBuilder RECOVER_COMBAT_DROP constant should match registry"
	)


func _test_agent_template_no_kaelen_rule() -> void:
	var ids := [
		MissionTemplateRegistryType.TEMPLATE_DELIVER_ORE_AGENT,
		MissionTemplateRegistryType.TEMPLATE_KILL_SHIPS_AGENT,
		MissionTemplateRegistryType.TEMPLATE_PICKUP_SPECIAL_AGENT,
	]
	for id in ids:
		var t = MissionTemplateRegistryType.get_template(id)
		_expect(
			not t.has_rule(MissionTemplateRegistryType.KAELEN_DISGUST_RULE),
			"Agent template %s should not have kaelen_disgust rule" % id
		)
		_expect(t.source_lane == "AGENT", "Agent template %s should have AGENT lane" % id)
