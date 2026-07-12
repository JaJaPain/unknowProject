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
const DEFAULT_MAX_ENTRIES := 256
const DEFAULT_MAX_JSON_BYTES := 8 * 1024 * 1024

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


func text_fingerprints() -> Dictionary:
	return (data.get("text_fingerprints", {}) as Dictionary).duplicate(true)


func has_text_fingerprint(text: String) -> bool:
	var fingerprint := text_fingerprint(text)
	if fingerprint.is_empty():
		return false
	return text_fingerprints().has(fingerprint)


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
	_merge_text_fingerprints(next_data, prepared)
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


func mark_field_displayed(cache_key: String, field_id: String) -> Dictionary:
	var entry := get_entry(cache_key)
	if entry.is_empty():
		return _failure("Narrative cache entry not found.")
	var clean_field := field_id.strip_edges()
	if clean_field.is_empty():
		return _failure("Displayed cache field requires field_id.")
	var text_bundle: Dictionary = entry.get("text_bundle", {}) \
		if entry.get("text_bundle", {}) is Dictionary else {}
	var text := str(text_bundle.get(clean_field, "")).strip_edges()
	if text.is_empty():
		return _failure("Displayed cache field is not present in text bundle.")
	var displayed_fields: Dictionary = entry.get("displayed_fields", {}) \
		if entry.get("displayed_fields", {}) is Dictionary else {}
	displayed_fields[clean_field] = {
		"field_id": clean_field,
		"text_fingerprint": text_fingerprint(text),
		"displayed_at_unix": int(Time.get_unix_time_from_system()),
	}
	entry["displayed_fields"] = displayed_fields
	return upsert_entry(entry)


func mark_tts_status(
	cache_key: String,
	field_id: String,
	voice_profile_id: String,
	status: String,
	audio_path: String = ""
) -> Dictionary:
	var entry := get_entry(cache_key)
	if entry.is_empty():
		return _failure("Narrative cache entry not found.")
	var clean_field := field_id.strip_edges()
	if clean_field.is_empty():
		return _failure("TTS status requires field_id.")
	var clean_voice := voice_profile_id.strip_edges()
	if clean_voice.is_empty():
		return _failure("TTS status requires voice_profile_id.")
	var text_bundle: Dictionary = entry.get("text_bundle", {}) \
		if entry.get("text_bundle", {}) is Dictionary else {}
	var text := str(text_bundle.get(clean_field, "")).strip_edges()
	if text.is_empty():
		return _failure("TTS field is not present in text bundle.")
	var tts_ready: Dictionary = entry.get("tts_ready", {}) \
		if entry.get("tts_ready", {}) is Dictionary else {}
	var tts_key := "%s|%s" % [clean_field, clean_voice]
	tts_ready[tts_key] = {
		"field_id": clean_field,
		"voice_profile_id": clean_voice,
		"text_fingerprint": text_fingerprint(text),
		"status": status.strip_edges(),
		"audio_path": audio_path.strip_edges(),
		"updated_at_unix": int(Time.get_unix_time_from_system()),
	}
	entry["tts_ready"] = tts_ready
	return upsert_entry(entry)


func readiness(
	cache_key: String,
	required_fields: Array,
	voice_profile_id: String = ""
) -> Dictionary:
	var entry := get_entry(cache_key)
	if entry.is_empty():
		return {
			"text_ready": false,
			"audio_ready": false,
			"missing_text_fields": required_fields.duplicate(true),
			"missing_audio_fields": required_fields.duplicate(true),
			"failed_audio_fields": [],
		}
	var text_bundle: Dictionary = entry.get("text_bundle", {}) \
		if entry.get("text_bundle", {}) is Dictionary else {}
	var tts_ready: Dictionary = entry.get("tts_ready", {}) \
		if entry.get("tts_ready", {}) is Dictionary else {}
	var missing_text: Array[String] = []
	var missing_audio: Array[String] = []
	var failed_audio: Array[String] = []
	for raw_field in required_fields:
		var field_id := str(raw_field).strip_edges()
		if field_id.is_empty():
			continue
		var text := str(text_bundle.get(field_id, "")).strip_edges()
		if text.is_empty():
			missing_text.append(field_id)
			missing_audio.append(field_id)
			continue
		var clean_voice := voice_profile_id.strip_edges()
		if clean_voice.is_empty():
			continue
		var tts_key := "%s|%s" % [field_id, clean_voice]
		var tts: Dictionary = tts_ready.get(tts_key, {}) \
			if tts_ready.get(tts_key, {}) is Dictionary else {}
		if tts.is_empty():
			missing_audio.append(field_id)
			continue
		if str(tts.get("text_fingerprint", "")) != text_fingerprint(text):
			missing_audio.append(field_id)
			continue
		match str(tts.get("status", "")):
			"ready":
				pass
			"failed":
				failed_audio.append(field_id)
			_:
				missing_audio.append(field_id)
	return {
		"text_ready": missing_text.is_empty(),
		"audio_ready": missing_audio.is_empty() and failed_audio.is_empty(),
		"missing_text_fields": missing_text,
		"missing_audio_fields": missing_audio,
		"failed_audio_fields": failed_audio,
	}


