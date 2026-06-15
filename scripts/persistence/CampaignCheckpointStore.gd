class_name CampaignCheckpointStore
extends RefCounted

const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const SchemaType := preload(
	"res://scripts/persistence/CampaignSchemaCatalog.gd"
)
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const CHECKPOINT_INDEX_VERSION := 1
const TACTICAL_KEYS: Array[String] = [
	"position",
	"rotation",
	"velocity",
	"current_speed",
	"target_position",
	"nav_mode",
	"is_docked",
	"projectiles",
	"aggro",
	"attack_target",
	"attack_targets",
	"autopilot_waypoint",
	"autopilot_waypoints",
	"jump_transition",
	"death_screen",
	"speech_request",
	"model_request",
	"transient_spawn_timer",
]

var campaign_path: String
var campaign: Dictionary = {}
var index: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> CampaignCheckpointStore:
	var store := CampaignCheckpointStore.new()
	store.campaign_path = path.trim_suffix("/")
	store._load()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func capture_autosave(
	runtime_state: Dictionary,
	safe_location: Dictionary,
	source_reason: String
) -> Dictionary:
	if not is_valid():
		return _failure("Campaign checkpoint store is invalid.")
	if source_reason not in ["dock", "undock", "gate_arrival"]:
		return _failure("Unsupported safe checkpoint reason.")
	if not _safe_location_matches_reason(safe_location, source_reason):
		return _failure("Safe location does not match the checkpoint reason.")
	if runtime_state.is_empty():
		return _failure("Checkpoint gameplay state cannot be empty.")
	if bool(runtime_state.get("dead", false)):
		return _failure("A dead player cannot create a safe checkpoint.")

	var safe_state := sanitize_runtime_state(runtime_state)
	var checkpoint_id := _new_id("checkpoint", source_reason)
	var map_id := _new_id("map_knowledge", source_reason)
	var previous := load_active_bundle()
	var previous_checkpoint: Dictionary = previous.get("checkpoint", {})
	var previous_map: Dictionary = previous.get("map_knowledge", {})
	var checkpoint := {
		"document_type": SchemaType.CHECKPOINT,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.REWINDABLE,
		"id": checkpoint_id,
		"campaign_id": campaign["id"],
		"timeline_id": campaign["current_timeline_id"],
		"chronicle_head_event_id":
			previous_checkpoint.get("chronicle_head_event_id", ""),
		"source_reason": source_reason,
		"living": true,
		"transitional": false,
		"safe_location": safe_location.duplicate(true),
		"state": safe_state,
	}
	var map_knowledge := _next_map_knowledge(
		previous_map,
		map_id,
		checkpoint_id
	)
	var bundle_validation := _validate_checkpoint_pair(
		checkpoint,
		map_knowledge
	)
	if not bundle_validation.is_valid():
		return _failure(
			"Safe checkpoint bundle failed validation.",
			bundle_validation
		)

	var bundle_path := "checkpoints/autosave/%s" % checkpoint_id
	var next_index: Dictionary = index.duplicate(true)
	next_index["schema_version"] = CHECKPOINT_INDEX_VERSION
	next_index["campaign_id"] = campaign["id"]
	next_index["active_checkpoint_id"] = checkpoint_id
	next_index["autosave"] = {
		"checkpoint_id": checkpoint_id,
		"path": bundle_path,
		"source_reason": source_reason,
		"checkpoint_hash": _stable_hash(checkpoint),
		"map_knowledge_hash": _stable_hash(map_knowledge),
	}
	if not next_index.has("manual"):
		next_index["manual"] = [null, null, null]
	var committed := TransactionStoreType.commit_json_set(
		campaign_path,
		"autosave",
		{
			"%s/checkpoint.json" % bundle_path: checkpoint,
			"%s/map_knowledge.json" % bundle_path: map_knowledge,
			"checkpoint_index.json": next_index,
		},
		"checkpoint_index.json",
		_validate_transaction_file
	)
	if not bool(committed.get("ok", false)):
		return committed
	index = next_index
	return {
		"ok": true,
		"checkpoint_id": checkpoint_id,
		"source_reason": source_reason,
		"safe_location": safe_location.duplicate(true),
	}


func load_active_bundle() -> Dictionary:
	if not is_valid():
		return _failure("Campaign checkpoint store is invalid.")
	var loaded := _read_bundle_for_index(index)
	if bool(loaded.get("ok", false)):
		return loaded
	var restored := TransactionStoreType.restore_last_known_good_index(
		campaign_path,
		"checkpoint_index.json",
		_validate_checkpoint_index
	)
	if not bool(restored.get("ok", false)):
		return loaded
	var prior_index: Dictionary = restored["data"]
	var prior_bundle := _read_bundle_for_index(prior_index)
	if not bool(prior_bundle.get("ok", false)):
		return loaded
	index = prior_index
	prior_bundle["recovered"] = true
	return prior_bundle


