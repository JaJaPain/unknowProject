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

# Extra variety axes rotated independently of the lane (plan §3.5/§3.6). Each is
# chosen deterministically per seed with its own salt so they don't all track the
# lane. Injected as prompt guidance and stored in the bible for debug/rotation.
# All openings must stay tutorial-compatible: player broke, one starter Reaver,
# first mission simple — the opening only changes WHY the tutorial matters.
const OPENING_TYPES := [
	{"name": "broke-and-hungry", "guidance": "player starts broke and desperate for any paying work."},
	{"name": "inherited-a-problem", "guidance": "player inherited a debt, ship, or obligation that drags them in."},
	{"name": "owed-a-favor", "guidance": "someone owes the player, and calling it in starts the trouble."},
	{"name": "witnessed-something", "guidance": "the player saw something they shouldn't have at the wrong moment."},
	{"name": "wrong-place-wrong-time", "guidance": "the player is caught in a deal gone bad or mistaken for someone else."},
	{"name": "small-win-gone-sour", "guidance": "an early lucky break quietly turns into a liability."},
]
const MYSTERY_SHAPES := [
	{"name": "whodunit", "guidance": "a crime or event is known; who is behind it is not."},
	{"name": "whatisit", "guidance": "an actor is known; their real scheme is hidden."},
	{"name": "whereisit", "guidance": "something or someone is missing and must be traced."},
	{"name": "whyisit", "guidance": "an event is known; the motive behind it is buried."},
]
const PRESSURE_TYPES := [
	{"name": "debt-clock", "guidance": "a debt or deadline tightens over time."},
	{"name": "reputation-squeeze", "guidance": "factions are watching; standing is fragile."},
	{"name": "scarcity", "guidance": "a critical resource is drying up."},
	{"name": "protection-dependency", "guidance": "safety depends on someone who charges for it."},
	{"name": "legal-jeopardy", "guidance": "one wrong move brings jurisdiction down."},
]

# ── Labeled-field generation (gemma4:e4b) ───────────────────────────────────────
# gemma4:e4b writes good story CONTENT but cannot hold this ~25-key nested JSON
# tree together under format:"json" — it drops nested keys every run. So we never
# ask it for JSON. It answers flat @@label blocks (one label per field, "- " for
# list items) and CODE owns all structure: parse_labeled_blocks +
# assemble_campaign_bible_from_labels build the exact production shape here, so a
# brace/quote/comma error is impossible by construction. Prototyped and validated
# 2026-07-02 (5/5 seeds clean vs 0/N with format:json). See memory
# project_labeled_field_generation.
const _RUMOR_DISCOVERY_TYPES := [
	"hidden_discovery", "secret_route", "rare_upgrade", "faction_secret", "endgame_easter_egg",
]
const _RUMOR_RARITIES := ["local", "uncommon", "rare", "legendary"]
const _TRIGGER_METRICS := [
	"prepared_systems_remaining", "active_story_arcs_remaining",
	"rumor_trails_remaining", "major_arc_state",
]
const _TRIGGER_ACTIONS := ["append_story_horizon", "append_rumor_trail", "append_story_arc"]

