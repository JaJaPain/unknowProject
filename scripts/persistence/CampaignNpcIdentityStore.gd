class_name CampaignNpcIdentityStore
extends RefCounted

const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)
const CharacterDirectorType := preload("res://scripts/story/CharacterDirector.gd")

const DOCUMENT_VERSION := 2
const NPCS_PATH := "npc_identities.json"
const NPC_PREFIX := "npc.gen."
const MAX_RECENT_TRAIT_COMBINATIONS := 24

const PERSONA_FIELDS := [
	"core_drive",
	"current_want",
	"fear",
	"contradiction",
	"social_strategy",
	"pressure_tell",
	"kindness_tell",
	"verbal_habit",
	"humor_mechanism",
	"taboo",
]

const VOICE_RULE_STRING_FIELDS := [
	"sentence_shape",
	"address_rule",
]

const VOICE_RULE_ARRAY_FIELDS := [
	"favored_vocabulary",
	"banned_tics",
]

var campaign_path: String
var campaign: Dictionary = {}
var data: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> RefCounted:
	var store = load("res://scripts/persistence/CampaignNpcIdentityStore.gd").new()
	store.campaign_path = path.trim_suffix("/")
	store._load_or_create()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func all_npcs() -> Array:
	return (data.get("npcs", []) as Array).duplicate(true)


func npc_ids() -> Array[String]:
	var ids: Array[String] = []
	for npc in all_npcs():
		if npc is Dictionary:
			ids.append(str(npc.get("id", "")))
	return ids


func npc_by_display_name(display_name: String) -> Dictionary:
	var clean_name := display_name.strip_edges()
	for npc in data.get("npcs", []):
		if npc is Dictionary and str(npc.get("display_name", "")) == clean_name:
			return (npc as Dictionary).duplicate(true)
	return {}


func npc_by_id(npc_id: String) -> Dictionary:
	for npc in data.get("npcs", []):
		if npc is Dictionary and str(npc.get("id", "")) == npc_id:
			return (npc as Dictionary).duplicate(true)
	return {}


func ensure_npc_record(source: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("NPC identity store is invalid.")
	var record := _record_from_source(source)
	if str(record.get("display_name", "")).is_empty():
		return _failure("NPC display name is required.")
	if str(record.get("home_station_id", "")).is_empty():
		return _failure("NPC home station is required.")
	var existing_index := _find_by_source_key(str(record.get("source_key", "")))
	if existing_index >= 0:
		var existing: Dictionary = data["npcs"][existing_index]
		return {"ok": true, "created": false, "npc": existing.duplicate(true)}
	var next_data := data.duplicate(true)
	var npcs: Array = next_data.get("npcs", []).duplicate(true)
	npcs.append(record)
	next_data["npcs"] = npcs
	next_data["recent_trait_combinations"] = _remember_trait_combination(
		next_data.get("recent_trait_combinations", []),
		str(record.get("trait_combination_key", ""))
	)
	var committed := _commit(next_data, "npc_identity_upsert")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "created": true, "npc": record.duplicate(true)}


func remember_line(npc_id: String, text: String, topic: String = "") -> Dictionary:
	if not is_valid():
		return _failure("NPC identity store is invalid.")
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return _failure("NPC line text is required.")
	var index := _find_by_id(npc_id)
	if index < 0:
		return _failure("NPC record was not found.")
	var next_data := data.duplicate(true)
	var npcs: Array = next_data.get("npcs", []).duplicate(true)
	var npc: Dictionary = (npcs[index] as Dictionary).duplicate(true)
	var fingerprints: Array = npc.get("line_memory_fingerprints", []).duplicate()
	var fingerprint := _fingerprint(clean_text)
	if fingerprint not in fingerprints:
		fingerprints.append(fingerprint)
		while fingerprints.size() > 32:
			fingerprints.pop_front()
	npc["line_memory_fingerprints"] = fingerprints
	npc["last_topic"] = topic
	npc["updated_at_unix"] = int(Time.get_unix_time_from_system())
	npcs[index] = npc
	next_data["npcs"] = npcs
	var committed := _commit(next_data, "npc_identity_line_memory")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "npc": npc.duplicate(true)}


