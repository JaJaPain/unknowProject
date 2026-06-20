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


func prompt_context() -> String:
	if not is_valid() or data.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("Campaign Bible:")
	lines.append("- Generation status: %s" % generation_status())
	lines.append("- Source: %s" % source_name())
	lines.append("- Tone: %s" % str(data.get("tone", "")))
	lines.append("- Core pressure: %s" % str(data.get("core_pressure", "")))
	lines.append("- Kaelen rule: %s" % str(data.get("kaelen_rule", "")))
	lines.append("- Faction reveal rule: %s" % str(data.get("faction_reveal_rule", "")))
	lines.append("- Humor rule: %s" % str(data.get("humor_rule", "")))
	lines.append("- Address rule: %s" % str(data.get("address_rule", "")))
	lines.append("- Story horizon rule: %s" % str(data.get("story_horizon_rule", "")))
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
					"- %s: %s" %
					[str(trail.get("name", "")), str(trail.get("payoff", ""))]
				)
	var regeneration_triggers: Array = data.get("regeneration_triggers", [])
	if not regeneration_triggers.is_empty():
		lines.append("Story horizon regeneration triggers:")
		for trigger in regeneration_triggers:
			if trigger is Dictionary:
				lines.append(
					"- %s: %s" %
					[str(trigger.get("id", "")), str(trigger.get("description", ""))]
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
	validation.merge(_validate_data(data, campaign_id), "campaign_bible")


func _commit(next_data: Dictionary, operation: String) -> Dictionary:
	return TransactionStoreType.commit_json_set(
		campaign_path,
		operation,
		{BIBLE_PATH: next_data},
		BIBLE_PATH,
		func(_path: String, value: Dictionary) -> ValidationResult:
			return _validate_data(value, str(campaign.get("id", "")))
	)


static func _default_bible(campaign_id: String, campaign_seed: String) -> Dictionary:
	return {
		"schema_version": DOCUMENT_VERSION,
		"document_type": "campaign_bible",
		"campaign_id": campaign_id,
		"campaign_seed": campaign_seed,
		"source": STATUS_PROCEDURAL_BOOTSTRAP,
		"generation_status": STATUS_PROCEDURAL_BOOTSTRAP,
		"source_model": "",
		"generation_note": "LLM campaign bible generation has not run yet; this bootstrap is labeled so diagnostics can see it.",
		"last_generation_error": "",
		"tone": "PG-13 frontier space opera with dry, slightly dark humor.",
		"core_pressure": "The old home-system powers are stable enough to feel known, but the frontier beyond the gates is changing faster than anyone admits.",
		"kaelen_rule": "Kaelen is the only fixed recurring character. Her actions can be revealed, but her true nature and full mystery should never be completely explained.",
		"faction_reveal_rule": "Reveal new factions, conflicts, ores, upgrades, and secrets through gate travel rather than upfront exposition.",
		"humor_rule": "Use humor as relief from killing, betrayal, power, and money. Prefer dry or dark wit, with occasional oddballs.",
		"address_rule": "Agents may call the player Indy in an opening request, but should avoid repeating the name in immediate acceptance follow-ups.",
		"fallback_rule": "Fallback content is last-resort only and should be visible to diagnostics.",
		"story_horizon_rule": "The campaign bible owns the current prepared story horizon. When the player nears its edge, append a new horizon with the larger model instead of replacing known canon.",
		"story_arcs": [
			{
				"name": "Home Powers, Frontier Pressure",
				"summary": "Zenith, Aurelia, and Vanguard remain the known baseline while new factions appear past the gates.",
			},
			{
				"name": "Kaelen's Unfinished Map",
				"summary": "Kaelen can guide, delay, and bargain over exits, but her deeper motive remains unresolved.",
			},
		],
		"rumor_trails": [
			{
				"name": "The Thing Everyone Heard Wrong",
				"clue_count": 4,
				"payoff": "A rare hidden discovery or endgame easter egg chosen by the future campaign-level LLM.",
			},
		],
		"regeneration_triggers": [
			{
				"id": "frontier_horizon_low",
				"description": "Fewer than the target number of prepared future systems or story packs remain beyond known gates.",
			},
			{
				"id": "major_arc_resolved",
				"description": "A major campaign arc resolves and no successor arc has been prepared.",
			},
			{
				"id": "rumor_trail_exhausted",
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
		"tone",
		"core_pressure",
		"kaelen_rule",
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
	if not value.get("story_arcs", []) is Array:
		result.add_error("invalid_story_arcs", "Story arcs must be an array.", "story_arcs")
	if not value.get("rumor_trails", []) is Array:
		result.add_error("invalid_rumor_trails", "Rumor trails must be an array.", "rumor_trails")
	if not value.get("regeneration_triggers", []) is Array:
		result.add_error(
			"invalid_regeneration_triggers",
			"Regeneration triggers must be an array.",
			"regeneration_triggers"
		)
	if not value.get("expansion_rules", []) is Array:
		result.add_error(
			"invalid_expansion_rules",
			"Expansion rules must be an array.",
			"expansion_rules"
		)
	return result


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