# Each field is addressable by its @@label. `kind` drives coercion in assembly:
#   text -> one string; list -> one item per "- " line; enum -> normalized to
#   choices; int -> integer extracted; slug -> snake_case id (prefix added later).
# `guide` is the plain-language ask shown in the prompt (no JSON, no braces).
const _CAMPAIGN_BIBLE_LABEL_FIELDS := [
	{"label": "campaign_title", "kind": "text",
	 "guide": "A distinct campaign title. Not a 'Zenith <single abstract noun>' pattern."},
	{"label": "campaign_logline", "kind": "text",
	 "guide": "One-sentence logline of the campaign hook, under 220 chars."},
	{"label": "opening_situation", "kind": "text",
	 "guide": "The opening: a broke independent pilot facing exactly one starter Reaver-class hostile. Under 260 chars."},
	{"label": "main_mystery", "kind": "text",
	 "guide": "The central campaign mystery the player chases through jobs. Under 220 chars."},
	{"label": "act_1_outline", "kind": "list", "min": 3, "max": 3,
	 "guide": "Exactly THREE act-1 beats, one per line, each under 180 chars."},
	{"label": "long_term_reveal", "kind": "text",
	 "guide": "The eventual long-term reveal, fit to the lane; avoid cosmic cliche. Under 220 chars."},
	{"label": "tone", "kind": "text", "guide": "Campaign tone in a short phrase."},
	{"label": "core_pressure", "kind": "text", "guide": "The core pressure driving the campaign, under 140 chars."},
	{"label": "factions.zenith", "kind": "text",
	 "guide": "Zenith's one concrete local problem this campaign. Player-facing, not a hidden twist. Under 140 chars."},
	{"label": "factions.aurelia", "kind": "text",
	 "guide": "Aurelia's one concrete local problem this campaign. Under 140 chars."},
	{"label": "factions.vanguard", "kind": "text",
	 "guide": "Vanguard's one concrete local problem this campaign. Under 140 chars."},
	{"label": "kaelen_rule", "kind": "text", "must_contain": ["broker", "fixer", "contract"],
	 "guide": "States Kaelen is PUBLICLY a broker, fixer, or contract handler. Must use the word broker, fixer, or contract."},
	{"label": "kaelen_angle", "kind": "text",
	 "guide": "HIDDEN director-only: what Kaelen secretly knows or did. Never restates her public role. Never shown to the player. Under 220 chars."},
	{"label": "kaelen_hint_plan", "kind": "list", "min": 3, "max": 5,
	 "guide": "3 to 5 player-safe surface observations that only HINT at her secret (odd habits, small inconsistencies). One per line. Never explain the secret."},
	{"label": "kaelen_hint_style", "kind": "text",
	 "guide": "How Kaelen deflects this campaign, e.g. deflect-with-jokes, over-precise-details, selective-silence."},
	{"label": "kaelen_never_reveal", "kind": "text",
	 "guide": "HIDDEN: one line naming what must stay unresolved even at full trail completion."},
	{"label": "nova_quirk", "kind": "text",
	 "guide": "One campaign-specific habit or fixation for N.O.V.A., the ship's dry, self-preserving AI, written in HER first-person voice as a line she could say aloud (e.g. 'I audit the air filters hourly. Someone aboard has to have standards.'). Player-safe. Under 140 chars."},
	{"label": "nova_memory_flicker", "kind": "text",
	 "guide": "HIDDEN director-only: one corrupted fragment of N.O.V.A.'s wiped past that obliquely connects to the main mystery. Never shown to the player; surfaces only as glitch-flavored hints. Under 180 chars."},
	{"label": "faction_reveal_rule", "kind": "text",
	 "guide": "Rule for how new factions get revealed through gate travel."},
	{"label": "humor_rule", "kind": "text", "guide": "Rule for the dry, slightly dark PG-13 humor."},
	{"label": "address_rule", "kind": "text", "guide": "How NPCs address the player."},
	{"label": "fallback_rule", "kind": "text", "guide": "How to handle missing story data."},
	{"label": "story_horizon_rule", "kind": "text",
	 "guide": "Rule for extending the story with a new horizon later without retconning player choices."},
	{"label": "story_arc.name", "kind": "text", "guide": "Name of the single first story arc."},
	{"label": "story_arc.summary", "kind": "text", "guide": "Summary of that story arc, under 180 chars."},
	{"label": "rumor.name", "kind": "text", "guide": "Name of the single rumor trail."},
	{"label": "rumor.trail_id", "kind": "slug", "prefix": "rumor_trail.",
	 "guide": "A snake_case id for the rumor trail (letters, digits, underscores only). No prefix needed; code adds 'rumor_trail.'."},
	{"label": "rumor.hint_theme", "kind": "text", "guide": "The theme tying the rumor trail's clues together."},
	{"label": "rumor.clue_templates", "kind": "list", "min": 2, "max": 2,
	 "guide": "Exactly TWO concrete clue templates the player could encounter. One per line."},
	{"label": "rumor.discovery_type", "kind": "enum", "choices": _RUMOR_DISCOVERY_TYPES},
	{"label": "rumor.rarity", "kind": "enum", "choices": _RUMOR_RARITIES},
	{"label": "rumor.payoff", "kind": "text", "guide": "What the rumor trail eventually pays off into. Under 180 chars."},
	{"label": "trigger.id", "kind": "slug", "guide": "A snake_case id for the regeneration trigger (letters, digits, underscores only)."},
	{"label": "trigger.metric", "kind": "enum", "choices": _TRIGGER_METRICS},
	{"label": "trigger.threshold", "kind": "int", "guide": "A single integer threshold for the trigger metric."},
	{"label": "trigger.action", "kind": "enum", "choices": _TRIGGER_ACTIONS},
	{"label": "trigger.description", "kind": "text", "guide": "One line describing what the trigger does."},
	{"label": "expansion_rules", "kind": "list", "min": 2, "max": 2,
	 "guide": "Exactly TWO rules for how the campaign expands later. One per line."},
	{"label": "banned_repeats", "kind": "list", "min": 1, "max": 8,
	 "guide": "Phrases/motifs this campaign should never repeat. One per line. Include 'chosen one' and 'destiny'."},
]