func prompt_context(system_id: String = "", limit: int = 16) -> String:
	var selected: Array = []
	for npc in data.get("npcs", []):
		if not npc is Dictionary:
			continue
		if not system_id.is_empty() and str(npc.get("home_system_id", "")) != system_id:
			continue
		selected.append(npc)
		if selected.size() >= maxi(1, limit):
			break
	if selected.is_empty():
		return "No persistent generated NPC identities recorded yet."
	var lines: Array[String] = ["Persistent generated NPCs:"]
	for npc in selected:
		lines.append(
			"- %s (%s, %s): faction=%s, humor=%s, memory=%s" %
			[
				str(npc.get("display_name", "")),
				str(npc.get("job_role", "")),
				str(npc.get("home_station_id", "")),
				str(npc.get("faction_id", "")),
				str(npc.get("humor_style", "")),
				str(npc.get("memory_summary", "")),
			]
		)
	return "\n".join(lines)


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
			"NPC identities require a valid campaign id.",
			"campaign.id"
		)
		return
	var npcs_path := "%s/%s" % [campaign_path, NPCS_PATH]
	if not FileAccess.file_exists(npcs_path):
		data = _default_document(campaign_id)
		var committed := _commit(data, "npc_identity_bootstrap")
		if not bool(committed.get("ok", false)):
			validation.add_error(
				"npc_identity_bootstrap_failed",
				str(committed.get("error", "NPC identities could not be created.")),
				NPCS_PATH
			)
		return
	var npcs_result := DomainJsonType.read_object(npcs_path)
	validation.merge(npcs_result["validation"], "npc_identities")
	if not validation.is_valid():
		return
	data = npcs_result["data"]
	if int(data.get("schema_version", 0)) < DOCUMENT_VERSION:
		data = _migrate_legacy_data(
			data,
			campaign_id,
			str(campaign.get("campaign_seed", campaign_id))
		)
		var migrated := _commit(data, "npc_identity_migration_v2")
		if not bool(migrated.get("ok", false)):
			validation.add_error(
				"npc_identity_migration_failed",
				str(migrated.get("error", "NPC identity migration failed.")),
				NPCS_PATH
			)
			return
	validation.merge(_validate_data(data, campaign_id), "npc_identities")


func _commit(next_data: Dictionary, operation: String) -> Dictionary:
	return TransactionStoreType.commit_json_set(
		campaign_path,
		operation,
		{NPCS_PATH: next_data},
		NPCS_PATH,
		func(_path: String, value: Dictionary) -> ValidationResult:
			return _validate_data(value, str(campaign.get("id", "")))
	)


func _record_from_source(source: Dictionary) -> Dictionary:
	var display_name := str(source.get("display_name", "")).strip_edges()
	var home_station_id := str(source.get("home_station_id", "")).strip_edges()
	var source_key := str(source.get("source_key", "")).strip_edges()
	if source_key.is_empty():
		source_key = "%s|%s|%s" % [
			home_station_id,
			display_name,
			str(source.get("job_role", "")),
		]
	var npc_id := str(source.get("id", "")).strip_edges()
	if npc_id.is_empty():
		npc_id = _generated_npc_id(source_key)
	var card := _character_card_from_source(
		source,
		npc_id,
		str(campaign.get("campaign_seed", campaign.get("id", ""))),
		_clean_string_array(data.get("recent_trait_combinations", []))
	)
	return {
		"id": npc_id,
		"source_key": source_key,
		"display_name": display_name,
		"portrait_id": str(source.get("portrait_id", "")),
		"voice_profile_id": str(source.get("voice_profile_id", "")),
		"faction_id": str(source.get("faction_id", "")),
		"faction_key": str(source.get("faction_key", "")),
		"job_role": str(source.get("job_role", "Local contact")),
		"home_system_id": str(source.get("home_system_id", "")),
		"home_station_id": home_station_id,
		"personality_tags": _clean_string_array(source.get("personality_tags", [])),
		"humor_style": str(source.get("humor_style", "")),
		"trait_combination_key": str(card.get("trait_combination_key", "")),
		"persona": card.get("persona", _persona_from_source(source)),
		"voice_rules": card.get("voice_rules", _voice_rules_from_source(source)),
		"relationship_state": str(source.get("relationship_state", "neutral")),
		"memory_summary": str(source.get("memory_summary", "")),
		"line_memory_fingerprints": _clean_string_array(
			source.get("line_memory_fingerprints", [])
		),
		"lifecycle": _lifecycle_from_source(source),
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"updated_at_unix": int(Time.get_unix_time_from_system()),
	}


