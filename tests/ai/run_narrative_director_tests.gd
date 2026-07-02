extends SceneTree

const DirectorType := preload("res://scripts/ai/NarrativeDirector.gd")
const BibleStoreType := preload("res://scripts/persistence/CampaignBibleStore.gd")
const ValidationResultType := preload("res://scripts/domain/ValidationResult.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_campaign_bible_prompt_includes_guardrails()
	_test_parses_campaign_bible_response()
	_test_repairs_safe_campaign_bible_drift()
	_test_rejects_invalid_campaign_bible_response()
	_test_parses_kaelen_angle_from_response()
	_test_repairs_missing_kaelen_angle_with_fallback()
	_test_validation_correction_notes_formats_errors()
	_test_correction_notes_injected_into_retry_prompt()
	_test_repair_telemetry_records_fired_repairs()
	_test_normalized_bible_stores_creative_lane()
	_test_motif_similarity_detection()
	_test_motif_collision_note()
	_test_faction_triad_repair_and_normalize()

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


func _test_validation_correction_notes_formats_errors() -> void:
	var empty := ValidationResultType.new()
	_expect(
		DirectorType.validation_correction_notes(empty) == "",
		"A valid ValidationResult should produce no correction notes."
	)
	var validation := ValidationResultType.new()
	validation.add_error("missing_field", "field cannot be empty", "kaelen_angle")
	validation.add_error("bad_role", "Kaelen must remain a broker.")
	var notes := DirectorType.validation_correction_notes(validation)
	_expect(
		notes.contains("[kaelen_angle]") and notes.contains("field cannot be empty"),
		"Correction notes should include the field path and message."
	)
	_expect(
		notes.contains("Kaelen must remain a broker."),
		"Correction notes should include pathless error messages."
	)


func _test_correction_notes_injected_into_retry_prompt() -> void:
	var baseline := _baseline_bible()
	var first := DirectorType.build_campaign_bible_prompt(baseline, "")
	_expect(
		not first.contains("previous attempt failed validation"),
		"First-attempt prompt should not carry a correction block."
	)
	var retry := DirectorType.build_campaign_bible_prompt(
		baseline,
		"",
		"- [kaelen_rule] Kaelen must publicly remain a broker, fixer, or contract handler."
	)
	_expect(
		retry.contains("previous attempt failed validation"),
		"Retry prompt should announce the prior validation failure."
	)
	_expect(
		retry.contains("Kaelen must publicly remain a broker"),
		"Retry prompt should include the specific correction notes."
	)
	_expect(
		retry.contains("Return exactly this object shape:"),
		"Retry prompt should still include the JSON shape spec after corrections."
	)


func _test_repair_telemetry_records_fired_repairs() -> void:
	# Drifted input that should trigger several distinct safe repairs.
	var drifted := {
		"title": "An Aliased Title",  # key_alias:title->campaign_title
		"rumor_trail": {"name": "Solo Trail"},  # alias + object_to_array:rumor_trails
		"kaelen_rule": "She keeps to herself and knows everyone worth knowing.",  # masked
		"kaelen_angle": "",  # defaulted
	}
	var repairs: Array = []
	DirectorType._repaired_generated_campaign_bible(drifted, repairs)
	_expect(
		repairs.has("key_alias:title->campaign_title"),
		"Repair telemetry did not record the title key alias. Got: %s" % str(repairs)
	)
	_expect(
		repairs.has("object_to_array:rumor_trails"),
		"Repair telemetry did not record the rumor_trails object->array coercion."
	)
	_expect(
		repairs.has("kaelen_public_role_masked"),
		"Repair telemetry did not record the Kaelen public-role mask."
	)
	_expect(
		repairs.has("kaelen_angle_defaulted"),
		"Repair telemetry did not record the Kaelen angle default."
	)

	# A clean input should record no repairs.
	var clean_repairs: Array = []
	DirectorType._repaired_generated_campaign_bible(
		{
			"campaign_title": "Clean",
			"kaelen_rule": "Kaelen is a broker.",
			"kaelen_angle": "She owes a debt.",
			"factions": {"zenith": "Z problem.", "aurelia": "A problem.", "vanguard": "V problem."},
		},
		clean_repairs
	)
	_expect(
		clean_repairs.is_empty(),
		"Clean input should fire no repairs. Got: %s" % str(clean_repairs)
	)


func _test_normalized_bible_stores_creative_lane() -> void:
	var baseline := _baseline_bible()
	var normalized := DirectorType._normalized_campaign_bible(
		{"campaign_title": "Any"},
		baseline,
		"gemma4:12b"
	)
	var lane := str(normalized.get("creative_lane", "")).strip_edges()
	_expect(not lane.is_empty(), "Normalized bible did not store a creative_lane.")
	var expected := DirectorType._creative_lane_for_seed(str(baseline.get("campaign_seed", "")))
	_expect(
		lane == str(expected.get("name", "")),
		"Stored creative_lane (%s) did not match the seed's deterministic lane (%s)." %
			[lane, str(expected.get("name", ""))]
	)


func _test_motif_similarity_detection() -> void:
	# The "Zenith X" collapse — shared distinctive first word, low Jaccard.
	_expect(
		DirectorType.is_text_too_similar("The Zenith Paradox", "The Zenith Drift"),
		"'Zenith X' near-duplicate titles should be flagged."
	)
	# High word overlap should flag even without a shared first word.
	_expect(
		DirectorType.is_text_too_similar(
			"Debt and the Broken Ledger",
			"The Broken Ledger of Debt"
		),
		"High-overlap titles should be flagged."
	)
	# Genuinely distinct titles must pass.
	_expect(
		not DirectorType.is_text_too_similar("The Silted Vein", "Sovereign Debt"),
		"Distinct titles should not be flagged."
	)
	_expect(
		not DirectorType.is_text_too_similar("The Scavenger's Ledger", "Orbital Scarcity"),
		"Distinct titles should not be flagged."
	)
	# Empty inputs never flag.
	_expect(
		not DirectorType.is_text_too_similar("", "The Zenith Drift"),
		"Empty candidate should never be flagged as similar."
	)
	# Reveal-length text: same core twist phrased differently should flag.
	_expect(
		DirectorType.is_text_too_similar(
			"The insurance fraud hid illicit mineral movements as lost cargo.",
			"Illicit mineral movements were hidden as lost cargo insurance fraud."
		),
		"Reworded but substantially overlapping reveals should be flagged."
	)


func _test_motif_collision_note() -> void:
	var bible := {
		"campaign_title": "The Zenith Drift",
		"long_term_reveal": "A quiet debt scheme forecloses sectors to enrich shareholders.",
	}
	# Title collides with a recent one.
	var note := DirectorType.motif_collision_note(
		bible, ["The Zenith Paradox"], []
	)
	_expect(
		note.contains("campaign_title") and note.contains("different"),
		"Colliding title should produce a correction note. Got: %s" % note
	)
	# Reveal collides.
	var reveal_note := DirectorType.motif_collision_note(
		bible, [], ["A debt scheme quietly forecloses sectors to enrich shareholders."]
	)
	_expect(
		reveal_note.contains("long_term_reveal"),
		"Colliding reveal should produce a correction note. Got: %s" % reveal_note
	)
	# No collision against distinct history.
	_expect(
		DirectorType.motif_collision_note(bible, ["The Silted Vein"], ["Toxic ore coverup."]) == "",
		"Distinct history should produce no collision note."
	)


func _test_faction_triad_repair_and_normalize() -> void:
	# Missing/partial triad: repair fills all three anchors, records telemetry,
	# and accepts a per-faction object form ({problem: ...}).
	var drifted := {
		"factions": {
			"zenith": "Zenith is quietly foreclosing on debtor stations.",
			"aurelia": {"problem": "Aurelia's trade permits are being forged."},
			# vanguard missing entirely
		},
	}
	var repairs: Array = []
	var repaired := DirectorType._repaired_generated_campaign_bible(drifted, repairs)
	var factions: Dictionary = repaired.get("factions", {})
	_expect(
		str(factions.get("zenith", "")).contains("foreclosing"),
		"Repair should preserve a valid faction problem string."
	)
	_expect(
		str(factions.get("aurelia", "")).contains("forged"),
		"Repair should extract 'problem' from a per-faction object."
	)
	_expect(
		not str(factions.get("vanguard", "")).strip_edges().is_empty(),
		"Repair should fill a placeholder for a missing anchor faction."
	)
	_expect(
		repairs.has("faction_problem_defaulted:vanguard"),
		"Repair telemetry should record the defaulted vanguard faction."
	)

	# Normalize copies the generated factions through to the stored bible.
	var normalized := DirectorType._normalized_campaign_bible(
		{"factions": {"zenith": "Z", "aurelia": "A", "vanguard": "V"}},
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(
		normalized.get("factions", {}) is Dictionary
			and str(normalized["factions"].get("vanguard", "")) == "V",
		"Normalized bible did not carry the generated factions triad."
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