static func build_campaign_bible_prompt(
	baseline_bible: Dictionary,
	idea_memory_context: String = "",
	correction_notes: String = ""
) -> String:
	var campaign_seed := str(baseline_bible.get("campaign_seed", ""))
	var excluded_lanes: Array = baseline_bible.get("_recent_lanes", []) if baseline_bible.get("_recent_lanes", []) is Array else []
	var creative_lane := _creative_lane_for_seed(campaign_seed, excluded_lanes)
	var opening := _axis_for_seed(campaign_seed, OPENING_TYPES, 101)
	var mystery := _axis_for_seed(campaign_seed, MYSTERY_SHAPES, 211)
	var pressure := _axis_for_seed(campaign_seed, PRESSURE_TYPES, 331)
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
		"- kaelen_hint_plan entries are player-safe SURFACE observations that only HINT at kaelen_angle (odd habits, small inconsistencies); they must never state or explain her secret.",
		"- N.O.V.A., the player's ship AI, is fixed cast alongside Kaelen: sardonic, self-preserving, the ship is her body. She and the player both woke with wiped memories after the gate accident.",
		"- N.O.V.A. and Kaelen can never die, be destroyed, deleted, or permanently removed in ANY beat, arc, rumor, or reveal. Do not write their deaths even as a threat that comes true.",
		"- nova_memory_flicker is HIDDEN director-only: one corrupted fragment of N.O.V.A.'s lost past that obliquely ties into the main mystery without explaining either.",
		"- New systems should reveal new factions, conflicts, ores, upgrades, rumors, and ships through gate travel.",
		"- Use dry, slightly dark PG-13 humor. Avoid repeating example jokes or catchphrases.",
		"- Include exactly one rumor trail that can eventually lead to a hidden discovery or endgame easter egg.",
		"- The rumor trail needs exactly two concrete clue templates and a discovery type.",
		"- Include exactly one story horizon regeneration trigger with a metric, threshold, and action.",
		"- Give each anchor faction (Zenith, Aurelia, Vanguard) one concrete local problem tied to this campaign's lane — player-facing world texture, not a hidden twist.",
		"- If story extends later, append a new horizon. Do not retcon known player choices.",
		"- Keep every string under 140 characters unless the field says otherwise.",
		"",
		"Campaign seed: %s" % campaign_seed,
		"Creative lane for this campaign: %s." % str(creative_lane.get("name", "")),
		"Lane guidance: %s" % str(creative_lane.get("guidance", "")),
		"Opening type: %s — %s" % [str(opening.get("name", "")), str(opening.get("guidance", ""))],
		"Mystery shape: %s — %s" % [str(mystery.get("name", "")), str(mystery.get("guidance", ""))],
		"Pressure type: %s — %s" % [str(pressure.get("name", "")), str(pressure.get("guidance", ""))],
		"Honor these axes, but keep the first mission simple and tutorial-safe: the player is broke and faces exactly one starter Reaver-class hostile.",
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
	] + correction_lines + _campaign_bible_label_protocol_lines())