func _read_bundle_for_index(candidate_index: Dictionary) -> Dictionary:
	var autosave: Variant = candidate_index.get("autosave", null)
	if not autosave is Dictionary:
		return _failure("Campaign has no active safe autosave.")
	var bundle_path := str(autosave.get("path", ""))
	if bundle_path.is_empty():
		return _failure("Active autosave path is missing.")
	var checkpoint_result := DomainJsonType.read_object(
		"%s/%s/checkpoint.json" % [campaign_path, bundle_path]
	)
	var map_result := DomainJsonType.read_object(
		"%s/%s/map_knowledge.json" % [campaign_path, bundle_path]
	)
	var result := ValidationResultType.new()
	result.merge(checkpoint_result["validation"], "checkpoint")
	result.merge(map_result["validation"], "map_knowledge")
	if not result.is_valid():
		return _failure("Safe checkpoint files could not be read.", result)
	var checkpoint: Dictionary = checkpoint_result["data"]
	var map_knowledge: Dictionary = map_result["data"]
	result.merge(_validate_checkpoint_pair(checkpoint, map_knowledge))
	if str(checkpoint.get("id", "")) \
			!= str(candidate_index.get("active_checkpoint_id", "")):
		result.add_error(
			"checkpoint_index_mismatch",
			"Checkpoint index references a different active checkpoint.",
			"active_checkpoint_id"
		)
	var expected_checkpoint_hash := str(
		autosave.get("checkpoint_hash", "")
	)
	var expected_map_hash := str(autosave.get("map_knowledge_hash", ""))
	if not expected_checkpoint_hash.is_empty() \
			and _stable_hash(checkpoint) != expected_checkpoint_hash:
		result.add_error(
			"checkpoint_hash_mismatch",
			"Checkpoint payload does not match its index.",
			"autosave.checkpoint_hash"
		)
	if not expected_map_hash.is_empty() \
			and _stable_hash(map_knowledge) != expected_map_hash:
		result.add_error(
			"map_hash_mismatch",
			"Map knowledge does not match its index.",
			"autosave.map_knowledge_hash"
		)
	if not result.is_valid():
		return _failure("Safe checkpoint bundle failed validation.", result)
	return {
		"ok": true,
		"checkpoint": checkpoint,
		"map_knowledge": map_knowledge,
	}


func runtime_state_from_active() -> Dictionary:
	var bundle := load_active_bundle()
	if not bool(bundle.get("ok", false)):
		return bundle
	var checkpoint: Dictionary = bundle["checkpoint"]
	return {
		"ok": true,
		"state": (checkpoint.get("state", {}) as Dictionary).duplicate(true),
		"safe_location":
			(checkpoint.get("safe_location", {}) as Dictionary).duplicate(true),
		"source_reason": checkpoint.get("source_reason", ""),
		"checkpoint_id": checkpoint.get("id", ""),
	}


static func sanitize_runtime_state(runtime_state: Dictionary) -> Dictionary:
	var safe_state := runtime_state.duplicate(true)
	safe_state.erase("version")
	safe_state.erase("current_system_id")
	safe_state.erase("arrival_gate_id")
	_strip_tactical_state(safe_state)
	return safe_state


func _load() -> void:
	var campaign_result := DomainJsonType.read_object(
		"%s/campaign.json" % campaign_path
	)
	validation.merge(campaign_result["validation"], "campaign")
	if validation.is_valid():
		campaign = campaign_result["data"]
		validation.merge(
			SchemaType.validate_document(campaign),
			"campaign"
		)
	if not validation.is_valid():
		return
	var recovered := TransactionStoreType.recover_index(
		campaign_path,
		"checkpoint_index.json",
		_validate_checkpoint_index
	)
	if not bool(recovered.get("ok", false)):
		validation.add_error(
			"checkpoint_index_unavailable",
			recovered.get("error", "Checkpoint index is unavailable.")
		)
		return
	index = recovered["data"]
	if str(index.get("campaign_id", "")) != str(campaign.get("id", "")):
		validation.add_error(
			"checkpoint_campaign_mismatch",
			"Checkpoint index belongs to a different campaign.",
			"campaign_id"
		)


func _next_map_knowledge(
	previous: Dictionary,
	map_id: String,
	checkpoint_id: String
) -> Dictionary:
	var output := {
		"document_type": SchemaType.MAP_KNOWLEDGE,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.REWINDABLE,
		"id": map_id,
		"campaign_id": campaign["id"],
		"checkpoint_id": checkpoint_id,
	}
	for key in [
		"known_gate_ids",
		"rumored_gate_ids",
		"hidden_gate_ids",
		"blocked_gate_ids",
		"damaged_gate_ids",
	]:
		output[key] = previous.get(key, []).duplicate(true)
	return output