func _generated_npc_id(source_key: String) -> String:
	var campaign_key := str(campaign.get("id", "")).sha256_text().substr(0, 8)
	var creation_key := _slug(source_key).left(30)
	if creation_key.is_empty():
		creation_key = source_key.sha256_text().substr(0, 12)
	var candidate := "%s%s.%s_%s" % [
		NPC_PREFIX,
		campaign_key,
		creation_key,
		source_key.sha256_text().substr(0, 8),
	]
	if DomainIdType.is_valid(candidate, "npc"):
		return candidate
	return "%s%s.%s" % [
		NPC_PREFIX,
		campaign_key,
		source_key.sha256_text().substr(0, 12),
	]


static func _default_document(campaign_id: String) -> Dictionary:
	return {
		"schema_version": DOCUMENT_VERSION,
		"document_type": "campaign_npc_identities",
		"campaign_id": campaign_id,
		"recent_trait_combinations": [],
		"npcs": [],
	}


static func _validate_data(value: Dictionary, campaign_id: String) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(value.get("schema_version", 0)) != DOCUMENT_VERSION:
		result.add_error(
			"invalid_npc_identity_version",
			"NPC identity schema version is invalid.",
			"schema_version"
		)
	if str(value.get("document_type", "")) != "campaign_npc_identities":
		result.add_error(
			"invalid_npc_identity_type",
			"NPC identity document type is invalid.",
			"document_type"
		)
	if str(value.get("campaign_id", "")) != campaign_id:
		result.add_error(
			"npc_identity_campaign_mismatch",
			"NPC identities belong to a different campaign.",
			"campaign_id"
		)
	if not value.get("npcs", []) is Array:
		result.add_error("invalid_npcs", "NPC identities must be an array.", "npcs")
		return result
	if not value.get("recent_trait_combinations", []) is Array:
		result.add_error(
			"invalid_recent_trait_combinations",
			"Recent NPC trait combinations must be an array.",
			"recent_trait_combinations"
		)
	var seen_ids := {}
	var seen_sources := {}
	var npcs: Array = value.get("npcs", [])
	for index in range(npcs.size()):
		var npc: Variant = npcs[index]
		if not npc is Dictionary:
			result.add_error(
				"invalid_npc_record",
				"NPC identity record must be an object.",
				"npcs.%d" % index
			)
			continue
		_validate_npc_record(npc, result, "npcs.%d" % index, seen_ids, seen_sources)
	return result


