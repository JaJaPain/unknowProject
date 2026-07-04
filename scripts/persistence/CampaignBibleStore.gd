class_name CampaignBibleStore
extends RefCounted

const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const DOCUMENT_VERSION := 1
const BIBLE_PATH := "campaign_bible.json"
const STATUS_PROCEDURAL_BOOTSTRAP := "procedural_bootstrap"
const STATUS_LLM_GENERATED := "llm_generated"
const STATUS_LLM_UNAVAILABLE := "llm_unavailable"
const STATUS_GENERATION_FAILED := "generation_failed"
const VALID_GENERATION_STATUSES := [
	STATUS_PROCEDURAL_BOOTSTRAP,
	STATUS_LLM_GENERATED,
	STATUS_LLM_UNAVAILABLE,
	STATUS_GENERATION_FAILED,
]
const RUMOR_DISCOVERY_TYPES := [
	"hidden_discovery",
	"secret_route",
	"rare_upgrade",
	"faction_secret",
	"endgame_easter_egg",
]
const RUMOR_RARITIES := ["local", "uncommon", "rare", "legendary"]
const HORIZON_TRIGGER_METRICS := [
	"prepared_systems_remaining",
	"active_story_arcs_remaining",
	"rumor_trails_remaining",
	"major_arc_state",
]
const HORIZON_TRIGGER_ACTIONS := [
	"append_story_horizon",
	"append_rumor_trail",
	"append_story_arc",
]

var campaign_path: String
var campaign: Dictionary = {}
var data: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> CampaignBibleStore:
	var store := CampaignBibleStore.new()
	store.campaign_path = path.trim_suffix("/")
	store._load_or_create()
	return store


func is_valid() -> bool:
	return validation.is_valid()


# Player-safe projection of the bible for small-model (dialogue/contract/
# chatter) prompts. This is an ALLOWLIST, not a denylist: only fields the
# player is meant to know — the premise and the voice/behavior rules — are
# included. Director-only fields (main_mystery, long_term_reveal, act_1_outline,
# story_arcs summaries, rumor-trail payoffs/hint themes, and the horizon
# machinery) are deliberately excluded so a chatty qwen completion can never
# paraphrase the campaign twist into dock gossip. New bible fields default to
# private: they only reach small models if explicitly added here.
#
# The full view (with secrets) lives in director_context()/prompt_context() and
# is only for debug tooling and large, director-privileged model calls.
#
# ── LEAK-HUNT NOTE (deviation from docs/storytelling_architecture_plan.md §7.1) ──
# The plan's item #1 named only long_term_reveal, rumor payoffs, and act_1_outline
# as the leaking fields. During implementation we also classified `main_mystery`
# as director-only, because StoryManager.seed_story_state_from_bible() seeds it
# into `player_does_not_know_yet` (the never-exposed list) — so it was leaking too.
# If a future story-secret leak turns up, THIS allowlist is the first place to
# look: any bible field NOT listed below is invisible to small models by design,
# so a leak means either (a) a secret field was mistakenly added here, or (b) a
# secret is reaching qwen through a *different* path (story_state block, a direct
# prompt, or _update_kaelen_mood — see plan §7.2). Confirm which before editing.
func public_prompt_context() -> String:
	if not is_valid() or data.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("Campaign Premise (player-safe):")
	lines.append("- Campaign title: %s" % str(data.get("campaign_title", "")))
	lines.append("- Logline: %s" % str(data.get("campaign_logline", "")))
	lines.append("- Opening situation: %s" % str(data.get("opening_situation", "")))
	lines.append("- Tone: %s" % str(data.get("tone", "")))
	lines.append("- Core pressure: %s" % str(data.get("core_pressure", "")))
	_append_faction_lines(lines, data)
	lines.append("- Kaelen rule: %s" % str(data.get("kaelen_rule", "")))
	# nova_quirk is player-safe campaign color for the ship AI; the flicker
	# (her hidden past fragment) stays director-only and must NOT appear here.
	var nova_quirk := str(data.get("nova_quirk", "")).strip_edges()
	if not nova_quirk.is_empty():
		lines.append("- N.O.V.A. quirk this campaign: %s" % nova_quirk)
	lines.append("- Faction reveal rule: %s" % str(data.get("faction_reveal_rule", "")))
	lines.append("- Humor rule: %s" % str(data.get("humor_rule", "")))
	lines.append("- Address rule: %s" % str(data.get("address_rule", "")))
	return "\n".join(lines)