func invalidate_by_subject(subject_id: String) -> Dictionary:
	if not is_valid():
		return _failure("Narrative cache store is invalid.")
	var clean_subject := subject_id.strip_edges()
	var next_data := data.duplicate(true)
	var next_entries: Dictionary = entries()
	var removed: Array[String] = []
	for cache_key in next_entries.keys():
		var entry: Variant = next_entries[cache_key]
		if entry is Dictionary \
				and str((entry as Dictionary).get("subject_id", "")) == clean_subject:
			removed.append(str(cache_key))
	for cache_key in removed:
		next_entries.erase(cache_key)
	next_data["entries"] = next_entries
	var committed := _commit(next_data, "narrative_cache_invalidate_subject")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "removed": removed}


func invalidate_unconsumed_stale_offers(criteria: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Narrative cache store is invalid.")
	var next_data := data.duplicate(true)
	var next_entries: Dictionary = entries()
	var removed: Array[String] = []
	for cache_key in next_entries.keys():
		var raw: Variant = next_entries[cache_key]
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if bool(entry.get("consumed", false)):
			continue
		if bool(entry.get("truth_frozen", false)) \
				or str(entry.get("status", "")) == "accepted":
			continue
		if _entry_matches_any_stale_criterion(entry, criteria):
			removed.append(str(cache_key))
	for cache_key in removed:
		next_entries.erase(cache_key)
	next_data["entries"] = next_entries
	var committed := _commit(next_data, "narrative_cache_invalidate_stale")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "removed": removed}


func discard_entries_outside_context(restored_context: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Narrative cache store is invalid.")
	var next_data := data.duplicate(true)
	var next_entries: Dictionary = entries()
	var removed: Array[String] = []
	for cache_key in next_entries.keys():
		var raw: Variant = next_entries[cache_key]
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if bool(entry.get("truth_frozen", false)) \
				or str(entry.get("status", "")) == "accepted":
			continue
		if _entry_context_mismatches(entry, restored_context):
			removed.append(str(cache_key))
	for cache_key in removed:
		next_entries.erase(cache_key)
	next_data["entries"] = next_entries
	var committed := _commit(next_data, "narrative_cache_discard_context")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "removed": removed}


func enforce_limits(
	max_entries: int = DEFAULT_MAX_ENTRIES,
	max_json_bytes: int = DEFAULT_MAX_JSON_BYTES
) -> Dictionary:
	if not is_valid():
		return _failure("Narrative cache store is invalid.")
	var next_data := data.duplicate(true)
	var next_entries: Dictionary = entries()
	var removed: Array[String] = []
	while _limits_exceeded(next_entries, max_entries, max_json_bytes):
		var eviction_key := _next_eviction_key(next_entries)
		if eviction_key.is_empty():
			break
		var raw: Variant = next_entries.get(eviction_key, {})
		if raw is Dictionary:
			_merge_text_fingerprints(next_data, raw)
		next_entries.erase(eviction_key)
		removed.append(eviction_key)
	next_data["entries"] = next_entries
	var committed := _commit(next_data, "narrative_cache_enforce_limits")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {
		"ok": true,
		"removed": removed,
		"entry_count": next_entries.size(),
		"json_bytes": _json_size(next_data),
		"within_limits": not _limits_exceeded(
			next_entries,
			max_entries,
			max_json_bytes
		),
	}


func clear_cache(reason: String = "narrative_cache_clear") -> Dictionary:
	if not is_valid():
		return _failure("Narrative cache store is invalid.")
	var next_data := data.duplicate(true)
	next_data["entries"] = {}
	next_data["text_fingerprints"] = {}
	var committed := _commit(next_data, reason)
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true}


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
		"text_fingerprints": {},
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