static func _validate_npc_record(
	npc: Dictionary,
	result: ValidationResult,
	path: String,
	seen_ids: Dictionary,
	seen_sources: Dictionary
) -> void:
	var npc_id := str(npc.get("id", ""))
	if not DomainIdType.is_valid(npc_id, "npc"):
		result.add_error("invalid_npc_id", "NPC ID is invalid.", "%s.id" % path)
	elif not npc_id.begins_with(NPC_PREFIX):
		result.add_error("invalid_npc_prefix", "NPC ID must use generated prefix.", "%s.id" % path)
	elif seen_ids.has(npc_id):
		result.add_error("duplicate_npc_id", "NPC ID is duplicated.", "%s.id" % path)
	else:
		seen_ids[npc_id] = true
	var source_key := str(npc.get("source_key", ""))
	if source_key.is_empty():
		result.add_error("missing_npc_source_key", "NPC source key is required.", "%s.source_key" % path)
	elif seen_sources.has(source_key):
		result.add_error("duplicate_npc_source_key", "NPC source key is duplicated.", "%s.source_key" % path)
	else:
		seen_sources[source_key] = true
	for field in [
		"display_name",
		"portrait_id",
		"voice_profile_id",
		"job_role",
		"home_station_id",
		"relationship_state",
	]:
		if str(npc.get(field, "")).strip_edges().is_empty():
			result.add_error("missing_npc_field", "NPC identity field is required.", "%s.%s" % [path, field])
	if not npc.get("personality_tags", []) is Array:
		result.add_error("invalid_personality_tags", "Personality tags must be an array.", "%s.personality_tags" % path)
	if not npc.get("persona", {}) is Dictionary:
		result.add_error("invalid_persona", "NPC persona must be an object.", "%s.persona" % path)
	else:
		_validate_persona(npc.get("persona", {}) as Dictionary, result, "%s.persona" % path)
	if not npc.get("voice_rules", {}) is Dictionary:
		result.add_error("invalid_voice_rules", "NPC voice rules must be an object.", "%s.voice_rules" % path)
	else:
		_validate_voice_rules(npc.get("voice_rules", {}) as Dictionary, result, "%s.voice_rules" % path)
	if not npc.get("line_memory_fingerprints", []) is Array:
		result.add_error("invalid_line_memory", "Line memory must be an array.", "%s.line_memory_fingerprints" % path)
	if not npc.get("lifecycle", {}) is Dictionary:
		result.add_error("invalid_lifecycle", "Lifecycle must be an object.", "%s.lifecycle" % path)
	if not str(npc.get("trait_combination_key", "")).strip_edges().is_empty() \
			and str(npc.get("trait_combination_key", "")) \
				!= str(npc.get("trait_combination_key", "")).strip_edges():
		result.add_error(
			"invalid_trait_combination_key",
			"NPC trait combination key cannot contain leading or trailing whitespace.",
			"%s.trait_combination_key" % path
		)


static func _validate_persona(
	persona: Dictionary,
	result: ValidationResult,
	path: String
) -> void:
	for field in PERSONA_FIELDS:
		if str(persona.get(field, "")).strip_edges().is_empty():
			result.add_error(
				"missing_persona_field",
				"NPC persona field is required.",
				"%s.%s" % [path, field]
			)


static func _validate_voice_rules(
	voice_rules: Dictionary,
	result: ValidationResult,
	path: String
) -> void:
	for field in VOICE_RULE_STRING_FIELDS:
		if str(voice_rules.get(field, "")).strip_edges().is_empty():
			result.add_error(
				"missing_voice_rule_field",
				"NPC voice rule field is required.",
				"%s.%s" % [path, field]
			)
	for field in VOICE_RULE_ARRAY_FIELDS:
		if not voice_rules.get(field, []) is Array:
			result.add_error(
				"invalid_voice_rule_array",
				"NPC voice rule field must be an array.",
				"%s.%s" % [path, field]
			)


static func _migrate_legacy_data(
	legacy: Dictionary,
	campaign_id: String,
	campaign_seed: String
) -> Dictionary:
	var migrated := legacy.duplicate(true)
	migrated["schema_version"] = DOCUMENT_VERSION
	migrated["document_type"] = "campaign_npc_identities"
	migrated["campaign_id"] = campaign_id
	var recent_combinations := _clean_string_array(
		legacy.get("recent_trait_combinations", [])
	)
	var migrated_npcs: Array = []
	var source_npcs: Array = legacy.get("npcs", []) if legacy.get("npcs", []) is Array else []
	for value in source_npcs:
		if not value is Dictionary:
			migrated_npcs.append(value)
			continue
		var npc: Dictionary = (value as Dictionary).duplicate(true)
		var card := _character_card_from_source(
			npc,
			str(npc.get("id", "")),
			campaign_seed,
			recent_combinations
		)
		npc["trait_combination_key"] = str(card.get("trait_combination_key", ""))
		npc["persona"] = card.get("persona", _persona_from_source(npc))
		npc["voice_rules"] = card.get("voice_rules", _voice_rules_from_source(npc))
		recent_combinations = _remember_trait_combination(
			recent_combinations,
			str(npc.get("trait_combination_key", ""))
		)
		migrated_npcs.append(npc)
	migrated["npcs"] = migrated_npcs
	migrated["recent_trait_combinations"] = recent_combinations
	return migrated


