extends SceneTree

const DirectorType := preload("res://scripts/ai/NarrativeDirector.gd")
const BibleStoreType := preload("res://scripts/persistence/CampaignBibleStore.gd")
const ValidationResultType := preload("res://scripts/domain/ValidationResult.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_campaign_bible_prompt_includes_guardrails()
	_test_parses_campaign_bible_response()
	_test_parses_labeled_campaign_bible_response()
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
	_test_variety_axes_in_prompt_and_bible()
	_test_lane_rotation_against_history()
	_test_kaelen_hint_fields()
	_test_nova_fields_repair_and_normalize()
	_test_plot_armor_validation()

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
	_expect(prompt.contains("Do NOT write JSON"), "Prompt should forbid JSON and require @@label blocks.")
	_expect(prompt.contains("@@campaign_title"), "Prompt did not use the @@label output protocol.")
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


# Exercises the PRIMARY (labeled @@block) parse path with deliberately messy
# output, proving code owns all structure: enum case/period normalization,
# trail_id prefix dedup, integer extraction from prose, and the guaranteed
# banned_repeats phrases.
func _test_parses_labeled_campaign_bible_response() -> void:
	var labeled := "\n".join([
		"Here is the campaign bible:",
		"@@campaign_title",
		"The Hollowed Vein",
		"@@campaign_logline",
		"A broke pilot untangles a refinery fraud before three factions pin it on her.",
		"@@opening_situation",
		"You are a broke independent pilot. A lone Reaver-class hostile is closing over Zenith space.",
		"@@main_mystery",
		"Who manufactured the debt that ensnares every local player.",
		"@@act_1_outline",
		"- Take the only job on the board.",
		"- The manifest lists cargo never loaded.",
		"- Kaelen offers to bury it, for a price.",
		"@@long_term_reveal",
		"The refinery collapse was engineered to erase a debt ledger.",
		"@@tone",
		"dry, wary, blue-collar",
		"@@core_pressure",
		"Everyone needs the refinery running and no one can afford the truth.",
		"@@factions.zenith",
		"Zenith lost its refining permits and is quietly bleeding credits.",
		"@@factions.aurelia",
		"Aurelia buys stranded cargo at pennies and calls it charity.",
		"@@factions.vanguard",
		"Vanguard impounds ships to look useful to the council.",
		"@@kaelen_rule",
		"Kaelen is publicly a contract broker who handles the board jobs nobody wants.",
		"@@kaelen_angle",
		"She holds the original debt ledger and knows who really owns the refinery.",
		"@@kaelen_hint_plan",
		"- She never charges for jobs near the refinery.",
		"- She flinches when old permit numbers come up.",
		"- She knows dock schedules she should not.",
		"@@kaelen_hint_style",
		"deflect-with-jokes",
		"@@kaelen_never_reveal",
		"Who she was before she started brokering here.",
		"@@faction_reveal_rule",
		"New factions surface only through gate travel and rumor.",
		"@@humor_rule",
		"Dry gallows humor about paperwork and repair bills.",
		"@@address_rule",
		"NPCs call the player by ship name or 'pilot'.",
		"@@fallback_rule",
		"If story data is missing, fall back to generic board-job framing.",
		"@@story_horizon_rule",
		"Append a new horizon past the gate; never retcon prior choices.",
		"@@story_arc.name",
		"Ledger of the Hollowed Vein",
		"@@story_arc.summary",
		"Trace the manifest fraud back to the missing debt ledger.",
		"@@rumor.name",
		"The Manifest That Loaded Itself",
		"@@rumor.trail_id",
		"rumor_trail.hollow_manifest",
		"@@rumor.hint_theme",
		"Cargo that exists on paper but never in a hold.",
		"@@rumor.clue_templates",
		"- A manifest listing crates nobody remembers loading.",
		"- A dock worker who flinches at the name Vale.",
		"@@rumor.discovery_type",
		"Faction_Secret.",
		"@@rumor.rarity",
		"uncommon",
		"@@rumor.payoff",
		"The buried ledger naming the refinery's true owner.",
		"@@trigger.id",
		"low_prepared_systems",
		"@@trigger.metric",
		"prepared_systems_remaining",
		"@@trigger.threshold",
		"about 2 systems left",
		"@@trigger.action",
		"append_story_horizon",
		"@@trigger.description",
		"When prepared systems run low, extend the horizon past the gate.",
		"@@expansion_rules",
		"- Reveal new ore and upgrades only through gate travel.",
		"- Escalate faction pressure as the ledger surfaces.",
		"@@banned_repeats",
		"- space taxes",
	])
	var result := DirectorType.parse_campaign_bible_response(
		JSON.stringify({"response": labeled}),
		_baseline_bible(),
		"gemma4:e4b"
	)
	_expect(bool(result.get("ok", false)), _failure_text(result))
	var bible: Dictionary = result.get("bible", {})
	_expect(
		str(bible.get("campaign_title", "")) == "The Hollowed Vein",
		"Labeled parse did not read campaign_title."
	)
	_expect(
		(bible.get("act_1_outline", []) as Array).size() == 3,
		"Labeled parse did not split act_1_outline into three items."
	)
	var trail: Dictionary = bible.get("rumor_trails", [])[0]
	_expect(
		str(trail.get("trail_id", "")) == "rumor_trail.hollow_manifest",
		"Labeled parse did not dedup the rumor_trail. prefix (got '%s')." % str(trail.get("trail_id", ""))
	)
	_expect(
		str(trail.get("discovery_type", "")) == "faction_secret",
		"Labeled parse did not normalize the enum case/period (got '%s')." % str(trail.get("discovery_type", ""))
	)
	var trigger: Dictionary = bible.get("regeneration_triggers", [])[0]
	_expect(
		int(trigger.get("threshold", -1)) == 2,
		"Labeled parse did not extract the integer threshold (got '%s')." % str(trigger.get("threshold", ""))
	)
	var banned: Array = bible.get("banned_repeats", [])
	var banned_lower := ""
	for b in banned:
		banned_lower += str(b).to_lower() + "|"
	_expect(
		banned_lower.contains("chosen one") and banned_lower.contains("destiny"),
		"Labeled parse did not guarantee the required banned_repeats phrases."
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
		retry.contains("@@campaign_title"),
		"Retry prompt should still include the @@label field spec after corrections."
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
			"kaelen_hint_plan": ["A hint."],
			"kaelen_hint_style": "dry jokes",
			"kaelen_never_reveal": "Her origin stays unknown.",
			"nova_quirk": "I count the airlock cycles. Someone has to.",
			"nova_memory_flicker": "A registry stub she cannot open reacts to the refinery's name.",
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


func _test_variety_axes_in_prompt_and_bible() -> void:
	var baseline := _baseline_bible()
	var prompt := DirectorType.build_campaign_bible_prompt(baseline, "")
	_expect(
		prompt.contains("Opening type:") and prompt.contains("Mystery shape:")
			and prompt.contains("Pressure type:"),
		"Prompt did not include the opening/mystery/pressure variety axes."
	)
	_expect(
		prompt.contains("exactly one starter Reaver-class hostile"),
		"Prompt did not keep the tutorial-safety guard alongside the axes."
	)

	# Normalized bible stores each axis' chosen name, matching the deterministic pick.
	var normalized := DirectorType._normalized_campaign_bible({"campaign_title": "A"}, baseline, "gemma4:12b")
	var seed_text := str(baseline.get("campaign_seed", ""))
	_expect(
		str(normalized.get("opening_type", "")) == str(DirectorType._axis_for_seed(seed_text, DirectorType.OPENING_TYPES, 101).get("name", ""))
			and not str(normalized.get("opening_type", "")).is_empty(),
		"Stored opening_type did not match the deterministic axis pick."
	)
	_expect(
		not str(normalized.get("mystery_shape", "")).is_empty()
			and not str(normalized.get("pressure_type", "")).is_empty(),
		"Normalized bible did not store mystery_shape/pressure_type."
	)

	# Axes are salted apart from the lane: at least one axis differs from the lane
	# index for a representative seed (sanity that salts actually shift the hash).
	_expect(
		DirectorType._axis_for_seed("seedA", DirectorType.MYSTERY_SHAPES, 211).has("name"),
		"_axis_for_seed returned no option for a non-empty table."
	)


func _test_lane_rotation_against_history() -> void:
	# The lane a seed normally picks, with no history.
	var natural := str(DirectorType._creative_lane_for_seed("424242").get("name", ""))
	_expect(not natural.is_empty(), "Lane selection returned nothing for a seed.")
	# Excluding that lane must pick a different one.
	var rotated := str(DirectorType._creative_lane_for_seed("424242", [natural]).get("name", ""))
	_expect(
		rotated != natural and not rotated.is_empty(),
		"Excluding the natural lane did not rotate to a different lane."
	)
	# Excluding every lane falls back to the full set (never empty).
	var all_names: Array = []
	for lane in DirectorType.CREATIVE_LANES:
		all_names.append(str(lane.get("name", "")))
	_expect(
		not str(DirectorType._creative_lane_for_seed("424242", all_names).get("name", "")).is_empty(),
		"Excluding all lanes should fall back to the full set, not return empty."
	)
	# _recent_lanes is honored in the prompt and stripped from the stored bible.
	var baseline := _baseline_bible()
	baseline["_recent_lanes"] = [natural]
	var normalized := DirectorType._normalized_campaign_bible({"campaign_title": "A"}, baseline, "gemma4:12b")
	_expect(
		str(normalized.get("creative_lane", "")) != natural,
		"Normalized bible stored a lane that should have been rotated away from history."
	)
	_expect(
		not normalized.has("_recent_lanes"),
		"Transient _recent_lanes hint leaked into the stored bible."
	)


func _test_kaelen_hint_fields() -> void:
	# Missing hint fields get defaulted (with telemetry); a string hint_plan is
	# coerced to an array; valid values pass through normalize.
	var repairs: Array = []
	var repaired := DirectorType._repaired_generated_campaign_bible(
		{"kaelen_hint_plan": "She overpays for silence."},
		repairs
	)
	_expect(
		repaired.get("kaelen_hint_plan", null) is Array
			and (repaired["kaelen_hint_plan"] as Array).size() == 1,
		"String kaelen_hint_plan should be coerced to a one-item array."
	)
	_expect(
		repairs.has("string_to_array:kaelen_hint_plan")
			and repairs.has("kaelen_hint_style_defaulted")
			and repairs.has("kaelen_never_reveal_defaulted"),
		"Kaelen hint repair telemetry not recorded. Got: %s" % str(repairs)
	)

	var normalized := DirectorType._normalized_campaign_bible(
		{
			"kaelen_hint_plan": ["Hint one.", "Hint two."],
			"kaelen_hint_style": "over-precise details",
			"kaelen_never_reveal": "Her origin stays unknown.",
		},
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(
		(normalized.get("kaelen_hint_plan", []) as Array).size() == 2
			and str(normalized.get("kaelen_hint_style", "")) == "over-precise details"
			and str(normalized.get("kaelen_never_reveal", "")) == "Her origin stays unknown.",
		"Normalized bible did not carry the Kaelen hint fields."
	)


func _test_nova_fields_repair_and_normalize() -> void:
	# Missing nova fields default with telemetry (a model that skips the labels
	# still yields a working campaign).
	var repairs: Array = []
	var repaired := DirectorType._repaired_generated_campaign_bible({}, repairs)
	_expect(
		not str(repaired.get("nova_quirk", "")).strip_edges().is_empty()
			and not str(repaired.get("nova_memory_flicker", "")).strip_edges().is_empty(),
		"Missing nova fields were not defaulted by repair."
	)
	_expect(
		repairs.has("nova_quirk_defaulted") and repairs.has("nova_memory_flicker_defaulted"),
		"Nova repair telemetry not recorded. Got: %s" % str(repairs)
	)
	# Aliases: nova_secret -> nova_memory_flicker, nova_habit -> nova_quirk.
	var aliased_repairs: Array = []
	var aliased := DirectorType._repaired_generated_campaign_bible(
		{
			"nova_habit": "I recount the cargo manifest during every burn.",
			"nova_secret": "A checksum in her boot log matches a ship that no longer exists.",
		},
		aliased_repairs
	)
	_expect(
		str(aliased.get("nova_quirk", "")).contains("manifest")
			and str(aliased.get("nova_memory_flicker", "")).contains("checksum"),
		"Nova key aliases were not applied."
	)
	# Explicit values round-trip through normalization into the stored bible.
	var normalized := DirectorType._normalized_campaign_bible(
		{
			"nova_quirk": "I audit the coolant loop hourly. It knows what it did.",
			"nova_memory_flicker": "One wiped nav entry still hums when the gate spins up.",
		},
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(
		str(normalized.get("nova_quirk", "")).contains("coolant")
			and str(normalized.get("nova_memory_flicker", "")).contains("nav entry"),
		"Normalized bible did not carry the nova fields."
	)
	# The bible prompt itself asks for the fields and states the protection.
	var prompt := DirectorType.build_campaign_bible_prompt(_baseline_bible(), "")
	_expect(
		prompt.contains("@@nova_quirk") and prompt.contains("@@nova_memory_flicker"),
		"Prompt did not request the nova @@labels."
	)
	_expect(
		prompt.contains("N.O.V.A. and Kaelen can never die"),
		"Prompt did not include the N.O.V.A./Kaelen plot-armor constraint."
	)


func _test_plot_armor_validation() -> void:
	# Direct offense detection.
	_expect(
		not DirectorType.plot_armor_offense("In the finale, Kaelen dies to save the station.").is_empty(),
		"'Kaelen dies' was not flagged as a plot-armor offense."
	)
	_expect(
		not DirectorType.plot_armor_offense("The syndicate plans to kill Kaelen at the handoff.").is_empty(),
		"'kill Kaelen' was not flagged."
	)
	_expect(
		not DirectorType.plot_armor_offense("Nova is destroyed when the relay overloads.").is_empty(),
		"'Nova is destroyed' was not flagged."
	)
	_expect(
		not DirectorType.plot_armor_offense("They will erase N.O.V.A and reflash the core.").is_empty(),
		"'erase N.O.V.A' was not flagged."
	)
	# Legitimate usage must pass: Kaelen assigning kill work, dead third parties,
	# celestial novas, and lookalike tokens.
	_expect(
		DirectorType.plot_armor_offense("Kaelen wants the depot destroyed before the audit.").is_empty(),
		"Kaelen assigning destruction work should not be flagged."
	)
	_expect(
		DirectorType.plot_armor_offense("Kaelen studies the manifest of the dead smuggler.").is_empty(),
		"Kaelen near a dead third party should not be flagged."
	)
	_expect(
		DirectorType.plot_armor_offense("The refinery star goes nova in old miner tales.").is_empty(),
		"Celestial 'goes nova' should not be flagged."
	)
	_expect(
		DirectorType.plot_armor_offense("Supernovae killed the first survey team.").is_empty(),
		"'Supernovae' should not count as the character Nova."
	)
	# A generated bible carrying an offense fails validation with the right code.
	var doomed := _valid_generated_bible()
	doomed["long_term_reveal"] = "The campaign ends when Kaelen is killed by her old partner."
	var result := DirectorType.parse_campaign_bible_response(
		JSON.stringify({"response": JSON.stringify(doomed)}),
		_baseline_bible(),
		"gemma4:12b"
	)
	_expect(not bool(result.get("ok", true)), "A bible that kills Kaelen was accepted.")
	var validation: ValidationResult = result.get("validation")
	var codes: Array[String] = []
	if validation != null:
		for error in validation.errors:
			codes.append(str(error.get("code", "")))
	_expect(
		"plot_armor_violation" in codes,
		"Kaelen-death bible did not report plot_armor_violation. Got: %s" % str(codes)
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
