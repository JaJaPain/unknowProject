extends SceneTree

const DirectorType := preload("res://scripts/ai/NarrativeDirector.gd")
const BibleStoreType := preload("res://scripts/persistence/CampaignBibleStore.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_campaign_bible_prompt_includes_guardrails()
	_test_parses_campaign_bible_response()
	_test_rejects_invalid_campaign_bible_response()

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
	_expect(prompt.contains("Return only JSON"), "Prompt did not require JSON-only output.")


func _test_parses_campaign_bible_response() -> void:
	var generated := {
		"tone": "Dry frontier danger with jokes sharp enough to leave marks.",
		"core_pressure": "A quiet route war is moving ahead of the player through the gates.",
		"kaelen_rule": "Kaelen appears where profit and impossible maps overlap; protect the mystery.",
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
			"clue_count": 5,
			"payoff": "A hidden relay that changes Kaelen's eulogy options.",
		}],
		"regeneration_triggers": [{
			"id": "echo_clues_low",
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
