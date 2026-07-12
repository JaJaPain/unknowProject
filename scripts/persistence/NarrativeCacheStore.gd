class_name NarrativeCacheStore
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
const CACHE_PATH := "narrative_cache.json"
const SEMANTIC_KEY_VERSION := 1

var campaign_path: String
var campaign: Dictionary = {}
var data: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> RefCounted:
	var store = load("res://scripts/persistence/NarrativeCacheStore.gd").new()
	store.campaign_path = path.trim_suffix("/")
	store._load_or_create()
	return store


func is_valid() -> bool:
	return validation.is_valid()


static func semantic_cache_key(inputs: Dictionary) -> String:
	return "cache.%s" % semantic_context_fingerprint(inputs).substr(0, 32)


static func semantic_context_fingerprint(inputs: Dictionary) -> String:
	return JSON.stringify(_semantic_identity(inputs), "", true).sha256_text()


func entries() -> Dictionary:
	return (data.get("entries", {}) as Dictionary).duplicate(true)


func get_entry(cache_key: String) -> Dictionary:
	var clean_key := cache_key.strip_edges()
	var raw: Variant = data.get("entries", {}).get(clean_key, {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


func upsert_entry(entry: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Narrative cache store is invalid.")
	var cache_key := str(entry.get("cache_key", "")).strip_edges()
	if cache_key.is_empty():
		return _failure("Narrative cache entry requires cache_key.")
	var next_data := data.duplicate(true)
	var next_entries: Dictionary = entries()
	var prepared := entry.duplicate(true)
	prepared["cache_key"] = cache_key
	prepared["campaign_id"] = str(campaign.get("id", ""))
	prepared["updated_at_unix"] = int(Time.get_unix_time_from_system())
	if not prepared.has("created_at_unix"):
		prepared["created_at_unix"] = prepared["updated_at_unix"]
	if not prepared.has("consumed"):
		prepared["consumed"] = false
	next_entries[cache_key] = prepared
	next_data["entries"] = next_entries
	var committed := _commit(next_data, "narrative_cache_upsert")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "entry": prepared.duplicate(true)}


func mark_consumed(cache_key: String) -> Dictionary:
	var entry := get_entry(cache_key)
	if entry.is_empty():
		return _failure("Narrative cache entry not found.")
	entry["consumed"] = true
	return upsert_entry(entry)


func invalidate_by_subject(subject_id: String) -> Dictionary:
	if not is_valid():
		return _failure("Narrative cache store is invalid.")
	var clean_subject := subject_id.strip_edges()
	var next_entries: Dictionary = entries()
	var removed: Array[String] = []
	for cache_key in next_entries.keys():
		var entry: Variant = next_entries[cache_key]
		if entry is Dictionary \
				and str((entry as Dictionary).get("subject_id", "")) == clean_subject:
			removed.append(str(cache_key))
	for cache_key in removed:
		next_entries.erase(cache_key)
	var next_data := data.duplicate(true)
	next_data["entries"] = next_entries
	var committed := _commit(next_data, "narrative_cache_invalidate_subject")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "removed": removed}


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
			"Narrative cache requires a valid campaign id.",
			"campaign.id"
		)
		return
	var cache_path := "%s/%s" % [campaign_path, CACHE_PATH]
	if not FileAccess.file_exists(cache_path):
		data = _initial_data(campaign_id)
		var committed := _commit(data, "narrative_cache_bootstrap")
		if not bool(committed.get("ok", false)):
			validation.add_error(
				"narrative_cache_bootstrap_failed",
				str(committed.get("error", "Narrative cache could not be created.")),
				CACHE_PATH
			)
		return
	var cache_result := DomainJsonType.read_object(cache_path)
	validation.merge(cache_result["validation"], "narrative_cache")
	if not validation.is_valid():
		return
	data = cache_result["data"]
	validation.merge(_validate_data(data, campaign_id), "narrative_cache")


func _commit(next_data: Dictionary, operation: String) -> Dictionary:
	return TransactionStoreType.commit_json_set(
		campaign_path,
		operation,
		{CACHE_PATH: next_data},
		CACHE_PATH,
		func(_path: String, value: Dictionary) -> ValidationResult:
			return _validate_data(value, str(campaign.get("id", "")))
	)