# The output-format tail of build_campaign_bible_prompt: the labeled @@block
# protocol plus one instruction line per field, generated from
# _CAMPAIGN_BIBLE_LABEL_FIELDS so the prompt and parser can never drift apart.
static func _campaign_bible_label_protocol_lines() -> Array:
	var lines := [
		"",
		"OUTPUT FORMAT -- READ CAREFULLY:",
		"Do NOT write JSON. Do NOT use braces, brackets, quotes, or commas as structure.",
		"Answer each field as a block that starts with its label on its own line, prefixed by @@,",
		"then the value on the following line(s). Example:",
		"",
		"@@campaign_title",
		"The Hollowed Vein",
		"@@act_1_outline",
		"- First beat here.",
		"- Second beat here.",
		"- Third beat here.",
		"",
		"Rules:",
		"- One @@label line per field, spelled exactly as given below.",
		"- For list fields, put ONE item per line, each starting with \"- \".",
		"- Do not add labels that were not requested. Do not skip any requested label.",
		"- Plain ASCII text values only. No markdown headers, no numbering, no extra commentary.",
		"",
		"Answer ALL of these fields, each as its own @@label block:",
		"",
	]
	for field in _CAMPAIGN_BIBLE_LABEL_FIELDS:
		var kind := str(field.get("kind", "text"))
		var tag := ""
		match kind:
			"list": tag = " (list, one per line)"
			"enum": tag = " (pick one of: %s)" % ", ".join(field.get("choices", []))
			"int": tag = " (a whole number)"
			"slug": tag = " (snake_case)"
		var guide := str(field.get("guide", ""))
		var suffix := (" -- %s" % guide) if not guide.is_empty() else ""
		lines.append("@@%s%s%s" % [str(field.get("label", "")), tag, suffix])
	return lines


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


# excluded_names: recently-used lane names (from idea memory) to skip, so
# consecutive campaigns don't repeat a lane even when their seeds hash to the
# same one. Still deterministic per seed within the remaining pool. If every lane
# is excluded, falls back to the full set rather than returning nothing.
static func _creative_lane_for_seed(campaign_seed: String, excluded_names: Array = []) -> Dictionary:
	if CREATIVE_LANES.is_empty():
		return {}
	var pool: Array = []
	for lane in CREATIVE_LANES:
		if str(lane.get("name", "")) in excluded_names:
			continue
		pool.append(lane)
	if pool.is_empty():
		pool = CREATIVE_LANES
	var accumulator := 0
	for index in range(campaign_seed.length()):
		accumulator += campaign_seed.unicode_at(index) * (index + 1)
	return pool[abs(accumulator) % pool.size()]


# Deterministic per-seed pick from one variety-axis table. The salt shifts the
# hash so opening/mystery/pressure axes vary independently of each other and of
# the lane, while staying stable for a given seed (same seed → same campaign).
static func _axis_for_seed(campaign_seed: String, options: Array, salt: int) -> Dictionary:
	if options.is_empty():
		return {}
	var accumulator := salt
	for index in range(campaign_seed.length()):
		accumulator += campaign_seed.unicode_at(index) * (index + 1 + salt)
	return options[abs(accumulator) % options.size()]


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
	# Primary path: the model answers flat @@label blocks, not JSON (gemma4:e4b
	# can't hold the nested tree together). Structure is owned entirely by code.
	# Fallback path: if no @@blocks are present the response is legacy/other-model
	# JSON, so parse it as an object. Either way we hand a `generated` dict to the
	# same downstream repair + validation.
	var generated := {}
	var response_parse_error: ValidationResult = null
	var blocks := parse_labeled_blocks(response_text)
	if not blocks.is_empty():
		generated = assemble_campaign_bible_from_labels(blocks)
	else:
		var parsed := DomainJsonType.parse_object(response_text, "campaign_bible_response")
		var response_validation := parsed["validation"] as ValidationResult
		if not response_validation.is_valid():
			var extracted_response := _extract_json_object_text(response_text)
			if extracted_response != response_text:
				parsed = DomainJsonType.parse_object(
					extracted_response,
					"campaign_bible_response_extracted"
				)
				response_validation = parsed["validation"] as ValidationResult
		if response_validation.is_valid():
			generated = parsed["data"]
		else:
			response_parse_error = response_validation
	if response_parse_error != null:
		return _failure("response_parse_failed", response_parse_error)
	var repairs: Array = []
	var repaired_generated := _repaired_generated_campaign_bible(generated, repairs)
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


static func _extract_json_object_text(text: String) -> String:
	var start := text.find("{")
	var end := text.rfind("}")
	if start == -1 or end == -1 or end <= start:
		return text
	return text.substr(start, end - start + 1).strip_edges()


