class_name NarrativeDirector
extends RefCounted

const CampaignBibleStoreType := preload(
	"res://scripts/persistence/CampaignBibleStore.gd"
)
const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const CREATIVE_LANES := [
	{
		"name": "criminal economy",
		"guidance": "center smuggling, forged manifests, protection rackets, stolen cargo, and who profits when legal trade breaks.",
	},
	{
		"name": "corporate espionage",
		"guidance": "center deniable sabotage, leaked patents, dirty audits, black-budget security, and contracts that hide ownership.",
	},
	{
		"name": "infrastructure collapse",
		"guidance": "center failing stations, broken relays, unsafe gates, repair scarcity, and factions blaming each other for neglect.",
	},
	{
		"name": "political succession",
		"guidance": "center leadership disputes, emergency powers, contested permits, quiet coups, and brokers selling access.",
	},
	{
		"name": "salvage rights",
		"guidance": "center wreck claims, disputed manifests, dead ships, insurance fraud, and evidence hidden in recovered parts.",
	},
	{
		"name": "debt and privatization",
		"guidance": "center repossession, company towns, privatized security, predatory loans, and survival under owned infrastructure.",
	},
	{
		"name": "ecological or industrial hazard",
		"guidance": "center toxic ore, failing life support, unsafe extraction, poisoned habitats, and coverups disguised as accidents.",
	},
]


static func build_campaign_bible_prompt(
	baseline_bible: Dictionary,
	idea_memory_context: String = "",
	correction_notes: String = ""
) -> String:
	var campaign_seed := str(baseline_bible.get("campaign_seed", ""))
	var creative_lane := _creative_lane_for_seed(campaign_seed)
	var idea_block := "No prior idea memory yet."
	if not idea_memory_context.strip_edges().is_empty():
		idea_block = idea_memory_context.strip_edges()
	# When a prior attempt failed validation, LLMInterface feeds the specific
	# errors back so the retry can fix exactly what broke instead of rerolling
	# blind. Empty on the first attempt.
	var correction_lines: Array[String] = []
	if not correction_notes.strip_edges().is_empty():
		correction_lines = [
			"",
			"IMPORTANT: your previous attempt failed validation. Fix these exact problems and return corrected JSON:",
			correction_notes.strip_edges(),
		]
	return "\n".join([
		"You are the large local story model for a procedural space game.",
		"Create a compact first-horizon campaign bible for one new campaign.",
		"Be concise. This is a startup-critical request; short valid JSON is better than rich prose.",
		"",
		"Hard constraints:",
		"- Keep the handcrafted first system anchored by Zenith, Aurelia, and Vanguard.",
		"- Do not reveal future frontier factions to the player up front.",
		"- Kaelen is the only fixed recurring NPC besides the player.",
		"- Kaelen cannot die and her full mystery must never be completely solved.",
		"- Kaelen must publicly appear as a broker, fixer, or contract handler, not a scavenger, scientist, commander, prophet, mechanic, AI, archive, or failsafe.",
		"- Kaelen's hidden identity can be strange, mundane, human, non-human, technological, or unknown, but the story bible must frame it as hidden director knowledge only.",
		"- kaelen_angle is HIDDEN director-only knowledge: what she secretly knows or did. It must never restate kaelen_rule's public role, and must never be shown to the player or to small-model prompts.",
		"- New systems should reveal new factions, conflicts, ores, upgrades, rumors, and ships through gate travel.",
		"- Use dry, slightly dark PG-13 humor. Avoid repeating example jokes or catchphrases.",
		"- Include exactly one rumor trail that can eventually lead to a hidden discovery or endgame easter egg.",
		"- The rumor trail needs exactly two concrete clue templates and a discovery type.",
		"- Include exactly one story horizon regeneration trigger with a metric, threshold, and action.",
		"- If story extends later, append a new horizon. Do not retcon known player choices.",
		"- Keep every string under 140 characters unless the field says otherwise.",
		"",
		"Campaign seed: %s" % campaign_seed,
		"Creative lane for this campaign: %s." % str(creative_lane.get("name", "")),
		"Lane guidance: %s" % str(creative_lane.get("guidance", "")),
		"",
		"Anti-motif guidance:",
		"- Do not use a 'Zenith [single abstract noun]' title pattern.",
		"- Avoid overusing Kaelen-as-AI/archive/failsafe unless it is genuinely the freshest fit for this specific campaign lane.",
		"- Do not use Great Silence, Great Collapse, purge protocol, ancient signal, ghost signal, prophecy, alien owner, mysterious pulse, chosen one, or destiny as the core reveal.",
		"- Prefer campaign-facing secrets the player can chase through jobs: debt, fraud, leverage, sabotage, jurisdiction, inheritance, stolen cargo, repair scarcity, hidden ownership, or carefully buried identity hints.",
		"- Make the reveal fit the chosen creative lane instead of defaulting to cosmic explanation.",
		"",
		"Existing idea memory:",
		idea_block,
	] + correction_lines + [
		"",
		"Return only JSON. No markdown. No comments.",
		"Return exactly this object shape:",
		"{",
		"  \"campaign_title\": string,",
		"  \"campaign_logline\": string under 220 chars,",
		"  \"opening_situation\": string under 260 chars,",
		"  \"main_mystery\": string under 220 chars,",
		"  \"act_1_outline\": [three strings under 180 chars each],",
		"  \"long_term_reveal\": string under 220 chars,",
		"  \"tone\": string,",
		"  \"core_pressure\": string,",
		"  \"kaelen_rule\": string that says she is publicly a broker, fixer, or contract handler,",
		"  \"kaelen_angle\": string under 220 chars — HIDDEN. What Kaelen secretly knows or did. Never shown to the player or small-model prompts. Director-only knowledge.,",
		"  \"faction_reveal_rule\": string,",
		"  \"humor_rule\": string,",
		"  \"address_rule\": string describing how NPCs address the player,",
		"  \"fallback_rule\": string describing how to handle missing story data,",
		"  \"story_horizon_rule\": string,",
		"  \"story_arcs\": [{\"name\": string, \"summary\": string under 180 chars}],",
		"  \"rumor_trails\": [{\"name\": string, \"trail_id\": \"rumor_trail.\" plus snake_case_id, \"clue_count\": 2, \"hint_theme\": string, \"clue_templates\": [two strings], \"discovery_type\": \"hidden_discovery|secret_route|rare_upgrade|faction_secret|endgame_easter_egg\", \"rarity\": \"local|uncommon|rare|legendary\", \"payoff\": string under 180 chars}],",
		"  \"regeneration_triggers\": [{\"id\": snake_case_string, \"metric\": \"prepared_systems_remaining|active_story_arcs_remaining|rumor_trails_remaining|major_arc_state\", \"threshold\": number, \"action\": \"append_story_horizon|append_rumor_trail|append_story_arc\", \"description\": string}],",
		"  \"expansion_rules\": [two strings],",
		"  \"banned_repeats\": [string]",
		"}",
		"Use exactly one story_arcs item, one rumor_trails item, and one regeneration_triggers item.",
	])