static func _initial_data(campaign_id: String) -> Dictionary:
	return {
		"schema_version": DOCUMENT_VERSION,
		"document_type": "narrative_cache",
		"ownership": "disposable",
		"campaign_id": campaign_id,
		"entries": {},
	}


static func _semantic_identity(inputs: Dictionary) -> Dictionary:
	return {
		"semantic_key_version": SEMANTIC_KEY_VERSION,
		"campaign_id": str(inputs.get("campaign_id", "")),
		"kind": str(inputs.get("kind", "")),
		"subject_id": str(inputs.get("subject_id", "")),
		"speaker_id": str(inputs.get("speaker_id", "")),
		"system_id": str(inputs.get("system_id", "")),
		"station_id": str(inputs.get("station_id", "")),
		"story_revision": int(inputs.get("story_revision", 0)),
		"thread_revision": int(inputs.get("thread_revision", 0)),
		"beat_revision": int(inputs.get("beat_revision", 0)),
		"knowledge_revision": int(inputs.get("knowledge_revision", 0)),
		"relationship_tier": str(inputs.get("relationship_tier", "")),
		"relationship_revision": int(inputs.get("relationship_revision", 0)),
		"recent_line_digest": str(inputs.get("recent_line_digest", "")),
		"knowledge_fact_states": _normalized_dictionary(
			inputs.get("knowledge_fact_states", {})
		),
		"mission_objective": _normalized_dictionary(
			inputs.get("mission_objective", {})
		),
		"choice_consequences": _normalized_dictionary(
			inputs.get("choice_consequences", {})
		),
		"player_state_bands": _normalized_dictionary(
			inputs.get("player_state_bands", {})
		),
	}


static func _normalized_dictionary(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var result := {}
	var keys: Array = (value as Dictionary).keys()
	keys.sort()
	for key in keys:
		var clean_key := str(key)
		var item: Variant = (value as Dictionary)[key]
		if item is Dictionary:
			result[clean_key] = _normalized_dictionary(item)
		elif item is Array:
			result[clean_key] = _normalized_array(item)
		else:
			result[clean_key] = item
	return result


static func _normalized_array(value: Variant) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	for item in (value as Array):
		if item is Dictionary:
			result.append(_normalized_dictionary(item))
		elif item is Array:
			result.append(_normalized_array(item))
		else:
			result.append(item)
	return result


static func _validate_data(value: Dictionary, campaign_id: String) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(value.get("schema_version", 0)) != DOCUMENT_VERSION:
		result.add_error(
			"invalid_narrative_cache_version",
			"Narrative cache schema version is invalid.",
			"schema_version"
		)
	if str(value.get("document_type", "")) != "narrative_cache":
		result.add_error(
			"invalid_narrative_cache_type",
			"Narrative cache document type is invalid.",
			"document_type"
		)
	if str(value.get("campaign_id", "")) != campaign_id:
		result.add_error(
			"narrative_cache_campaign_mismatch",
			"Narrative cache belongs to a different campaign.",
			"campaign_id"
		)
	if not value.get("entries", {}) is Dictionary:
		result.add_error(
			"invalid_narrative_cache_entries",
			"Narrative cache entries must be an object.",
			"entries"
		)
		return result
	var entries: Dictionary = value.get("entries", {})
	for cache_key in entries.keys():
		var raw: Variant = entries[cache_key]
		if not raw is Dictionary:
			result.add_error(
				"invalid_narrative_cache_entry",
				"Narrative cache entry must be an object.",
				"entries.%s" % str(cache_key)
			)
			continue
		var entry: Dictionary = raw
		if str(entry.get("cache_key", "")) != str(cache_key):
			result.add_error(
				"narrative_cache_key_mismatch",
				"Narrative cache entry key must match its cache_key field.",
				"entries.%s.cache_key" % str(cache_key)
			)
		for field in ["kind", "subject_id", "context_fingerprint"]:
			if str(entry.get(field, "")).strip_edges().is_empty():
				result.add_error(
					"missing_narrative_cache_field",
					"Narrative cache entry requires '%s'." % field,
					"entries.%s.%s" % [str(cache_key), field]
				)
		if not entry.get("text_bundle", {}) is Dictionary:
			result.add_error(
				"invalid_narrative_cache_text_bundle",
				"Narrative cache entry text_bundle must be an object.",
				"entries.%s.text_bundle" % str(cache_key)
			)
	return result


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