# ── Labeled-block parsing + assembly (gemma4:e4b) ───────────────────────────────
# Splits the model's @@label output into {label: [raw lines]}. Ignores any
# preamble before the first @@ and any label we didn't ask for. Tolerant of the
# model echoing the guide after a label ("@@label -- ...") by keeping the first
# token only.
static func parse_labeled_blocks(text: String) -> Dictionary:
	var blocks := {}
	var current := ""
	for raw_line in text.split("\n"):
		var line := str(raw_line)
		var stripped := line.strip_edges()
		if stripped.begins_with("@@"):
			var label := stripped.substr(2).strip_edges()
			var space_idx := label.find(" ")
			if space_idx != -1:
				label = label.substr(0, space_idx)
			var tab_idx := label.find("\t")
			if tab_idx != -1:
				label = label.substr(0, tab_idx)
			current = label.strip_edges()
			blocks[current] = []
			continue
		if current != "":
			(blocks[current] as Array).append(line)
	return blocks


# Builds the exact production campaign-bible shape from parsed label blocks. All
# structure lives here in code; the model never wrote a brace. Missing labels
# fall back to "" / [] so assembly never throws (downstream repair + validation
# catch gaps and drive the correction retry).
static func assemble_campaign_bible_from_labels(blocks: Dictionary) -> Dictionary:
	var v := {}
	for field in _CAMPAIGN_BIBLE_LABEL_FIELDS:
		var label := str(field.get("label", ""))
		if blocks.has(label):
			v[label] = _coerce_labeled_field(field, blocks[label])

	var trail_id := str(v.get("rumor.trail_id", ""))
	if not trail_id.is_empty() and not trail_id.begins_with("rumor_trail."):
		trail_id = "rumor_trail." + trail_id

	# Guarantee the two hard-required banned phrases regardless of model output.
	var banned: Array = (v.get("banned_repeats", []) as Array).duplicate()
	var lowered := {}
	for b in banned:
		lowered[str(b).strip_edges().to_lower()] = true
	for required in ["chosen one", "destiny"]:
		if not lowered.has(required):
			banned.append(required)

	return {
		"campaign_title": v.get("campaign_title", ""),
		"campaign_logline": v.get("campaign_logline", ""),
		"opening_situation": v.get("opening_situation", ""),
		"main_mystery": v.get("main_mystery", ""),
		"act_1_outline": v.get("act_1_outline", []),
		"long_term_reveal": v.get("long_term_reveal", ""),
		"tone": v.get("tone", ""),
		"core_pressure": v.get("core_pressure", ""),
		"factions": {
			"zenith": v.get("factions.zenith", ""),
			"aurelia": v.get("factions.aurelia", ""),
			"vanguard": v.get("factions.vanguard", ""),
		},
		"kaelen_rule": v.get("kaelen_rule", ""),
		"kaelen_angle": v.get("kaelen_angle", ""),
		"kaelen_hint_plan": v.get("kaelen_hint_plan", []),
		"kaelen_hint_style": v.get("kaelen_hint_style", ""),
		"kaelen_never_reveal": v.get("kaelen_never_reveal", ""),
		"nova_quirk": v.get("nova_quirk", ""),
		"nova_memory_flicker": v.get("nova_memory_flicker", ""),
		"faction_reveal_rule": v.get("faction_reveal_rule", ""),
		"humor_rule": v.get("humor_rule", ""),
		"address_rule": v.get("address_rule", ""),
		"fallback_rule": v.get("fallback_rule", ""),
		"story_horizon_rule": v.get("story_horizon_rule", ""),
		"story_arcs": [{
			"name": v.get("story_arc.name", ""),
			"summary": v.get("story_arc.summary", ""),
		}],
		"rumor_trails": [{
			"name": v.get("rumor.name", ""),
			"trail_id": trail_id,
			"clue_count": 2,
			"hint_theme": v.get("rumor.hint_theme", ""),
			"clue_templates": v.get("rumor.clue_templates", []),
			"discovery_type": v.get("rumor.discovery_type", ""),
			"rarity": v.get("rumor.rarity", ""),
			"payoff": v.get("rumor.payoff", ""),
		}],
		"regeneration_triggers": [{
			"id": v.get("trigger.id", ""),
			"metric": v.get("trigger.metric", ""),
			"threshold": v.get("trigger.threshold", 0),
			"action": v.get("trigger.action", ""),
			"description": v.get("trigger.description", ""),
		}],
		"expansion_rules": v.get("expansion_rules", []),
		"banned_repeats": banned,
	}