static func _character_card_from_source(
	source: Dictionary,
	npc_id: String,
	campaign_seed: String,
	recent_combinations: Array = []
) -> Dictionary:
	var existing_persona: Variant = source.get("persona", null)
	var existing_voice: Variant = source.get("voice_rules", null)
	if existing_persona is Dictionary and existing_voice is Dictionary:
		return {
			"persona": (existing_persona as Dictionary).duplicate(true),
			"voice_rules": (existing_voice as Dictionary).duplicate(true),
			"trait_combination_key": str(source.get("trait_combination_key", "")),
		}
	var source_with_id := source.duplicate(true)
	source_with_id["id"] = npc_id
	var generated := CharacterDirectorType.generate_card(
		source_with_id,
		campaign_seed,
		recent_combinations
	)
	if bool(generated.get("ok", false)) \
			and CharacterDirectorType.is_complete_card(generated.get("card", {})):
		var card: Dictionary = generated.get("card", {})
		return {
			"persona": (card.get("persona", {}) as Dictionary).duplicate(true),
			"voice_rules": (card.get("voice_rules", {}) as Dictionary).duplicate(true),
			"trait_combination_key": str(card.get("trait_combination_key", "")),
		}
	return {
		"persona": _persona_from_source(source),
		"voice_rules": _voice_rules_from_source(source),
		"trait_combination_key": str(source.get("trait_combination_key", "")),
	}


static func _persona_from_source(source: Dictionary) -> Dictionary:
	var existing: Dictionary = source.get("persona", {}) \
		if source.get("persona", {}) is Dictionary else {}
	var tags := _clean_string_array(source.get("personality_tags", []))
	var tag_text := ", ".join(tags) if not tags.is_empty() else "practical"
	var humor := str(source.get("humor_style", "")).strip_edges()
	if humor.is_empty():
		humor = "dry practical understatement"
	var role := str(source.get("job_role", "local contact")).strip_edges()
	if role.is_empty():
		role = "local contact"
	var summary := str(source.get("memory_summary", "")).strip_edges()
	return {
		"core_drive": _string_or_default(
			existing,
			"core_drive",
			"Keep their corner of station life functional enough for people to survive it."
		),
		"current_want": _string_or_default(
			existing,
			"current_want",
			summary if not summary.is_empty() else "Get through the current pressure without losing face or lives."
		),
		"fear": _string_or_default(
			existing,
			"fear",
			"Being treated as disposable when the station chooses whose problem matters."
		),
		"contradiction": _string_or_default(
			existing,
			"contradiction",
			"Reads as %s, but becomes unexpectedly specific when someone is in real trouble." % tag_text
		),
		"social_strategy": _string_or_default(
			existing,
			"social_strategy",
			"Tests whether the other person is listening before offering warmth."
		),
		"pressure_tell": _string_or_default(
			existing,
			"pressure_tell",
			"Gets more concrete and procedural under stress."
		),
		"kindness_tell": _string_or_default(
			existing,
			"kindness_tell",
			"Solves a practical problem before admitting they care."
		),
		"verbal_habit": _string_or_default(
			existing,
			"verbal_habit",
			"Frames trouble through their %s work without turning it into a catchphrase." % role
		),
		"humor_mechanism": _string_or_default(existing, "humor_mechanism", humor),
		"taboo": _string_or_default(
			existing,
			"taboo",
			"Does not make light of civilian deaths or decompression."
		),
	}