# Anchor faction problems are player-safe world texture, so they appear in both
# the public and director views. Shared by public_prompt_context/prompt_context.
static func _append_faction_lines(lines: Array, data: Dictionary) -> void:
	var factions = data.get("factions", null)
	if not factions is Dictionary:
		return
	var parts: Array[String] = []
	for anchor in ["zenith", "aurelia", "vanguard"]:
		var problem := str(factions.get(anchor, "")).strip_edges()
		if not problem.is_empty():
			parts.append("%s: %s" % [anchor.capitalize(), problem])
	if not parts.is_empty():
		lines.append("- Faction problems: %s" % " | ".join(parts))


# Full bible view, INCLUDING director-only secrets (mystery, reveal, outline,
# rumor payoffs, horizon machinery). Only for debug tooling and large,
# director-privileged model calls — never feed this to small-model prompts.
# Alias of prompt_context(); the explicit name documents intent at call sites.
func director_context() -> String:
	return prompt_context()


func prompt_context() -> String:
	if not is_valid() or data.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("Campaign Bible:")
	lines.append("- Generation status: %s" % generation_status())
	lines.append("- Source: %s" % source_name())
	lines.append("- Campaign title: %s" % str(data.get("campaign_title", "")))
	lines.append("- Logline: %s" % str(data.get("campaign_logline", "")))
	lines.append("- Opening situation: %s" % str(data.get("opening_situation", "")))
	lines.append("- Main mystery: %s" % str(data.get("main_mystery", "")))
	lines.append("- Tone: %s" % str(data.get("tone", "")))
	lines.append("- Core pressure: %s" % str(data.get("core_pressure", "")))
	_append_faction_lines(lines, data)
	lines.append("- Kaelen rule: %s" % str(data.get("kaelen_rule", "")))
	lines.append("- N.O.V.A. quirk: %s" % str(data.get("nova_quirk", "")))
	lines.append("- N.O.V.A. memory flicker (director-only): %s" % str(data.get("nova_memory_flicker", "")))
	lines.append("- Faction reveal rule: %s" % str(data.get("faction_reveal_rule", "")))
	lines.append("- Humor rule: %s" % str(data.get("humor_rule", "")))
	lines.append("- Address rule: %s" % str(data.get("address_rule", "")))
	lines.append("- Story horizon rule: %s" % str(data.get("story_horizon_rule", "")))
	var act_1_outline: Array = data.get("act_1_outline", [])
	if not act_1_outline.is_empty():
		lines.append("Act 1 outline:")
		for beat in act_1_outline:
			lines.append("- %s" % str(beat))
	lines.append("- Long-term reveal direction: %s" % str(data.get("long_term_reveal", "")))
	var arcs: Array = data.get("story_arcs", [])
	if not arcs.is_empty():
		lines.append("Story arcs:")
		for arc in arcs:
			if arc is Dictionary:
				lines.append(
					"- %s: %s" %
					[str(arc.get("name", "")), str(arc.get("summary", ""))]
				)
	var rumor_trails: Array = data.get("rumor_trails", [])
	if not rumor_trails.is_empty():
		lines.append("Rumor trails:")
		for trail in rumor_trails:
			if trail is Dictionary:
				lines.append(
					"- %s (%s): %s -> %s" %
					[
						str(trail.get("name", "")),
						str(trail.get("discovery_type", "hidden_discovery")),
						str(trail.get("hint_theme", "")),
						str(trail.get("payoff", "")),
					]
				)
	var regeneration_triggers: Array = data.get("regeneration_triggers", [])
	if not regeneration_triggers.is_empty():
		lines.append("Story horizon regeneration triggers:")
		for trigger in regeneration_triggers:
			if trigger is Dictionary:
				lines.append(
					"- %s when %s <= %s: %s" %
					[
						str(trigger.get("id", "")),
						str(trigger.get("metric", "")),
						str(trigger.get("threshold", "")),
						str(trigger.get("action", "")),
					]
				)
	var expansion_rules: Array = data.get("expansion_rules", [])
	if not expansion_rules.is_empty():
		lines.append("Expansion rules:")
		for rule in expansion_rules:
			lines.append("- %s" % str(rule))
	return "\n".join(lines)