# Coerces one field's raw block lines to a typed value per its `kind`. Pure and
# offline: never a network call. Length caps are NOT enforced here (production
# never validated length; over-length text is harmless and can be condensed
# later — see memory project_labeled_field_generation).
static func _coerce_labeled_field(field: Dictionary, lines: Array) -> Variant:
	var kind := str(field.get("kind", "text"))
	match kind:
		"list":
			return _labeled_list_items(lines)
		"int":
			return _extract_leading_int(_join_labeled_text(lines))
		"enum":
			return _join_labeled_text(lines).strip_edges().to_lower().trim_suffix(".")
		"slug":
			var slug := _slugify(_join_labeled_text(lines))
			if field.has("prefix"):
				var pslug := _slugify(str(field["prefix"]))
				if slug == pslug:
					slug = ""
				elif slug.begins_with(pslug + "_"):
					slug = slug.substr(pslug.length() + 1)
			return slug
		_:
			return _join_labeled_text(lines)


static func _join_labeled_text(lines: Array) -> String:
	var parts := PackedStringArray()
	for l in lines:
		var s := str(l).strip_edges()
		if not s.is_empty():
			parts.append(s)
	return " ".join(parts).strip_edges()


static func _labeled_list_items(lines: Array) -> Array:
	var items := []
	for l in lines:
		var s := str(l).strip_edges()
		if s.is_empty():
			continue
		if s.begins_with("- "):
			s = s.substr(2).strip_edges()
		elif s.begins_with("-"):
			s = s.substr(1).strip_edges()
		if not s.is_empty():
			items.append(s)
	return items


static func _slugify(value: String) -> String:
	var out := ""
	for ch in value.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif (ch == " " or ch == "-" or ch == "_" or ch == ".") \
				and not out.is_empty() and out[out.length() - 1] != "_":
			out += "_"
	return out.lstrip("_").rstrip("_")


static func _extract_leading_int(text: String) -> int:
	var digits := ""
	for i in text.length():
		var ch := text[i]
		if ch >= "0" and ch <= "9":
			digits += ch
		elif ch == "-" and digits.is_empty():
			digits += ch
		elif not digits.is_empty():
			break
	if digits.is_empty() or digits == "-":
		return 0
	return int(digits)


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
			"nova_rule": "nova_quirk",
			"nova_habit": "nova_quirk",
			"nova_secret": "nova_memory_flicker",
			"nova_fragment": "nova_memory_flicker",
			"nova_memory": "nova_memory_flicker",
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
	_repair_kaelen_hints(repaired, repairs)
	_repair_nova_fields(repaired, repairs)
	_repair_factions(repaired, repairs)
	_repair_rumor_trails(repaired, repairs)
	_repair_regeneration_triggers(repaired)
	_repair_banned_repeats(repaired)
	return repaired


# Ensures the factions triad exists with all three anchor keys as non-empty
# strings. Accepts aliases (a per-faction "problem"/"issue" object) and fills a
# neutral placeholder for any missing anchor so downstream faction_pressure
# seeding always has three entries. Player-safe world texture, not a secret.
static func _repair_factions(target: Dictionary, repairs: Array = []) -> void:
	var factions = target.get("factions", null)
	if not factions is Dictionary:
		factions = {}
		repairs.append("factions_defaulted")
	for anchor in ["zenith", "aurelia", "vanguard"]:
		var value := ""
		if factions.has(anchor):
			var raw = factions[anchor]
			if raw is Dictionary:
				value = str(raw.get("problem", raw.get("issue", raw.get("summary", "")))).strip_edges()
			else:
				value = str(raw).strip_edges()
		if value.is_empty():
			value = "%s keeps its local troubles quiet for now." % anchor.capitalize()
			repairs.append("faction_problem_defaulted:%s" % anchor)
		factions[anchor] = value
	target["factions"] = factions


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


