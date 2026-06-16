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