# Formats a failed ValidationResult into a compact, model-facing correction
# list for a retry prompt (see build_campaign_bible_prompt's correction_notes).
# One line per error: the field path (when known) plus the human message.
# Returns "" when there is nothing to correct.
static func validation_correction_notes(validation: ValidationResult) -> String:
	if validation == null or validation.is_valid():
		return ""
	var lines: Array[String] = []
	for issue in validation.errors:
		var path := str(issue.get("path", "")).strip_edges()
		var message := str(issue.get("message", "")).strip_edges()
		if message.is_empty():
			message = str(issue.get("code", "invalid field")).strip_edges()
		if path.is_empty():
			lines.append("- %s" % message)
		else:
			lines.append("- [%s] %s" % [path, message])
	return "\n".join(lines)


# ── Motif-repeat detection (plan §3.2) ──────────────────────────────────────────
# Cheap, code-side check so consecutive campaigns can't open with a near-duplicate
# title/reveal (e.g. "The Zenith Paradox" vs "The Zenith Drift"). No LLM call.
# Two signals, either of which flags a collision:
#   1. Distinctive-word Jaccard overlap >= threshold (default 0.6).
#   2. A shared distinctive FIRST word — catches the "Zenith X" title collapse
#      that Jaccard alone misses (only 1 shared word out of 3 => 0.33 < 0.6).
const _MOTIF_STOPWORDS := {
	"the": true, "of": true, "a": true, "an": true, "and": true, "in": true,
	"to": true, "for": true, "on": true, "at": true, "by": true, "with": true,
	"is": true, "it": true, "its": true, "this": true, "that": true,
}