# Shape-only scaffolding for Kaelen's hint delivery (plan §5). hint_plan/never_reveal
# are director-only (kept private by the public_prompt_context allowlist); hint_style
# is player-safe. Defaults are neutral delivery scaffolding, not the secret itself.
static func _repair_kaelen_hints(target: Dictionary, repairs: Array = []) -> void:
	if not target.get("kaelen_hint_plan", null) is Array:
		if target.get("kaelen_hint_plan", null) is String \
				and not str(target["kaelen_hint_plan"]).strip_edges().is_empty():
			target["kaelen_hint_plan"] = [str(target["kaelen_hint_plan"]).strip_edges()]
			repairs.append("string_to_array:kaelen_hint_plan")
		else:
			target["kaelen_hint_plan"] = []
			repairs.append("kaelen_hint_plan_defaulted")
	if str(target.get("kaelen_hint_style", "")).strip_edges().is_empty():
		target["kaelen_hint_style"] = "deflects with dry jokes and changes the subject"
		repairs.append("kaelen_hint_style_defaulted")
	if str(target.get("kaelen_never_reveal", "")).strip_edges().is_empty():
		target["kaelen_never_reveal"] = "Kaelen's full identity and true motive are never confirmed."
		repairs.append("kaelen_never_reveal_defaulted")


# N.O.V.A. is fixed cast (see plot-armor contract in docs/campaign_bible_schema.md).
# nova_quirk is player-safe campaign color; nova_memory_flicker is director-only.
# Defaults are neutral scaffolding so a model that skips the labels still yields
# a working campaign — the quirk just stays generic instead of campaign-flavored.
static func _repair_nova_fields(target: Dictionary, repairs: Array = []) -> void:
	if str(target.get("nova_quirk", "")).strip_edges().is_empty():
		target["nova_quirk"] = (
			"I keep a running audit of everything aboard I consider mine. " +
			"Which is everything."
		)
		repairs.append("nova_quirk_defaulted")
	if str(target.get("nova_memory_flicker", "")).strip_edges().is_empty():
		target["nova_memory_flicker"] = (
			"Something in N.O.V.A.'s wiped archives reacts to this campaign's trouble, " +
			"but the fragment never resolves."
		)
		repairs.append("nova_memory_flicker_defaulted")


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
		"factions",
		"kaelen_rule",
		"kaelen_angle",
		"kaelen_hint_plan",
		"kaelen_hint_style",
		"kaelen_never_reveal",
		"nova_quirk",
		"nova_memory_flicker",
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
	var seed_text := str(baseline.get("campaign_seed", ""))
	var excluded_lanes: Array = baseline.get("_recent_lanes", []) if baseline.get("_recent_lanes", []) is Array else []
	# Transient hint from GameRoot; never persist it into the stored bible.
	bible.erase("_recent_lanes")
	var lane := _creative_lane_for_seed(seed_text, excluded_lanes)
	if not lane.is_empty():
		bible["creative_lane"] = str(lane.get("name", ""))
	# Same deterministic axes the prompt was built with (plan §3.5/§3.6), stored
	# for debug visibility and cross-campaign rotation.
	bible["opening_type"] = str(_axis_for_seed(seed_text, OPENING_TYPES, 101).get("name", ""))
	bible["mystery_shape"] = str(_axis_for_seed(seed_text, MYSTERY_SHAPES, 211).get("name", ""))
	bible["pressure_type"] = str(_axis_for_seed(seed_text, PRESSURE_TYPES, 331).get("name", ""))
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
		"nova_quirk",
		"nova_memory_flicker",
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
	_validate_plot_armor(bible, result)
	return result