func _safe_location_matches_reason(
	location: Dictionary,
	source_reason: String
) -> bool:
	var expected_type := (
		"gate_arrival"
		if source_reason == "gate_arrival"
		else "docked"
	)
	return str(location.get("type", "")) == expected_type \
		and DomainIdType.is_valid(location.get("system_id", ""), "system") \
		and (
			DomainIdType.is_valid(location.get("gate_id", ""), "gate")
			if expected_type == "gate_arrival"
			else DomainIdType.is_valid(
				location.get("station_id", ""),
				"station"
			)
		)


func _validate_transaction_file(
	path: String,
	data: Dictionary
) -> ValidationResult:
	if path.get_file() == "checkpoint_index.json":
		return _validate_checkpoint_index(path, data)
	return SchemaType.validate_document(data)


static func _validate_checkpoint_index(
	_path: String,
	data: Dictionary
) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(data.get("schema_version", -1)) != CHECKPOINT_INDEX_VERSION:
		result.add_error(
			"invalid_checkpoint_index",
			"Checkpoint index version must be 1.",
			"schema_version"
		)
	if not DomainIdType.is_valid(data.get("campaign_id", ""), "campaign"):
		result.add_error(
			"invalid_checkpoint_index",
			"Checkpoint index requires a campaign ID.",
			"campaign_id"
		)
	if not DomainIdType.is_valid(
		data.get("active_checkpoint_id", ""),
		"checkpoint"
	):
		result.add_error(
			"invalid_checkpoint_index",
			"Checkpoint index requires an active checkpoint ID.",
			"active_checkpoint_id"
		)
	var autosave: Variant = data.get("autosave", null)
	if not autosave is Dictionary:
		result.add_error(
			"invalid_checkpoint_index",
			"Checkpoint index requires autosave metadata.",
			"autosave"
		)
	else:
		if str(autosave.get("checkpoint_id", "")) \
				!= str(data.get("active_checkpoint_id", "")):
			result.add_error(
				"invalid_checkpoint_index",
				"Autosave checkpoint must be the active checkpoint.",
				"autosave.checkpoint_id"
			)
		if str(autosave.get("path", "")).is_empty():
			result.add_error(
				"invalid_checkpoint_index",
				"Autosave path is required.",
				"autosave.path"
			)
	var manual: Variant = data.get("manual", null)
	if not manual is Array or manual.size() != 3:
		result.add_error(
			"invalid_checkpoint_index",
			"Checkpoint index requires exactly three manual entries.",
			"manual"
		)
	return result


static func _validate_checkpoint_pair(
	checkpoint: Dictionary,
	map_knowledge: Dictionary
) -> ValidationResult:
	var result := ValidationResultType.new()
	result.merge(
		SchemaType.validate_document(checkpoint),
		"checkpoint"
	)
	result.merge(
		SchemaType.validate_document(map_knowledge),
		"map_knowledge"
	)
	if str(checkpoint.get("campaign_id", "")) \
			!= str(map_knowledge.get("campaign_id", "")):
		result.add_error(
			"campaign_reference_mismatch",
			"Checkpoint and map knowledge belong to different campaigns.",
			"map_knowledge.campaign_id"
		)
	if str(checkpoint.get("id", "")) \
			!= str(map_knowledge.get("checkpoint_id", "")):
		result.add_error(
			"checkpoint_reference_mismatch",
			"Map knowledge references a different checkpoint.",
			"map_knowledge.checkpoint_id"
		)
	return result


static func _strip_tactical_state(value: Variant) -> void:
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			if str(key) in TACTICAL_KEYS:
				(value as Dictionary).erase(key)
			else:
				_strip_tactical_state((value as Dictionary)[key])
	elif value is Array:
		for item in value:
			_strip_tactical_state(item)


static func _new_id(id_namespace: String, label: String) -> String:
	var entropy := "%s|%s|%s" % [
		Time.get_ticks_usec(),
		Crypto.new().generate_random_bytes(12).hex_encode(),
		label,
	]
	return "%s.local.%s" % [
		id_namespace,
		entropy.sha256_text().substr(0, 24),
	]


static func _stable_hash(value: Variant) -> String:
	var normalized: Variant = JSON.parse_string(
		JSON.stringify(value, "", true)
	)
	return JSON.stringify(normalized, "", true).sha256_text()


static func _failure(
	message: String,
	result: ValidationResult = null
) -> Dictionary:
	var output := {"ok": false, "error": message}
	if result != null:
		output["validation"] = result.to_dict()
	return output