static func _entry_matches_any_stale_criterion(
	entry: Dictionary,
	criteria: Dictionary
) -> bool:
	for key in [
		"story_beat_id",
		"giver_npc_id",
		"destination_id",
		"objective_fingerprint",
		"allowed_facts_fingerprint",
		"relationship_tier",
	]:
		if not criteria.has(key):
			continue
		var expected := str(criteria.get(key, "")).strip_edges()
		if expected.is_empty():
			continue
		if str(entry.get(key, "")).strip_edges() == expected:
			return true
	return false


static func _entry_context_mismatches(
	entry: Dictionary,
	restored_context: Dictionary
) -> bool:
	for key in [
		"timeline_id",
		"context_revision",
		"story_revision",
		"knowledge_revision",
		"relationship_revision",
	]:
		if not restored_context.has(key):
			continue
		var expected: Variant = restored_context.get(key)
		if expected == null:
			continue
		if expected is String and str(expected).strip_edges().is_empty():
			continue
		if key.ends_with("_revision"):
			if int(entry.get(key, -1)) != int(expected):
				return true
		elif str(entry.get(key, "")).strip_edges() != str(expected).strip_edges():
			return true
	return false


static func text_fingerprint(text: String) -> String:
	return text.strip_edges().sha256_text()


static func _merge_text_fingerprints(next_data: Dictionary, entry: Dictionary) -> void:
	var fingerprints: Dictionary = next_data.get("text_fingerprints", {})
	var extracted := _extract_text_fingerprints(entry.get("text_bundle", {}))
	var now := int(Time.get_unix_time_from_system())
	for fingerprint in extracted.keys():
		fingerprints[fingerprint] = {
			"fingerprint": fingerprint,
			"kind": str(entry.get("kind", "")),
			"subject_id": str(entry.get("subject_id", "")),
			"speaker_id": str(entry.get("speaker_id", "")),
			"last_seen_at_unix": now,
		}
	next_data["text_fingerprints"] = fingerprints


static func _extract_text_fingerprints(value: Variant) -> Dictionary:
	var result := {}
	if value is String:
		var text := (value as String).strip_edges()
		if not text.is_empty():
			result[text_fingerprint(text)] = true
	elif value is Dictionary:
		for item in (value as Dictionary).values():
			result.merge(_extract_text_fingerprints(item))
	elif value is Array:
		for item in (value as Array):
			result.merge(_extract_text_fingerprints(item))
	return result


static func _limits_exceeded(
	next_entries: Dictionary,
	max_entries: int,
	max_json_bytes: int
) -> bool:
	if max_entries > 0 and next_entries.size() > max_entries:
		return true
	if max_json_bytes > 0:
		var probe := {
			"schema_version": DOCUMENT_VERSION,
			"document_type": "narrative_cache",
			"ownership": "disposable",
			"campaign_id": "",
			"entries": next_entries,
		}
		return _json_size(probe) > max_json_bytes
	return false


static func _next_eviction_key(next_entries: Dictionary) -> String:
	var candidates: Array[Dictionary] = []
	for cache_key in next_entries.keys():
		var raw: Variant = next_entries[cache_key]
		if raw is Dictionary:
			var entry: Dictionary = raw
			candidates.append({
				"cache_key": str(cache_key),
				"rank": _eviction_rank(entry),
				"priority": int(entry.get("priority", 100)),
				"updated_at_unix": int(entry.get("updated_at_unix", 0)),
			})
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.get("rank", 0)) != int(right.get("rank", 0)):
			return int(left.get("rank", 0)) < int(right.get("rank", 0))
		if int(left.get("priority", 0)) != int(right.get("priority", 0)):
			return int(left.get("priority", 0)) > int(right.get("priority", 0))
		return int(left.get("updated_at_unix", 0)) < int(
			right.get("updated_at_unix", 0)
		)
	)
	return str(candidates[0].get("cache_key", ""))


static func _eviction_rank(entry: Dictionary) -> int:
	if bool(entry.get("consumed", false)):
		return 0
	var expires_at := int(entry.get("expires_at_unix", 0))
	if expires_at > 0 and expires_at <= int(Time.get_unix_time_from_system()):
		return 1
	if str(entry.get("status", "")) in ["stale_discarded", "canceled"]:
		return 2
	if bool(entry.get("truth_frozen", false)) \
			or str(entry.get("status", "")) == "accepted":
		return 9
	return 4


static func _json_size(value: Dictionary) -> int:
	return JSON.stringify(value).to_utf8_buffer().size()


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
	if value.has("text_fingerprints") \
			and not value.get("text_fingerprints", {}) is Dictionary:
		result.add_error(
			"invalid_narrative_cache_text_fingerprints",
			"Narrative cache text_fingerprints must be an object.",
			"text_fingerprints"
		)
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