func generation_status() -> String:
	var status := str(data.get("generation_status", "")).strip_edges()
	if status.is_empty():
		status = str(data.get("source", "")).strip_edges()
	if status.is_empty():
		status = STATUS_PROCEDURAL_BOOTSTRAP
	return status


func source_name() -> String:
	var source := str(data.get("source", "")).strip_edges()
	if source.is_empty():
		source = generation_status()
	return source


func status_summary() -> String:
	var source_model := str(data.get("source_model", "")).strip_edges()
	var note := str(data.get("generation_note", "")).strip_edges()
	var parts: Array[String] = [
		"status=%s" % generation_status(),
		"source=%s" % source_name(),
	]
	if not source_model.is_empty():
		parts.append("model=%s" % source_model)
	if not note.is_empty():
		parts.append("note=%s" % note)
	return ", ".join(parts)


func replace_bible(next_data: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Campaign bible store is invalid.")
	var prepared := next_data.duplicate(true)
	prepared["rumor_trails"] = normalize_rumor_trails(prepared.get("rumor_trails", []))
	prepared["regeneration_triggers"] = normalize_regeneration_triggers(
		prepared.get("regeneration_triggers", [])
	)
	prepared["schema_version"] = DOCUMENT_VERSION
	prepared["document_type"] = "campaign_bible"
	prepared["campaign_id"] = str(campaign.get("id", ""))
	if str(prepared.get("source", "")).strip_edges().is_empty():
		prepared["source"] = STATUS_LLM_GENERATED
	if str(prepared.get("generation_status", "")).strip_edges().is_empty():
		prepared["generation_status"] = str(prepared.get("source", STATUS_LLM_GENERATED))
	var committed := _commit(prepared, "campaign_bible_replace")
	if not bool(committed.get("ok", false)):
		return committed
	data = prepared
	return {"ok": true, "bible": data.duplicate(true)}


func mark_model_unavailable(reason: String, model_name: String = "") -> Dictionary:
	if not is_valid():
		return _failure("Campaign bible store is invalid.")
	var prepared := data.duplicate(true)
	prepared["source"] = STATUS_LLM_UNAVAILABLE
	prepared["generation_status"] = STATUS_LLM_UNAVAILABLE
	prepared["source_model"] = model_name.strip_edges()
	prepared["generation_note"] = reason.strip_edges()
	prepared["last_generation_error"] = reason.strip_edges()
	var committed := _commit(prepared, "campaign_bible_model_unavailable")
	if not bool(committed.get("ok", false)):
		return committed
	data = prepared
	return {"ok": true, "bible": data.duplicate(true)}


func mark_generation_failed(reason: String, model_name: String = "") -> Dictionary:
	if not is_valid():
		return _failure("Campaign bible store is invalid.")
	var prepared := data.duplicate(true)
	prepared["source"] = STATUS_GENERATION_FAILED
	prepared["generation_status"] = STATUS_GENERATION_FAILED
	prepared["source_model"] = model_name.strip_edges()
	prepared["generation_note"] = reason.strip_edges()
	prepared["last_generation_error"] = reason.strip_edges()
	var committed := _commit(prepared, "campaign_bible_generation_failed")
	if not bool(committed.get("ok", false)):
		return committed
	data = prepared
	return {"ok": true, "bible": data.duplicate(true)}


func _load_or_create() -> void:
	var campaign_result := DomainJsonType.read_object(
		"%s/campaign.json" % campaign_path
	)
	validation.merge(campaign_result["validation"], "campaign")
	if not validation.is_valid():
		return
	campaign = campaign_result["data"]
	var campaign_id := str(campaign.get("id", ""))
	if not DomainIdType.is_valid(campaign_id, "campaign"):
		validation.add_error(
			"invalid_campaign_id",
			"Campaign bible requires a valid campaign id.",
			"campaign.id"
		)
		return
	var bible_path := "%s/%s" % [campaign_path, BIBLE_PATH]
	if not FileAccess.file_exists(bible_path):
		data = _default_bible(campaign_id, str(campaign.get("campaign_seed", "")))
		var committed := _commit(data, "campaign_bible_bootstrap")
		if not bool(committed.get("ok", false)):
			validation.add_error(
				"campaign_bible_bootstrap_failed",
				str(committed.get("error", "Campaign bible could not be created.")),
				BIBLE_PATH
			)
		return
	var bible_result := DomainJsonType.read_object(bible_path)
	validation.merge(bible_result["validation"], "campaign_bible")
	if not validation.is_valid():
		return
	data = bible_result["data"]
	data = _migrate_legacy_bible(data, campaign_id)
	data["rumor_trails"] = normalize_rumor_trails(data.get("rumor_trails", []))
	data["regeneration_triggers"] = normalize_regeneration_triggers(
		data.get("regeneration_triggers", [])
	)
	validation.merge(_validate_data(data, campaign_id), "campaign_bible")
	if validation.is_valid():
		_commit(data, "campaign_bible_migration")


func _commit(next_data: Dictionary, operation: String) -> Dictionary:
	return TransactionStoreType.commit_json_set(
		campaign_path,
		operation,
		{BIBLE_PATH: next_data},
		BIBLE_PATH,
		func(_path: String, value: Dictionary) -> ValidationResult:
			return _validate_data(value, str(campaign.get("id", "")))
	)


# Backfills fields added to the schema after a save was written, so an
# existing campaign bible from an older session doesn't fail validation and
# get stuck forever (validation requires these fields non-empty). If any
# backfill was needed, resets generation_status to bootstrap so the now-
# reliable large-story pipeline writes complete fresh content next time
# instead of leaving a permanent mix of real old content + placeholder text.
static func _migrate_legacy_bible(data: Dictionary, campaign_id: String) -> Dictionary:
	var migrated := data.duplicate(true)
	var defaults := _default_bible(campaign_id, str(data.get("campaign_seed", "")))
	var backfilled := false
	for field in [
		"campaign_title",
		"campaign_logline",
		"opening_situation",
		"main_mystery",
		"long_term_reveal",
		"kaelen_angle",
	]:
		if str(migrated.get(field, "")).strip_edges().is_empty():
			migrated[field] = defaults[field]
			backfilled = true
	if not migrated.has("act_1_outline") or not migrated.get("act_1_outline", null) is Array:
		migrated["act_1_outline"] = []
		backfilled = true
	# factions is optional metadata added later — backfill a neutral triad WITHOUT
	# forcing a full regeneration of an otherwise-complete campaign.
	if not migrated.get("factions", null) is Dictionary:
		migrated["factions"] = defaults["factions"]
	else:
		for anchor in ["zenith", "aurelia", "vanguard"]:
			if str(migrated["factions"].get(anchor, "")).strip_edges().is_empty():
				migrated["factions"][anchor] = defaults["factions"][anchor]
	# N.O.V.A. fields were added after early campaigns were written. Backfill a
	# neutral quirk/flicker (same pattern as factions) so an old save keeps its
	# real generated content instead of being reset to bootstrap.
	for nova_field in ["nova_quirk", "nova_memory_flicker"]:
		if str(migrated.get(nova_field, "")).strip_edges().is_empty():
			migrated[nova_field] = defaults[nova_field]
	if backfilled:
		migrated["generation_status"] = STATUS_PROCEDURAL_BOOTSTRAP
		migrated["source"] = STATUS_PROCEDURAL_BOOTSTRAP
		migrated["generation_note"] = (
			"Campaign bible schema was updated since this campaign was created; " +
			"waiting for the large story model to write complete fresh content."
		)
	return migrated


static func _default_bible(campaign_id: String, campaign_seed: String) -> Dictionary:
	return {
		"schema_version": DOCUMENT_VERSION,
		"document_type": "campaign_bible",
		"campaign_id": campaign_id,
		"campaign_seed": campaign_seed,
		"source": STATUS_PROCEDURAL_BOOTSTRAP,
		"generation_status": STATUS_PROCEDURAL_BOOTSTRAP,
		"source_model": "",
		"generation_note": "Waiting for the large story model to generate the required campaign bible.",
		"last_generation_error": "",
		"campaign_title": "Pending Large-Model Campaign",
		"campaign_logline": "Waiting for Gemma to write the campaign premise.",
		"opening_situation": "Gameplay must wait until the large story model writes the opening situation.",
		"main_mystery": "Pending large-model mystery.",
		"act_1_outline": [],
		"long_term_reveal": "Pending large-model reveal direction.",
		"tone": "PG-13 frontier space opera with dry, slightly dark humor.",
		"core_pressure": "Pending large-model campaign story generation.",
		"factions": {
			"zenith": "Pending large-model faction problem.",
			"aurelia": "Pending large-model faction problem.",
			"vanguard": "Pending large-model faction problem.",
		},
		"kaelen_rule": "Kaelen is the only fixed recurring character. Her actions can be revealed, but her true nature and full mystery should never be completely explained.",
		"kaelen_angle": "Pending large-model Kaelen angle.",
		# Neutral working text, not "Pending..." — these same defaults backfill
		# legacy campaigns without a regeneration, so they must read fine in prompts.
		# nova_quirk is first-person: N.O.V.A. can speak it verbatim.
		"nova_quirk": "I keep a running audit of everything aboard I consider mine. Which is everything.",
		"nova_memory_flicker": "Something in N.O.V.A.'s wiped archives reacts to this campaign's trouble, but the fragment never resolves.",
		"faction_reveal_rule": "Reveal new factions, conflicts, ores, upgrades, and secrets through gate travel rather than upfront exposition.",
		"humor_rule": "Use humor as relief from killing, betrayal, power, and money. Prefer dry or dark wit, with occasional oddballs.",
		"address_rule": "Agents may call the player Indy in an opening request, but should avoid repeating the name in immediate acceptance follow-ups.",
		"fallback_rule": "Fallback content is last-resort only and should be visible to diagnostics.",
		"story_horizon_rule": "The campaign bible owns the current prepared story horizon. When the player nears its edge, append a new horizon with the larger model instead of replacing known canon.",
		"story_arcs": [],
		"rumor_trails": [
			{
				"name": "Pending Large-Model Rumor Trail",
				"trail_id": "rumor_trail.pending_large_model",
				"clue_count": 4,
				"hint_theme": "placeholder diagnostics only; gameplay must wait for generated story",
				"clue_templates": [
					"Large story model has not generated clue one.",
					"Large story model has not generated clue two.",
					"Large story model has not generated clue three.",
					"Large story model has not generated clue four.",
				],
				"discovery_type": "endgame_easter_egg",
				"rarity": "legendary",
				"payoff": "No payoff until the large story model writes the campaign bible.",
			},
		],
		"regeneration_triggers": [
			{
				"id": "frontier_horizon_low",
				"metric": "prepared_systems_remaining",
				"threshold": 2,
				"action": "append_story_horizon",
				"description": "Fewer than the target number of prepared future systems or story packs remain beyond known gates.",
			},
			{
				"id": "major_arc_resolved",
				"metric": "active_story_arcs_remaining",
				"threshold": 0,
				"action": "append_story_arc",
				"description": "A major campaign arc resolves and no successor arc has been prepared.",
			},
			{
				"id": "rumor_trail_exhausted",
				"metric": "rumor_trails_remaining",
				"threshold": 0,
				"action": "append_rumor_trail",
				"description": "A rare rumor trail or payoff has been consumed and no deeper trail exists.",
			},
		],
		"expansion_rules": [
			"Preserve known facts, alliances, enemies, discovered systems, named NPC outcomes, and player choices.",
			"Append the next frontier horizon; do not retcon the existing campaign bible.",
			"Keep Kaelen alive and preserve her unresolved mystery.",
			"Use campaign idea memory to avoid repeating names, jokes, factions, rumors, and story beats.",
			"Keep newly generated factions, ores, upgrades, secrets, and regions undiscovered until gates reveal them.",
		],
		"banned_repeats": [],
	}


static func _validate_data(value: Dictionary, campaign_id: String) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(value.get("schema_version", 0)) != DOCUMENT_VERSION:
		result.add_error(
			"invalid_campaign_bible_version",
			"Campaign bible schema version is invalid.",
			"schema_version"
		)
	if str(value.get("document_type", "")) != "campaign_bible":
		result.add_error(
			"invalid_campaign_bible_type",
			"Campaign bible document type is invalid.",
			"document_type"
		)
	if str(value.get("campaign_id", "")) != campaign_id:
		result.add_error(
			"campaign_bible_campaign_mismatch",
			"Campaign bible belongs to a different campaign.",
			"campaign_id"
		)
	var status := str(value.get("generation_status", "")).strip_edges()
	if status.is_empty():
		status = str(value.get("source", "")).strip_edges()
	if status not in VALID_GENERATION_STATUSES:
		result.add_error(
			"invalid_campaign_bible_generation_status",
			"Campaign bible generation status is unsupported.",
			"generation_status"
		)
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
		if str(value.get(field, "")).strip_edges().is_empty():
			result.add_error(
				"missing_campaign_bible_field",
				"Campaign bible field '%s' cannot be empty." % field,
				field
			)
	if value.has("factions") and not value.get("factions", {}) is Dictionary:
		result.add_error(
			"invalid_factions",
			"Campaign bible factions must be an object.",
			"factions"
		)
	if not value.get("story_arcs", []) is Array:
		result.add_error("invalid_story_arcs", "Story arcs must be an array.", "story_arcs")
	if not value.get("act_1_outline", []) is Array:
		result.add_error(
			"invalid_act_1_outline",
			"Act 1 outline must be an array.",
			"act_1_outline"
		)
	if not value.get("rumor_trails", []) is Array:
		result.add_error("invalid_rumor_trails", "Rumor trails must be an array.", "rumor_trails")
	else:
		var trails: Array = value.get("rumor_trails", [])
		for index in range(trails.size()):
			if not trails[index] is Dictionary:
				result.add_error(
					"invalid_rumor_trail",
					"Rumor trail must be an object.",
					"rumor_trails.%d" % index
				)
				continue
			var trail: Dictionary = trails[index]
			for field in ["name", "trail_id", "hint_theme", "payoff", "discovery_type", "rarity"]:
				if str(trail.get(field, "")).strip_edges().is_empty():
					result.add_error(
						"missing_rumor_trail_field",
						"Rumor trail field '%s' cannot be empty." % field,
						"rumor_trails.%d.%s" % [index, field]
					)
			if int(trail.get("clue_count", 0)) < 2:
				result.add_error(
					"invalid_rumor_trail_clue_count",
					"Rumor trail clue_count must be at least 2.",
					"rumor_trails.%d.clue_count" % index
				)
			if str(trail.get("discovery_type", "")) not in RUMOR_DISCOVERY_TYPES:
				result.add_error(
					"invalid_rumor_trail_discovery_type",
					"Rumor trail discovery_type is unsupported.",
					"rumor_trails.%d.discovery_type" % index
				)
			if str(trail.get("rarity", "")) not in RUMOR_RARITIES:
				result.add_error(
					"invalid_rumor_trail_rarity",
					"Rumor trail rarity is unsupported.",
					"rumor_trails.%d.rarity" % index
				)
			if not trail.get("clue_templates", []) is Array:
				result.add_error(
					"invalid_rumor_trail_clue_templates",
					"Rumor trail clue_templates must be an array.",
					"rumor_trails.%d.clue_templates" % index
				)
	if not value.get("regeneration_triggers", []) is Array:
		result.add_error(
			"invalid_regeneration_triggers",
			"Regeneration triggers must be an array.",
			"regeneration_triggers"
		)
	else:
		var triggers: Array = value.get("regeneration_triggers", [])
		for index in range(triggers.size()):
			if not triggers[index] is Dictionary:
				result.add_error(
					"invalid_regeneration_trigger",
					"Regeneration trigger must be an object.",
					"regeneration_triggers.%d" % index
				)
				continue
			var trigger: Dictionary = triggers[index]
			for field in ["id", "metric", "action", "description"]:
				if str(trigger.get(field, "")).strip_edges().is_empty():
					result.add_error(
						"missing_regeneration_trigger_field",
						"Regeneration trigger field '%s' cannot be empty." % field,
						"regeneration_triggers.%d.%s" % [index, field]
					)
			if str(trigger.get("metric", "")) not in HORIZON_TRIGGER_METRICS:
				result.add_error(
					"invalid_regeneration_trigger_metric",
					"Regeneration trigger metric is unsupported.",
					"regeneration_triggers.%d.metric" % index
				)
			if str(trigger.get("action", "")) not in HORIZON_TRIGGER_ACTIONS:
				result.add_error(
					"invalid_regeneration_trigger_action",
					"Regeneration trigger action is unsupported.",
					"regeneration_triggers.%d.action" % index
				)
			if int(trigger.get("threshold", -1)) < 0:
				result.add_error(
					"invalid_regeneration_trigger_threshold",
					"Regeneration trigger threshold cannot be negative.",
					"regeneration_triggers.%d.threshold" % index
				)
	if not value.get("expansion_rules", []) is Array:
		result.add_error(
			"invalid_expansion_rules",
			"Expansion rules must be an array.",
			"expansion_rules"
		)
	return result


static func normalize_rumor_trails(source: Variant) -> Array:
	var normalized: Array = []
	if not source is Array:
		return normalized
	for index in range((source as Array).size()):
		var raw = (source as Array)[index]
		if not raw is Dictionary:
			continue
		var trail := (raw as Dictionary).duplicate(true)
		var name := str(trail.get("name", "Rumor Trail %d" % (index + 1))).strip_edges()
		if name.is_empty():
			name = "Rumor Trail %d" % (index + 1)
		trail["name"] = name
		var trail_id := str(trail.get("trail_id", "")).strip_edges()
		if trail_id.is_empty():
			trail_id = "rumor_trail.%s" % _slug(name)
		trail["trail_id"] = trail_id
		var hint_theme := str(trail.get("hint_theme", "")).strip_edges()
		if hint_theme.is_empty():
			hint_theme = str(trail.get("payoff", "")).strip_edges()
		if hint_theme.is_empty():
			hint_theme = "A strange frontier rumor that points toward a hidden discovery."
		trail["hint_theme"] = hint_theme
		var clue_count := int(trail.get("clue_count", 0))
		trail["clue_count"] = maxi(2, clue_count)
		var discovery_type := str(trail.get("discovery_type", "")).strip_edges()
		if discovery_type not in RUMOR_DISCOVERY_TYPES:
			discovery_type = "hidden_discovery"
		trail["discovery_type"] = discovery_type
		var rarity := str(trail.get("rarity", "")).strip_edges()
		if rarity not in RUMOR_RARITIES:
			rarity = "rare"
		trail["rarity"] = rarity
		if not trail.get("clue_templates", []) is Array:
			trail["clue_templates"] = []
		normalized.append(trail)
	return normalized


static func normalize_regeneration_triggers(source: Variant) -> Array:
	var normalized: Array = []
	if not source is Array:
		return normalized
	for index in range((source as Array).size()):
		var raw = (source as Array)[index]
		if not raw is Dictionary:
			continue
		var trigger := (raw as Dictionary).duplicate(true)
		var trigger_id := str(trigger.get("id", "")).strip_edges()
		if trigger_id.is_empty():
			trigger_id = "story_horizon_trigger_%d" % (index + 1)
		trigger["id"] = trigger_id
		var metric := str(trigger.get("metric", "")).strip_edges()
		if metric not in HORIZON_TRIGGER_METRICS:
			metric = _default_trigger_metric(trigger_id)
		trigger["metric"] = metric
		var action := str(trigger.get("action", "")).strip_edges()
		if action not in HORIZON_TRIGGER_ACTIONS:
			action = _default_trigger_action(metric)
		trigger["action"] = action
		var threshold := int(trigger.get("threshold", -1))
		if threshold < 0:
			threshold = _default_trigger_threshold(metric)
		trigger["threshold"] = threshold
		if str(trigger.get("description", "")).strip_edges().is_empty():
			trigger["description"] = "Extend prepared campaign story when %s reaches %d." % [
				metric,
				threshold,
			]
		normalized.append(trigger)
	return normalized


static func _default_trigger_metric(trigger_id: String) -> String:
	if trigger_id.contains("rumor"):
		return "rumor_trails_remaining"
	if trigger_id.contains("arc"):
		return "active_story_arcs_remaining"
	return "prepared_systems_remaining"


static func _default_trigger_action(metric: String) -> String:
	match metric:
		"rumor_trails_remaining":
			return "append_rumor_trail"
		"active_story_arcs_remaining", "major_arc_state":
			return "append_story_arc"
		_:
			return "append_story_horizon"


static func _default_trigger_threshold(metric: String) -> int:
	match metric:
		"prepared_systems_remaining":
			return 2
		_:
			return 0


static func _slug(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	var output := ""
	for index in range(clean.length()):
		var c := clean[index]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			output += c
		elif not output.ends_with("_"):
			output += "_"
	output = output.strip_edges().trim_prefix("_").trim_suffix("_")
	if output.is_empty():
		output = value.sha256_text().substr(0, 12)
	return output.left(48)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