static func is_text_too_similar(candidate: String, prior: String, threshold := 0.6) -> bool:
	var c := candidate.strip_edges()
	var p := prior.strip_edges()
	if c.is_empty() or p.is_empty():
		return false
	if text_similarity(c, p) >= threshold:
		return true
	var cf := _first_distinctive_word(c)
	var pf := _first_distinctive_word(p)
	return not cf.is_empty() and cf == pf


# Jaccard overlap of the two texts' distinctive-word sets (0.0 .. 1.0).
static func text_similarity(a: String, b: String) -> float:
	var wa := _motif_words(a)
	var wb := _motif_words(b)
	if wa.is_empty() or wb.is_empty():
		return 0.0
	var intersection := 0
	for word in wa:
		if wb.has(word):
			intersection += 1
	var union := wb.size()
	for word in wa:
		if not wb.has(word):
			union += 1
	if union == 0:
		return 0.0
	return float(intersection) / float(union)


static func _motif_words(text: String) -> Dictionary:
	var out := {}
	var lower := text.to_lower()
	var token := ""
	for i in range(lower.length()):
		var c := lower[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			token += c
			continue
		if token.length() >= 3 and not _MOTIF_STOPWORDS.has(token):
			out[token] = true
		token = ""
	if token.length() >= 3 and not _MOTIF_STOPWORDS.has(token):
		out[token] = true
	return out


# Returns a model-facing correction note if the generated bible's title or
# reveal is too similar to any recent campaign's (from idea memory), else "".
# Used as a SOFT signal: LLMInterface retries with this note appended, but a
# collision on the final attempt is accepted rather than blocking game start —
# a slightly similar title beats no campaign.
static func motif_collision_note(
	bible: Dictionary,
	recent_titles: Array,
	recent_reveals: Array
) -> String:
	var title := str(bible.get("campaign_title", "")).strip_edges()
	for prior in recent_titles:
		if is_text_too_similar(title, str(prior)):
			return (
				"campaign_title '%s' is too similar to a recent campaign's title. " % title
				+ "Choose a clearly different, unrelated title."
			)
	var reveal := str(bible.get("long_term_reveal", "")).strip_edges()
	for prior in recent_reveals:
		if is_text_too_similar(reveal, str(prior)):
			return (
				"long_term_reveal repeats a recent campaign's core twist. "
				+ "Choose a clearly different reveal."
			)
	return ""


static func _first_distinctive_word(text: String) -> String:
	var lower := text.to_lower()
	var token := ""
	for i in range(lower.length()):
		var c := lower[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			token += c
			continue
		if token.length() >= 3 and not _MOTIF_STOPWORDS.has(token):
			return token
		token = ""
	if token.length() >= 3 and not _MOTIF_STOPWORDS.has(token):
		return token
	return ""


static func _creative_lane_for_seed(campaign_seed: String) -> Dictionary:
	if CREATIVE_LANES.is_empty():
		return {}
	var accumulator := 0
	for index in range(campaign_seed.length()):
		accumulator += campaign_seed.unicode_at(index) * (index + 1)
	return CREATIVE_LANES[abs(accumulator) % CREATIVE_LANES.size()]


static func parse_campaign_bible_response(
	envelope_text: String,
	baseline_bible: Dictionary,
	model_name: String
) -> Dictionary:
	var envelope := DomainJsonType.parse_object(envelope_text, "campaign_bible_envelope")
	var envelope_validation := envelope["validation"] as ValidationResult
	if not envelope_validation.is_valid():
		return _failure("response_envelope_parse_failed", envelope_validation)
	var envelope_data: Dictionary = envelope["data"]
	if not envelope_data.has("response"):
		var missing_response := ValidationResultType.new()
		missing_response.add_error(
			"response_envelope_missing_response",
			"Ollama response envelope did not include a response field."
		)
		return _failure("response_envelope_missing_response", missing_response)
	var response_text := str(envelope_data.get("response", "")).strip_edges()
	var parsed := DomainJsonType.parse_object(response_text, "campaign_bible_response")
	var response_validation := parsed["validation"] as ValidationResult
	if not response_validation.is_valid():
		return _failure("response_json_parse_failed", response_validation)
	var repairs: Array = []
	var repaired_generated := _repaired_generated_campaign_bible(parsed["data"], repairs)
	var generated_validation := _validate_campaign_bible_shape(repaired_generated)
	if not generated_validation.is_valid():
		return _failure("campaign_bible_validation_failed", generated_validation)
	var bible := _normalized_campaign_bible(
		repaired_generated,
		baseline_bible,
		model_name
	)
	var validation := _validate_campaign_bible_shape(bible)
	if not validation.is_valid():
		return _failure("campaign_bible_validation_failed", validation)
	return {"ok": true, "bible": bible, "repairs": repairs}


# repairs (optional) accumulates the name of each repair that actually changed
# something, so LLMInterface can log which safe repairs fired (model-drift
# signal — see docs/storytelling_architecture_plan.md §4 Tier 1). Empty when no
# repair was needed.
static func _repaired_generated_campaign_bible(generated: Dictionary, repairs: Array = []) -> Dictionary:
	var repaired := _repair_text_tree(generated.duplicate(true)) as Dictionary
	_apply_key_aliases(
		repaired,
		{
			"campaign_name": "campaign_title",
			"title": "campaign_title",
			"logline": "campaign_logline",
			"campaign_summary": "campaign_logline",
			"opening": "opening_situation",
			"mystery": "main_mystery",
			"act_one_outline": "act_1_outline",
			"act_i_outline": "act_1_outline",
			"longterm_reveal": "long_term_reveal",
			"long_term_reveal_direction": "long_term_reveal",
			"kaelen": "kaelen_rule",
			"kaelen_public_rule": "kaelen_rule",
			"kaelen_secret": "kaelen_angle",
			"kaelen_hidden_angle": "kaelen_angle",
			"angle": "kaelen_angle",
			"faction_rule": "faction_reveal_rule",
			"humor": "humor_rule",
			"fallback": "fallback_rule",
			"story_horizon": "story_horizon_rule",
			"story_arc": "story_arcs",
			"story_arc_list": "story_arcs",
			"rumor_trail": "rumor_trails",
			"rumor__trails": "rumor_trails",
			"regeneration_trigger": "regeneration_triggers",
			"regeneration_trigger_list": "regeneration_triggers",
			"expansion_rule": "expansion_rules",
			"banned_repeat": "banned_repeats",
		},
		repairs
	)
	for field in ["story_arcs", "rumor_trails", "regeneration_triggers"]:
		if repaired.get(field, null) is Dictionary:
			repaired[field] = [repaired[field]]
			repairs.append("object_to_array:%s" % field)
	for field in ["act_1_outline", "expansion_rules", "banned_repeats"]:
		if repaired.get(field, null) is String:
			repaired[field] = [str(repaired.get(field, "")).strip_edges()]
			repairs.append("string_to_array:%s" % field)
	_repair_kaelen_public_role(repaired, repairs)
	_repair_kaelen_angle(repaired, repairs)
	_repair_rumor_trails(repaired, repairs)
	_repair_regeneration_triggers(repaired)
	_repair_banned_repeats(repaired)
	return repaired


static func _apply_key_aliases(
	target: Dictionary,
	aliases: Dictionary,
	repairs: Array = []
) -> void:
	for source_key in aliases.keys():
		var target_key := str(aliases[source_key])
		if target.has(source_key) and not target.has(target_key):
			target[target_key] = target[source_key]
			repairs.append("key_alias:%s->%s" % [source_key, target_key])


static func _repair_kaelen_angle(target: Dictionary, repairs: Array = []) -> void:
	if str(target.get("kaelen_angle", "")).strip_edges().is_empty():
		target["kaelen_angle"] = (
			"Kaelen has a personal stake in how this campaign's central conflict resolves, " +
			"but never explains why."
		)
		repairs.append("kaelen_angle_defaulted")


static func _repair_kaelen_public_role(target: Dictionary, repairs: Array = []) -> void:
	var original := str(target.get("kaelen_rule", "")).strip_edges()
	if original.is_empty():
		return
	var lower := original.to_lower()
	if lower.contains("broker") or lower.contains("fixer") or lower.contains("contract"):
		return
	if lower.contains("public") or lower.contains("appears as") or lower.contains("works as"):
		for public_role in ["mechanic", "scientist", "commander", "prophet", " ai", "archive", "failsafe"]:
			if lower.contains(public_role):
				return
	for forbidden in [" ai", "archive", "failsafe", "uploaded mind", "non-human"]:
		if lower.contains(forbidden.strip_edges()):
			return
	target["kaelen_rule"] = (
		"Kaelen publicly works as a broker and fixer; %s" % original
	)
	repairs.append("kaelen_public_role_masked")


static func _repair_rumor_trails(target: Dictionary, repairs: Array = []) -> void:
	var trails: Array = target.get("rumor_trails", []) if target.get("rumor_trails", []) is Array else []
	for index in range(trails.size()):
		if not trails[index] is Dictionary:
			continue
		var trail: Dictionary = trails[index]
		_apply_key_aliases(
			trail,
			{
				"trail": "trail_id",
				"id": "trail_id",
				"clues": "clue_templates",
				"templates": "clue_templates",
				"type": "discovery_type",
				"reward": "payoff",
			},
			repairs
		)
		var trail_id := _snake_case_id(str(trail.get("trail_id", trail.get("name", "local_trail"))))
		if not trail_id.begins_with("rumor_trail."):
			trail_id = "rumor_trail.%s" % trail_id.trim_prefix("rumor_trail_")
		trail["trail_id"] = trail_id
		if not trail.get("clue_templates", []) is Array:
			trail["clue_templates"] = [str(trail.get("clue_templates", "")).strip_edges()]
		var clues: Array = trail.get("clue_templates", [])
		while clues.size() < 2:
			clues.append("A dockside rumor repeats the same suspicious detail.")
		trail["clue_templates"] = clues
		trail["clue_count"] = max(2, int(trail.get("clue_count", clues.size())))
		if str(trail.get("discovery_type", "")).strip_edges().is_empty():
			trail["discovery_type"] = "hidden_discovery"
		if str(trail.get("rarity", "")).strip_edges().is_empty():
			trail["rarity"] = "local"
		var payoff := str(trail.get("payoff", "")).strip_edges()
		var payoff_lower := payoff.to_lower()
		if payoff_lower.contains("hidden faction") or payoff_lower.contains("future faction"):
			trail["payoff"] = (
				"Unlocks evidence of an unnamed outside power without revealing it yet."
			)
			repairs.append("rumor_payoff_faction_leak_masked")


static func _repair_regeneration_triggers(target: Dictionary) -> void:
	var triggers: Array = (
		target.get("regeneration_triggers", [])
		if target.get("regeneration_triggers", []) is Array else []
	)
	for index in range(triggers.size()):
		if not triggers[index] is Dictionary:
			continue
		var trigger: Dictionary = triggers[index]
		_apply_key_aliases(
			trigger,
			{
				"trigger_id": "id",
				"when": "metric",
				"operation": "action",
			}
		)
		trigger["id"] = _snake_case_id(str(trigger.get("id", "story_horizon_trigger")))


static func _repair_banned_repeats(target: Dictionary) -> void:
	var repeats: Array = (
		target.get("banned_repeats", [])
		if target.get("banned_repeats", []) is Array else []
	)
	for required in ["chosen one", "destiny"]:
		var found := false
		for repeat in repeats:
			if str(repeat).to_lower() == required:
				found = true
				break
		if not found:
			repeats.append(required)
	target["banned_repeats"] = repeats


static func _repair_text_tree(value: Variant) -> Variant:
	if value is Dictionary:
		var copy := {}
		for key in (value as Dictionary).keys():
			copy[key] = _repair_text_tree((value as Dictionary)[key])
		return copy
	if value is Array:
		var fixed: Array = []
		for item in value:
			fixed.append(_repair_text_tree(item))
		return fixed
	if value is String:
		return _repair_common_text(str(value))
	return value


static func _repair_common_text(value: String) -> String:
	return value \
		.replace("â€™", "'") \
		.replace("â€œ", "\"") \
		.replace("â€", "\"") \
		.replace("â€“", "-") \
		.replace("â€”", "-") \
		.replace("’", "'") \
		.replace("“", "\"") \
		.replace("”", "\"") \
		.replace("–", "-") \
		.replace("—", "-")


static func _snake_case_id(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	var output := ""
	var previous_underscore := false
	for index in range(clean.length()):
		var code := clean.unicode_at(index)
		var is_alnum := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if is_alnum:
			output += char(code)
			previous_underscore = false
		elif clean[index] == ".":
			if not output.ends_with("."):
				output += "."
			previous_underscore = false
		elif not previous_underscore:
			output += "_"
			previous_underscore = true
	output = output.strip_edges()
	while output.begins_with("_") or output.begins_with("."):
		output = output.substr(1)
	while output.ends_with("_") or output.ends_with("."):
		output = output.substr(0, output.length() - 1)
	return output if not output.is_empty() else "generated_story_id"


static func _normalized_campaign_bible(
	generated: Dictionary,
	baseline: Dictionary,
	model_name: String
) -> Dictionary:
	var bible := baseline.duplicate(true)
	var generated_copy := generated.duplicate(true)
	if generated_copy.has("rumor_trails"):
		generated_copy["rumor_trails"] = CampaignBibleStoreType.normalize_rumor_trails(
			generated_copy.get("rumor_trails", [])
		)
	if generated_copy.has("regeneration_triggers"):
		generated_copy["regeneration_triggers"] = (
			CampaignBibleStoreType.normalize_regeneration_triggers(
				generated_copy.get("regeneration_triggers", [])
			)
		)
	for field in [
		"campaign_title",
		"campaign_logline",
		"opening_situation",
		"main_mystery",
		"act_1_outline",
		"long_term_reveal",
		"tone",
		"core_pressure",
		"kaelen_rule",
		"kaelen_angle",
		"faction_reveal_rule",
		"humor_rule",
		"address_rule",
		"fallback_rule",
		"story_horizon_rule",
		"story_arcs",
		"rumor_trails",
		"regeneration_triggers",
		"expansion_rules",
		"banned_repeats",
	]:
		if generated_copy.has(field):
			bible[field] = generated_copy[field]
	bible["source"] = "llm"
	bible["generation_status"] = CampaignBibleStoreType.STATUS_LLM_GENERATED
	bible["source_model"] = model_name.strip_edges()
	bible["generation_note"] = "Campaign bible generated by the large-story local model."
	bible["last_generation_error"] = ""
	# Record the deterministic creative lane this campaign was generated under.
	# Not model-authored — derived from the seed the same way the prompt was —
	# so it's reliable metadata for the debug panel and cross-campaign lane
	# rotation (plan §3.1). Optional field; not required by bible validation.
	var lane := _creative_lane_for_seed(str(baseline.get("campaign_seed", "")))
	if not lane.is_empty():
		bible["creative_lane"] = str(lane.get("name", ""))
	return bible


static func _validate_campaign_bible_shape(bible: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	for field in [
		"campaign_title",
		"campaign_logline",
		"opening_situation",
		"main_mystery",
		"long_term_reveal",
		"tone",
		"core_pressure",
		"kaelen_rule",
		"kaelen_angle",
		"faction_reveal_rule",
		"humor_rule",
		"address_rule",
		"fallback_rule",
		"story_horizon_rule",
	]:
		if str(bible.get(field, "")).strip_edges().is_empty():
			result.add_error(
				"missing_campaign_bible_field",
				"Generated campaign bible field '%s' cannot be empty." % field,
				field
			)
	for array_field in [
		"act_1_outline",
		"story_arcs",
		"rumor_trails",
		"regeneration_triggers",
		"expansion_rules",
		"banned_repeats",
	]:
		if not bible.get(array_field, []) is Array:
			result.add_error(
				"invalid_campaign_bible_array",
				"Generated campaign bible field '%s' must be an array." % array_field,
				array_field
			)
	var kaelen_rule := str(bible.get("kaelen_rule", "")).to_lower()
	if not (
		kaelen_rule.contains("broker")
		or kaelen_rule.contains("fixer")
		or kaelen_rule.contains("contract")
	):
		result.add_error(
			"invalid_kaelen_public_role",
			"Kaelen must publicly remain a broker, fixer, or contract handler.",
			"kaelen_rule"
		)
	return result


static func _failure(reason: String, validation: ValidationResult) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"validation": validation,
	}


# ── Phase C: Story horizon expansion ───────────────────────────────────────────
# Fires only when a campaign's prepared act_1_outline/story_arcs/rumor_trails
# reserve is exhausted. Extends the campaign — never retcons or replaces
# existing canon. One action per call, matching the bible's own
# regeneration_trigger schema (action: append_story_horizon|append_rumor_trail|
# append_story_arc).
static func build_story_horizon_expansion_prompt(
	bible_data: Dictionary,
	trigger: Dictionary,
	story_state_summary: String
) -> String:
	var action := str(trigger.get("action", "append_story_horizon"))
	var shape := "{\"act_1_outline_addition\": [three strings under 180 chars each]}"
	if action == "append_story_arc":
		shape = "{\"story_arc\": {\"name\": string, \"summary\": string under 180 chars}}"
	elif action == "append_rumor_trail":
		shape = (
			"{\"rumor_trail\": {\"name\": string, \"trail_id\": \"rumor_trail.\" plus snake_case_id, "
			+ "\"clue_count\": 2, \"hint_theme\": string, \"clue_templates\": [two strings], "
			+ "\"discovery_type\": \"hidden_discovery|secret_route|rare_upgrade|faction_secret|endgame_easter_egg\", "
			+ "\"rarity\": \"local|uncommon|rare|legendary\", \"payoff\": string under 180 chars}}"
		)
	return "\n".join([
		"You are the large local story model for a procedural space game.",
		"This campaign's prepared story reserve is running low. Extend it — do not retcon or replace anything that already happened.",
		"Be concise. Short valid JSON is better than rich prose.",
		"",
		"Established campaign so far:",
		"- Title: %s" % str(bible_data.get("campaign_title", "")),
		"- Main mystery: %s" % str(bible_data.get("main_mystery", "")),
		"- Tone: %s" % str(bible_data.get("tone", "")),
		"- Core pressure: %s" % str(bible_data.get("core_pressure", "")),
		"",
		"Current state:",
		story_state_summary,
		"",
		"Reason for this expansion: %s" % str(trigger.get("description", "")),
		"",
		"Banned repeats (do not reuse): %s" % ", ".join(bible_data.get("banned_repeats", [])),
		"",
		"Return only JSON. No markdown. No comments. Return exactly this shape:",
		shape,
	])


static func parse_story_horizon_expansion_response(
	envelope_text: String,
	action: String,
	model_name: String
) -> Dictionary:
	var envelope := DomainJsonType.parse_object(envelope_text, "story_horizon_expansion_envelope")
	var envelope_validation := envelope["validation"] as ValidationResult
	if not envelope_validation.is_valid():
		return _failure("response_envelope_parse_failed", envelope_validation)
	var envelope_data: Dictionary = envelope["data"]
	if not envelope_data.has("response"):
		var missing_response := ValidationResultType.new()
		missing_response.add_error(
			"response_envelope_missing_response",
			"Ollama response envelope did not include a response field."
		)
		return _failure("response_envelope_missing_response", missing_response)
	var response_text := str(envelope_data.get("response", "")).strip_edges()
	var parsed := DomainJsonType.parse_object(response_text, "story_horizon_expansion_response")
	var response_validation := parsed["validation"] as ValidationResult
	if not response_validation.is_valid():
		return _failure("response_json_parse_failed", response_validation)
	var repaired := _repair_text_tree(parsed["data"]) as Dictionary
	var result := ValidationResultType.new()
	if action == "append_story_arc":
		var arc: Dictionary = repaired.get("story_arc", {})
		if str(arc.get("name", "")).strip_edges().is_empty() \
				or str(arc.get("summary", "")).strip_edges().is_empty():
			result.add_error("invalid_story_arc_addition", "story_arc must have name and summary.")
			return _failure("story_horizon_expansion_validation_failed", result)
		return {"ok": true, "action": action, "story_arc": arc, "model": model_name}
	if action == "append_rumor_trail":
		var trails := CampaignBibleStoreType.normalize_rumor_trails([repaired.get("rumor_trail", {})])
		if trails.is_empty():
			result.add_error("invalid_rumor_trail_addition", "rumor_trail could not be normalized.")
			return _failure("story_horizon_expansion_validation_failed", result)
		return {"ok": true, "action": action, "rumor_trail": trails[0], "model": model_name}
	var addition: Array = repaired.get("act_1_outline_addition", [])
	if addition.is_empty():
		result.add_error("invalid_act_1_outline_addition", "act_1_outline_addition must be non-empty.")
		return _failure("story_horizon_expansion_validation_failed", result)
	return {"ok": true, "action": action, "act_1_outline_addition": addition, "model": model_name}