static func _voice_rules_from_source(source: Dictionary) -> Dictionary:
	var existing: Dictionary = source.get("voice_rules", {}) \
		if source.get("voice_rules", {}) is Dictionary else {}
	var role_words := _vocabulary_from_role(str(source.get("job_role", "")))
	return {
		"sentence_shape": _string_or_default(
			existing,
			"sentence_shape",
			"plain, specific, with one dry afterthought at most"
		),
		"address_rule": _string_or_default(
			existing,
			"address_rule",
			"No private nickname; uses pilot or captain sparingly."
		),
		"favored_vocabulary": _clean_string_array(
			existing.get("favored_vocabulary", role_words)
		),
		"banned_tics": _clean_string_array(
			existing.get("banned_tics", ["Shiny", "my friend", "as you know"])
		),
	}


static func _string_or_default(
	source: Dictionary,
	field: String,
	default_value: String
) -> String:
	var value := str(source.get(field, "")).strip_edges()
	return value if not value.is_empty() else default_value


static func _vocabulary_from_role(role: String) -> Array:
	var clean_role := role.to_lower()
	if clean_role.contains("dock"):
		return ["vector", "clearance", "queue"]
	if clean_role.contains("engineer") or clean_role.contains("mechanic"):
		return ["load", "seal", "tolerance"]
	if clean_role.contains("broker") or clean_role.contains("contact"):
		return ["terms", "margin", "favor"]
	if clean_role.contains("security") or clean_role.contains("marshal"):
		return ["witness", "route", "risk"]
	return ["station", "work", "pressure"]


func _find_by_source_key(source_key: String) -> int:
	var npcs: Array = data.get("npcs", [])
	for index in range(npcs.size()):
		var npc: Variant = npcs[index]
		if npc is Dictionary and str(npc.get("source_key", "")) == source_key:
			return index
	return -1


func _find_by_id(npc_id: String) -> int:
	var npcs: Array = data.get("npcs", [])
	for index in range(npcs.size()):
		var npc: Variant = npcs[index]
		if npc is Dictionary and str(npc.get("id", "")) == npc_id:
			return index
	return -1


static func _clean_string_array(value: Variant) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for item in value:
		var clean := str(item).strip_edges()
		if not clean.is_empty() and clean not in result:
			result.append(clean)
	return result


static func _remember_trait_combination(
	current: Variant,
	trait_combination_key: String
) -> Array:
	var remembered := _clean_string_array(current)
	var clean_key := trait_combination_key.strip_edges()
	if clean_key.is_empty():
		return remembered
	if clean_key in remembered:
		remembered.erase(clean_key)
	remembered.append(clean_key)
	while remembered.size() > MAX_RECENT_TRAIT_COMBINATIONS:
		remembered.pop_front()
	return remembered


static func _lifecycle_from_source(source: Dictionary) -> Dictionary:
	var source_lifecycle: Dictionary = source.get("lifecycle", {})
	return {
		"available": bool(source_lifecycle.get("available", true)),
		"relocated": bool(source_lifecycle.get("relocated", false)),
		"captured": bool(source_lifecycle.get("captured", false)),
		"dead": bool(source_lifecycle.get("dead", false)),
		"protected": bool(source_lifecycle.get("protected", false)),
	}


static func _slug(value: String) -> String:
	var raw := value.to_lower()
	var output := ""
	for index in range(raw.length()):
		var ch := raw.substr(index, 1)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			output += ch
		else:
			output += "_"
	while output.contains("__"):
		output = output.replace("__", "_")
	while output.begins_with("_"):
		output = output.trim_prefix("_")
	while output.ends_with("_"):
		output = output.trim_suffix("_")
	return output


static func _fingerprint(value: String) -> String:
	return value.to_lower().strip_edges().sha256_text().substr(0, 16)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