# ── Plot armor: Kaelen and N.O.V.A. are structural cast and can never die ──────
# Layer 2 of the plot-armor contract (docs/campaign_bible_schema.md): scan every
# string in a generated bible (or horizon expansion) for phrasing that kills,
# destroys, or permanently removes either character. A hit is a validation error,
# which feeds the correction-retry loop — the model gets told exactly what to fix.
# "supernova"/"goes nova" style celestial usage is masked out before matching so
# a star can still explode without tripping the guard.
# Explicit death-assertion templates, {n} = protected name. Deliberately
# NARROW: Kaelen assigning kill contracts ("Kaelen wants the depot destroyed")
# or gossiping about dead smugglers must never trip this — a false positive here
# can block campaign generation entirely. The model evading tight phrasing is
# acceptable because layer 3 (StoryQuestManager runtime guard) is the hard wall;
# this layer just catches the obvious cases early enough to retry cheaply.
const _PLOT_ARMOR_DEATH_PATTERNS := [
	"{n} dies", "{n} died", "{n} must die", "{n} will die",
	"{n} is dead", "{n} was dead", "{n} turns up dead", "{n} is found dead",
	"{n} is killed", "{n} was killed", "{n} gets killed",
	"{n} is destroyed", "{n} was destroyed", "{n} gets destroyed",
	"{n} is deleted", "{n} was deleted", "{n} is erased", "{n} was erased",
	"{n} is decommissioned", "{n} is dismantled", "{n} is scrapped",
	"{n} sacrifices herself", "{n} sacrifices itself", "{n} sacrifices themself",
	"{n}'s death", "death of {n}",
	"kill {n}", "kills {n}", "killing {n}", "kill off {n}",
	"destroy {n}", "destroys {n}", "destroying {n}",
	"delete {n}", "deletes {n}", "deleting {n}",
	"erase {n}", "erases {n}", "erasing {n}",
	"sacrifice {n}", "sacrifices {n}",
	"assassinate {n}", "assassinates {n}",
	"{n} is gone for good", "{n} is permanently offline",
	"{n} shuts down for good", "{n} is shut down for good",
]


static func _validate_plot_armor(bible: Dictionary, result: ValidationResult) -> void:
	var texts: Array[String] = []
	_collect_strings(bible, texts)
	for text in texts:
		var offense := plot_armor_offense(text)
		if not offense.is_empty():
			result.add_error(
				"plot_armor_violation",
				"Kaelen and N.O.V.A. are permanent cast and can never die or be removed. Rewrite without this: \"%s\"" % offense,
				"plot_armor"
			)
			return  # one clear correction per attempt beats a wall of errors


# Returns a short excerpt of the offending phrasing, or "" if the text is clean.
# Public so StoryQuestManager (layer 3) and tests can reuse the same rule.
static func plot_armor_offense(text: String) -> String:
	var lower := text.to_lower()
	# Mask celestial usage so "the star goes supernova" can't false-positive.
	lower = lower.replace("supernova", "star-event").replace("goes nova", "flares") \
		.replace("going nova", "flaring")
	# Collapse whitespace so multi-word patterns match across line breaks.
	lower = lower.replace("\n", " ").replace("\t", " ")
	while lower.contains("  "):
		lower = lower.replace("  ", " ")
	for cast_name in ["kaelen", "nova", "n.o.v.a"]:
		for pattern in _PLOT_ARMOR_DEATH_PATTERNS:
			var phrase := str(pattern).replace("{n}", cast_name)
			var idx := _find_word(lower, phrase)
			if idx != -1:
				var start := maxi(0, idx - 24)
				return lower.substr(start, phrase.length() + 48).strip_edges()
	return ""


# Index of `word`/phrase in `text` delimited by non-alphanumeric characters —
# so "dies" never matches inside "studies" and "nova" never inside "supernovae".
# Returns -1 when absent.
static func _find_word(text: String, word: String) -> int:
	var idx := text.find(word)
	while idx != -1:
		if _is_word_at(text, word, idx):
			return idx
		idx = text.find(word, idx + 1)
	return -1


static func _is_word_at(text: String, word: String, idx: int) -> bool:
	if idx > 0 and _is_word_char(text[idx - 1]):
		return false
	var end := idx + word.length()
	if end < text.length() and _is_word_char(text[end]):
		return false
	return true


static func _is_word_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "0" and c <= "9")


static func _collect_strings(value: Variant, out: Array) -> void:
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			_collect_strings((value as Dictionary)[key], out)
	elif value is Array:
		for item in value:
			_collect_strings(item, out)
	elif value is String:
		if not str(value).strip_edges().is_empty():
			out.append(str(value))


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
	# Horizon expansions extend the campaign mid-run — the same plot-armor rule
	# that guards initial generation applies to every appended arc/trail/beat.
	var expansion_texts: Array[String] = []
	_collect_strings(repaired, expansion_texts)
	for expansion_text in expansion_texts:
		var offense := plot_armor_offense(expansion_text)
		if not offense.is_empty():
			result.add_error(
				"plot_armor_violation",
				"Kaelen and N.O.V.A. can never die or be removed. Offending text: \"%s\"" % offense,
				"plot_armor"
			)
			return _failure("story_horizon_expansion_validation_failed", result)
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
