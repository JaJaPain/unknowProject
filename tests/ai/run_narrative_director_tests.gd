extends SceneTree

const DirectorType := preload("res://scripts/ai/NarrativeDirector.gd")
const BibleStoreType := preload("res://scripts/persistence/CampaignBibleStore.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_campaign_bible_prompt_includes_guardrails()
	_test_parses_campaign_bible_response()
	_test_repairs_safe_campaign_bible_drift()
	_test_rejects_invalid_campaign_bible_response()
	_test_parses_kaelen_angle_from_response()
	_test_repairs_missing_kaelen_angle_with_fallback()

	if _failures.is_empty():
		print("[PASS] Narrative director tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_campaign_bible_prompt_includes_guardrails() -> void:
	var baseline := _baseline_bible()
	var prompt := DirectorType.build_campaign_bible_prompt(
		baseline,
		"- used faction: Glass Choir\n- banned joke: space taxes"
	)
	_expect(prompt.contains("Campaign seed: 424242"), "Prompt did not include campaign seed.")
	_expect(prompt.contains("Kaelen cannot die"), "Prompt did not include Kaelen protection.")
	_expect(
		prompt.contains("Do not reveal future frontier factions"),
		"Prompt did not include no-spoiler faction rule."
	)
	_expect(
		prompt.contains("used faction: Glass Choir"),
		"Prompt did not include idea memory context."
	)
	_expect(
		prompt.contains("Creative lane for this campaign"),
		"Prompt did not include a deterministic creative lane."
	)
	_expect(
		prompt.contains("hidden identity can be strange"),
		"Prompt did not include the hidden Kaelen identity guidance."
	)
	_expect(
		prompt.contains("kaelen_angle") and prompt.contains("HIDDEN director-only knowledge"),
		"Prompt did not include the kaelen_angle field spec and director-only guardrail."
	)
	_expect(prompt.contains("Return only JSON"), "Prompt did not require JSON-only output.")
	_expect(
		prompt.contains("campaign_logline") and prompt.contains("act_1_outline"),
		"Prompt did not request explicit story fields."
	)


func _test_parses_campaign_bible_response() -> void:
	var generated := {
		"campaign_title": "The Aurelia Breach",
		"campaign_logline": "A station leak points to a route war moving faster than anyone admits.",
		"opening_situation": "The player reaches a worn frontier system where every faction is short on fuel, trust, and patience.",
		"main_mystery": "Someone is using gate interference to hide ships that should not exist yet.",
		"act_1_outline": [
			"Earn Kaelen's trust by surviving local work.",
			"Find evidence that Aurelia's leak is deliberate.",
			"Follow a ghost signal toward the first gate clue.",
		],
		"long_term_reveal": "Kaelen knows more about the gate interference than she can safely admit.",
		"tone": "Dry frontier danger with jokes sharp enough to leave marks.",
		"core_pressure": "A quiet route war is moving ahead of the player through the gates.",
		"kaelen_rule": "Kaelen publicly works as a broker and fixer; protect the mystery.",
		"faction_reveal_rule": "Reveal new factions only as gates and rumors expose them.",
		"humor_rule": "Use dark, dry humor and never repeat canned jokes.",
		"address_rule": "Use Indy sparingly, usually only in the opening request.",
		"fallback_rule": "Fallbacks are diagnostic failures, not authored content.",
		"story_horizon_rule": "Append future horizons without retconning known choices.",
		"story_arcs": [{
			"name": "Low Signal War",
			"summary": "Station outages hide a frontier proxy conflict.",
		}],
		"rumor_trails": [{
			"name": "The Third Echo",
			"trail_id": "rumor_trail.third_echo",
			"clue_count": 5,
			"hint_theme": "misheard distress calls that repeat from systems the player has not reached",
			"clue_templates": [
				"A dock worker quotes the same wrong call sign.",
				"A station contact claims the signal came from a dead relay.",
			],
			"discovery_type": "endgame_easter_egg",
			"rarity": "legendary",
			"payoff": "A hidden relay that changes Kaelen's eulogy options.",
		}],
		"regeneration_triggers": [{
			"id": "echo_clues_low",
			"metric": "rumor_trails_remaining",
			"threshold": 1,
			"action": "append_rumor_trail",
			"description": "The player has consumed most prepared echo clues.",
		}],
		"expansion_rules": [
			"Preserve alliances and enemies.",
			"Do not solve Kaelen.",
		],
		"banned_repeats": ["dad joke station tax"],
	}
	var envelope := {"response": JSON.stringify(generated)}
	var result := DirectorType.parse_campaign_bible_response(
		JSON.stringify(envelope),
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(bool(result.get("ok", false)), _failure_text(result))
	var bible: Dictionary = result.get("bible", {})
	_expect(
		str(bible.get("generation_status", "")) == BibleStoreType.STATUS_LLM_GENERATED,
		"Parsed bible did not mark llm_generated status."
	)
	_expect(
		str(bible.get("source_model", "")) == "gemma4:12b",
		"Parsed bible did not preserve model name."
	)
	_expect(
		str(bible.get("campaign_id", "")) == "campaign.test",
		"Parsed bible did not preserve baseline campaign id."
	)
	_expect(
		str(bible.get("core_pressure", "")).contains("route war"),
		"Parsed bible did not keep generated content."
	)
	_expect(
		str(bible.get("campaign_logline", "")).contains("route war"),
		"Parsed bible did not preserve explicit campaign story fields."
	)
	var trail: Dictionary = bible.get("rumor_trails", [])[0]
	_expect(
		str(trail.get("trail_id", "")) == "rumor_trail.third_echo"
			and str(trail.get("discovery_type", "")) == "endgame_easter_egg",
		"Parsed bible did not preserve structured rumor trail fields."
	)
	var trigger: Dictionary = bible.get("regeneration_triggers", [])[0]
	_expect(
		str(trigger.get("metric", "")) == "rumor_trails_remaining"
			and str(trigger.get("action", "")) == "append_rumor_trail",
		"Parsed bible did not preserve structured regeneration trigger fields."
	)


func _test_rejects_invalid_campaign_bible_response() -> void:
	var invalid := {"response": JSON.stringify({"tone": "not enough"})}
	var result := DirectorType.parse_campaign_bible_response(
		JSON.stringify(invalid),
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(not bool(result.get("ok", true)), "Invalid bible response was accepted.")
	_expect(
		str(result.get("reason", "")) == "campaign_bible_validation_failed",
		"Invalid bible response reported the wrong failure reason."
	)
	var bad_kaelen := _valid_generated_bible()
	bad_kaelen["kaelen_rule"] = "Kaelen publicly works as a station mechanic."
	var bad_result := DirectorType.parse_campaign_bible_response(
		JSON.stringify({"response": JSON.stringify(bad_kaelen)}),
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(not bool(bad_result.get("ok", true)), "Invalid Kaelen role was accepted.")
	var bad_validation: ValidationResult = bad_result.get("validation")
	var bad_codes: Array[String] = []
	if bad_validation != null:
		for error in bad_validation.errors:
			bad_codes.append(str(error.get("code", "")))
	_expect(
		"invalid_kaelen_public_role" in bad_codes,
		"Invalid public Kaelen role did not report the role validation failure."
	)
	var secret_kaelen := _valid_generated_bible()
	secret_kaelen["kaelen_rule"] = (
		"Kaelen publicly works as a broker and fixer; privately she may be an archive, "
		+ "failsafe, or something stranger, but this is hidden."
	)
	var secret_result := DirectorType.parse_campaign_bible_response(
		JSON.stringify({"response": JSON.stringify(secret_kaelen)}),
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(
		bool(secret_result.get("ok", false)),
		"Hidden strange Kaelen identity should be allowed when public role is correct."
	)


func _test_repairs_safe_campaign_bible_drift() -> void:
	var drifted := _valid_generated_bible()
	drifted["kaelen_rule"] = "Kaelen is a local scavenger who knows old station routes."
	drifted["rumor_trail"] = drifted["rumor_trails"][0]
	drifted.erase("rumor_trails")
	(drifted["rumor_trail"] as Dictionary)["trail_id"] = "Third Echo"
	(drifted["rumor_trail"] as Dictionary)["clue_count"] = 1
	(drifted["rumor_trail"] as Dictionary)["payoff"] = "Unlocks a hidden faction: The Purifiers."
	drifted["regeneration_trigger"] = drifted["regeneration_triggers"][0]
	drifted.erase("regeneration_triggers")
	(drifted["regeneration_trigger"] as Dictionary)["id"] = "Echo Clues.Low"
	var result := DirectorType.parse_campaign_bible_response(
		JSON.stringify({"response": JSON.stringify(drifted)}),
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(bool(result.get("ok", false)), _failure_text(result))
	var bible: Dictionary = result.get("bible", {})
	_expect(
		str(bible.get("kaelen_rule", "")).contains("broker and fixer"),
		"Safe Kaelen role drift was not repaired."
	)
	var trail: Dictionary = bible.get("rumor_trails", [])[0]
	_expect(
		str(trail.get("trail_id", "")) == "rumor_trail.third_echo"
			and int(trail.get("clue_count", 0)) >= 2,
		"Rumor trail alias/id/count drift was not repaired."
	)
	_expect(
		not str(trail.get("payoff", "")).contains("The Purifiers")
			and str(trail.get("payoff", "")).contains("unnamed outside power"),
		"Named future faction payoff was not repaired."
	)
	var trigger: Dictionary = bible.get("regeneration_triggers", [])[0]
	_expect(
		str(trigger.get("id", "")) == "echo_clues.low",
		"Regeneration trigger id drift was not repaired."
	)


func _test_parses_kaelen_angle_from_response() -> void:
	var generated := _valid_generated_bible()
	generated["kaelen_angle"] = "Kaelen personally profits from the route war continuing."
	var result := DirectorType.parse_campaign_bible_response(
		JSON.stringify({"response": JSON.stringify(generated)}),
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(bool(result.get("ok", false)), _failure_text(result))
	var bible: Dictionary = result.get("bible", {})
	_expect(
		str(bible.get("kaelen_angle", "")) == "Kaelen personally profits from the route war continuing.",
		"kaelen_angle did not round-trip into the normalized bible."
	)


func _test_repairs_missing_kaelen_angle_with_fallback() -> void:
	var generated := _valid_generated_bible()
	generated.erase("kaelen_angle")
	var result := DirectorType.parse_campaign_bible_response(
		JSON.stringify({"response": JSON.stringify(generated)}),
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(
		bool(result.get("ok", false)),
		"Missing kaelen_angle should be repaired with a fallback, not fail validation."
	)
	var bible: Dictionary = result.get("bible", {})
	_expect(
		not str(bible.get("kaelen_angle", "")).strip_edges().is_empty(),
		"Repaired bible did not fill a non-empty kaelen_angle fallback."
	)


func _valid_generated_bible() -> Dictionary:
	return {
		"campaign_title": "The Aurelia Breach",
		"campaign_logline": "A station leak points to a route war moving faster than anyone admits.",
		"opening_situation": "The player reaches a worn frontier system where every faction is short on fuel, trust, and patience.",
		"main_mystery": "Someone is using gate interference to hide ships that should not exist yet.",
		"act_1_outline": [
			"Earn Kaelen's trust by surviving local work.",
			"Find evidence that Aurelia's leak is deliberate.",
			"Follow a ghost signal toward the first gate clue.",
		],
		"long_term_reveal": "Kaelen knows more about the gate interference than she can safely admit.",
		"tone": "Dry frontier danger with jokes sharp enough to leave marks.",
		"core_pressure": "A quiet route war is moving ahead of the player through the gates.",
		"kaelen_rule": "Kaelen publicly works as a broker and fixer; protect the mystery.",
		"faction_reveal_rule": "Reveal new factions only as gates and rumors expose them.",
		"humor_rule": "Use dark, dry humor and never repeat canned jokes.",
		"address_rule": "Use Indy sparingly, usually only in the opening request.",
		"fallback_rule": "Fallbacks are diagnostic failures, not authored content.",
		"story_horizon_rule": "Append future horizons without retconning known choices.",
		"story_arcs": [{
			"name": "Low Signal War",
			"summary": "Station outages hide a frontier proxy conflict.",
		}],
		"rumor_trails": [{
			"name": "The Third Echo",
			"trail_id": "rumor_trail.third_echo",
			"clue_count": 5,
			"hint_theme": "misheard distress calls that repeat from systems the player has not reached",
			"clue_templates": [
				"A dock worker quotes the same wrong call sign.",
				"A station contact claims the signal came from a dead relay.",
			],
			"discovery_type": "endgame_easter_egg",
			"rarity": "legendary",
			"payoff": "A hidden relay that changes Kaelen's eulogy options.",
		}],
		"regeneration_triggers": [{
			"id": "echo_clues_low",
			"metric": "rumor_trails_remaining",
			"threshold": 1,
			"action": "append_rumor_trail",
			"description": "The player has consumed most prepared echo clues.",
		}],
		"expansion_rules": [
			"Preserve alliances and enemies.",
			"Do not solve Kaelen.",
		],
		"banned_repeats": ["dad joke station tax"],
	}


func _baseline_bible() -> Dictionary:
	var bible := BibleStoreType._default_bible("campaign.test", "424242")
	bible["campaign_seed"] = "424242"
	return bible


func _failure_text(result: Dictionary) -> String:
	var validation: Variant = result.get("validation")
	if validation != null and validation.has_method("summary"):
		return "%s: %s" % [str(result.get("reason", "")), validation.summary()]
	return str(result)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
