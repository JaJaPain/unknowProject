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
const MANUAL_SLOT_COUNT := 3
const MAX_MANUAL_NAME_LENGTH := 48
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
var chronicle_timeline_id: String = ""
var chronicle_head_event_id: String = ""
var map_knowledge: Dictionary = {}


static func open(path: String) -> CampaignCheckpointStore:
	var store := CampaignCheckpointStore.new()
	store.campaign_path = path.trim_suffix("/")
	store._load()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func set_chronicle_context(
	timeline_id: String,
	head_event_id: String
) -> bool:
	if not DomainIdType.is_valid(timeline_id, "timeline") \
			or not DomainIdType.is_valid(head_event_id, "event"):
		return false
	chronicle_timeline_id = timeline_id
	chronicle_head_event_id = head_event_id
	return true


func current_map_knowledge() -> Dictionary:
	return map_knowledge.duplicate(true)


func restore_map_knowledge(restored: Dictionary) -> bool:
	var result := SchemaType.validate_document(restored)
	if not result.is_valid() \
			or str(restored.get("campaign_id", "")) \
				!= str(campaign.get("id", "")):
		return false
	map_knowledge = restored.duplicate(true)
	return true


func set_gate_knowledge(gate_id: String, state: String) -> bool:
	if not DomainIdType.is_valid(gate_id, "gate") \
			or state not in [
				"known",
				"rumored",
				"hidden",
				"blocked",
				"damaged",
			]:
		return false
	if map_knowledge.is_empty():
		return false
	var target_key := "%s_gate_ids" % state
	for key in [
		"known_gate_ids",
		"rumored_gate_ids",
		"hidden_gate_ids",
		"blocked_gate_ids",
		"damaged_gate_ids",
	]:
		var gate_ids: Array = map_knowledge.get(key, []).duplicate(true)
		gate_ids.erase(gate_id)
		if key == target_key:
			gate_ids.append(gate_id)
			gate_ids.sort()
		map_knowledge[key] = gate_ids
	return true


func mark_gates_known(gate_ids: Array) -> bool:
	for gate_id in gate_ids:
		if not set_gate_knowledge(str(gate_id), "known"):
			return false
	return true


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
	var previous_map: Dictionary = (
		map_knowledge
		if not map_knowledge.is_empty()
		else previous.get("map_knowledge", {})
	)
	var checkpoint := {
		"document_type": SchemaType.CHECKPOINT,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.REWINDABLE,
		"id": checkpoint_id,
		"campaign_id": campaign["id"],
		"timeline_id": (
			chronicle_timeline_id
			if not chronicle_timeline_id.is_empty()
			else campaign["current_timeline_id"]
		),
		"chronicle_head_event_id":
			chronicle_head_event_id
			if not chronicle_head_event_id.is_empty()
			else previous_checkpoint.get("chronicle_head_event_id", ""),
		"source_reason": source_reason,
		"living": true,
		"transitional": false,
		"safe_location": safe_location.duplicate(true),
		"state": safe_state,
	}
	var next_map_knowledge := _next_map_knowledge(
		previous_map,
		map_id,
		checkpoint_id
	)
	var bundle_validation := _validate_checkpoint_pair(
		checkpoint,
		next_map_knowledge
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
		"map_knowledge_hash": _stable_hash(next_map_knowledge),
	}
	if not next_index.has("manual"):
		next_index["manual"] = [null, null, null]
	var committed := TransactionStoreType.commit_json_set(
		campaign_path,
		"autosave",
		{
			"%s/checkpoint.json" % bundle_path: checkpoint,
			"%s/map_knowledge.json" % bundle_path: next_map_knowledge,
			"checkpoint_index.json": next_index,
		},
		"checkpoint_index.json",
		_validate_transaction_file
	)
	if not bool(committed.get("ok", false)):
		return committed
	index = next_index
	map_knowledge = next_map_knowledge.duplicate(true)
	return {
		"ok": true,
		"checkpoint_id": checkpoint_id,
		"source_reason": source_reason,
		"safe_location": safe_location.duplicate(true),
	}


func load_active_bundle() -> Dictionary:
	if not is_valid():
		return _failure("Campaign checkpoint store is invalid.")
	var loaded := _read_bundle(
		index.get("autosave", null),
		str(index.get("active_checkpoint_id", "")),
		"Safe checkpoint"
	)
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
	var prior_bundle := _read_bundle(
		prior_index.get("autosave", null),
		str(prior_index.get("active_checkpoint_id", "")),
		"Safe checkpoint"
	)
	if not bool(prior_bundle.get("ok", false)):
		return loaded
	index = prior_index
	prior_bundle["recovered"] = true
	return prior_bundle


func copy_active_to_manual(
	slot_index: int,
	display_name: String,
	overwrite: bool = false
) -> Dictionary:
	if not is_valid():
		return _failure("Campaign checkpoint store is invalid.")
	if slot_index < 0 or slot_index >= MANUAL_SLOT_COUNT:
		return _failure("Manual checkpoint slot must be between 1 and 3.")
	if TransactionStoreType.is_locked(campaign_path):
		return _failure("A campaign save transaction is already active.")
	var clean_name := sanitize_manual_name(display_name)
	if clean_name.is_empty():
		return _failure("Manual checkpoint name cannot be empty.")
	var manual: Array = index.get(
		"manual",
		[null, null, null]
	).duplicate(true)
	if manual[slot_index] != null and not overwrite:
		return {
			"ok": false,
			"requires_overwrite": true,
			"error": "Manual checkpoint slot %d is already occupied." %
				(slot_index + 1),
		}
	var source := load_active_bundle()
	if not bool(source.get("ok", false)):
		return _failure(
			"No valid safe checkpoint is available to copy."
		)
	var checkpoint: Dictionary = source["checkpoint"]
	var map_knowledge: Dictionary = source["map_knowledge"]
	var copy_token := _new_copy_token(slot_index)
	var bundle_path := "checkpoints/manual_%02d/%s" % [
		slot_index + 1,
		copy_token,
	]
	var entry := {
		"checkpoint_id": checkpoint["id"],
		"path": bundle_path,
		"display_name": clean_name,
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"source_reason": checkpoint.get("source_reason", ""),
		"checkpoint_hash": _stable_hash(checkpoint),
		"map_knowledge_hash": _stable_hash(map_knowledge),
	}
	manual[slot_index] = entry
	var next_index: Dictionary = index.duplicate(true)
	next_index["manual"] = manual
	var committed := TransactionStoreType.commit_json_set(
		campaign_path,
		"manual_copy",
		{
			"%s/checkpoint.json" % bundle_path:
				checkpoint.duplicate(true),
			"%s/map_knowledge.json" % bundle_path:
				map_knowledge.duplicate(true),
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
		"slot_index": slot_index,
		"display_name": clean_name,
		"checkpoint_id": checkpoint["id"],
		"safe_location":
			(checkpoint.get("safe_location", {}) as Dictionary).duplicate(true),
	}


func list_manual_checkpoints() -> Array:
	var output: Array = []
	var manual: Array = index.get(
		"manual",
		[null, null, null]
	)
	for slot_index in range(MANUAL_SLOT_COUNT):
		var entry: Variant = manual[slot_index]
		output.append({
			"slot_index": slot_index,
			"occupied": entry is Dictionary,
			"display_name":
				str(entry.get("display_name", ""))
				if entry is Dictionary
				else "",
			"created_at_unix":
				int(entry.get("created_at_unix", 0))
				if entry is Dictionary
				else 0,
			"checkpoint_id":
				str(entry.get("checkpoint_id", ""))
				if entry is Dictionary
				else "",
			"source_reason":
				str(entry.get("source_reason", ""))
				if entry is Dictionary
				else "",
		})
	return output


func load_manual_bundle(slot_index: int) -> Dictionary:
	if not is_valid():
		return _failure("Campaign checkpoint store is invalid.")
	if slot_index < 0 or slot_index >= MANUAL_SLOT_COUNT:
		return _failure("Manual checkpoint slot must be between 1 and 3.")
	var manual: Array = index.get(
		"manual",
		[null, null, null]
	)
	var entry: Variant = manual[slot_index]
	if not entry is Dictionary:
		return _failure(
			"Manual checkpoint slot %d is empty." % (slot_index + 1)
		)
	return _read_bundle(
		entry,
		str(entry.get("checkpoint_id", "")),
		"Manual checkpoint"
	)


func rename_manual_checkpoint(
	slot_index: int,
	display_name: String
) -> Dictionary:
	if not is_valid():
		return _failure("Campaign checkpoint store is invalid.")
	if slot_index < 0 or slot_index >= MANUAL_SLOT_COUNT:
		return _failure("Manual checkpoint slot must be between 1 and 3.")
	if TransactionStoreType.is_locked(campaign_path):
		return _failure("A campaign save transaction is already active.")
	var clean_name := sanitize_manual_name(display_name)
	if clean_name.is_empty():
		return _failure("Manual checkpoint name cannot be empty.")
	var manual: Array = index.get(
		"manual",
		[null, null, null]
	).duplicate(true)
	if not manual[slot_index] is Dictionary:
		return _failure(
			"Manual checkpoint slot %d is empty." % (slot_index + 1)
		)
	var entry: Dictionary = manual[slot_index].duplicate(true)
	entry["display_name"] = clean_name
	manual[slot_index] = entry
	var next_index: Dictionary = index.duplicate(true)
	next_index["manual"] = manual
	var committed := TransactionStoreType.commit_json_set(
		campaign_path,
		"manual_rename",
		{"checkpoint_index.json": next_index},
		"checkpoint_index.json",
		_validate_transaction_file
	)
	if not bool(committed.get("ok", false)):
		return committed
	index = next_index
	return {
		"ok": true,
		"slot_index": slot_index,
		"display_name": clean_name,
		"checkpoint_id": entry["checkpoint_id"],
	}


func runtime_state_from_manual(slot_index: int) -> Dictionary:
	var bundle := load_manual_bundle(slot_index)
	if not bool(bundle.get("ok", false)):
		return bundle
	return _runtime_state_from_bundle(bundle)


func has_active_safe_checkpoint() -> bool:
	return bool(load_active_bundle().get("ok", false))


func is_transaction_active() -> bool:
	return TransactionStoreType.is_locked(campaign_path)


func _read_bundle(
	entry: Variant,
	expected_checkpoint_id: String,
	label: String
) -> Dictionary:
	if not entry is Dictionary:
		return _failure("%s metadata is missing." % label)
	var bundle_path := str(entry.get("path", ""))
	if bundle_path.is_empty():
		return _failure("%s path is missing." % label)
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
		return _failure("%s files could not be read." % label, result)
	var checkpoint: Dictionary = checkpoint_result["data"]
	var map_knowledge: Dictionary = map_result["data"]
	result.merge(_validate_checkpoint_pair(checkpoint, map_knowledge))
	if str(checkpoint.get("id", "")) != expected_checkpoint_id:
		result.add_error(
			"checkpoint_index_mismatch",
			"%s metadata references a different checkpoint." % label,
			"checkpoint_id"
		)
	var expected_checkpoint_hash := str(
		entry.get("checkpoint_hash", "")
	)
	var expected_map_hash := str(entry.get("map_knowledge_hash", ""))
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
		return _failure("%s bundle failed validation." % label, result)
	return {
		"ok": true,
		"checkpoint": checkpoint,
		"map_knowledge": map_knowledge,
	}


func runtime_state_from_active() -> Dictionary:
	var bundle := load_active_bundle()
	if not bool(bundle.get("ok", false)):
		return bundle
	return _runtime_state_from_bundle(bundle)


func _runtime_state_from_bundle(bundle: Dictionary) -> Dictionary:
	var checkpoint: Dictionary = bundle["checkpoint"]
	return {
		"ok": true,
		"state": (checkpoint.get("state", {}) as Dictionary).duplicate(true),
		"safe_location":
			(checkpoint.get("safe_location", {}) as Dictionary).duplicate(true),
		"source_reason": checkpoint.get("source_reason", ""),
		"checkpoint_id": checkpoint.get("id", ""),
		"timeline_id": checkpoint.get("timeline_id", ""),
		"chronicle_head_event_id":
			checkpoint.get("chronicle_head_event_id", ""),
		"map_knowledge":
			(bundle.get("map_knowledge", {}) as Dictionary).duplicate(true),
	}


static func sanitize_manual_name(display_name: String) -> String:
	var output := ""
	var last_was_space := false
	for character in display_name.strip_edges():
		var code := character.unicode_at(0)
		if code < 32 or character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
			continue
		if character in [" ", "\t", "\n", "\r"]:
			if output.is_empty() or last_was_space:
				continue
			output += " "
			last_was_space = true
		else:
			output += character
			last_was_space = false
		if output.length() >= MAX_MANUAL_NAME_LENGTH:
			break
	return output.strip_edges()


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
	if validation.is_valid():
		chronicle_timeline_id = str(campaign.get("current_timeline_id", ""))
		var active := load_active_bundle()
		if bool(active.get("ok", false)):
			chronicle_head_event_id = str(
				active.get("checkpoint", {}).get(
					"chronicle_head_event_id",
					""
				)
			)
			map_knowledge = (
				active.get("map_knowledge", {}) as Dictionary
			).duplicate(true)


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
	if not manual is Array or manual.size() != MANUAL_SLOT_COUNT:
		result.add_error(
			"invalid_checkpoint_index",
			"Checkpoint index requires exactly three manual entries.",
			"manual"
		)
	else:
		for slot_index in range(MANUAL_SLOT_COUNT):
			var entry: Variant = manual[slot_index]
			if entry == null:
				continue
			if not entry is Dictionary:
				result.add_error(
					"invalid_manual_checkpoint",
					"Manual checkpoint metadata must be an object or null.",
					"manual.%d" % slot_index
				)
				continue
			if not DomainIdType.is_valid(
				entry.get("checkpoint_id", ""),
				"checkpoint"
			):
				result.add_error(
					"invalid_manual_checkpoint",
					"Manual checkpoint requires a checkpoint ID.",
					"manual.%d.checkpoint_id" % slot_index
				)
			if str(entry.get("path", "")).is_empty():
				result.add_error(
					"invalid_manual_checkpoint",
					"Manual checkpoint path is required.",
					"manual.%d.path" % slot_index
				)
			var display_name := str(entry.get("display_name", ""))
			if sanitize_manual_name(display_name).is_empty() \
					or sanitize_manual_name(display_name) != display_name:
				result.add_error(
					"invalid_manual_checkpoint",
					"Manual checkpoint display name must be sanitized.",
					"manual.%d.display_name" % slot_index
				)
			if int(entry.get("created_at_unix", 0)) <= 0:
				result.add_error(
					"invalid_manual_checkpoint",
					"Manual checkpoint creation time is required.",
					"manual.%d.created_at_unix" % slot_index
				)
			for hash_field in [
				"checkpoint_hash",
				"map_knowledge_hash",
			]:
				if str(entry.get(hash_field, "")).length() != 64:
					result.add_error(
						"invalid_manual_checkpoint",
						"Manual checkpoint hashes must be SHA-256 values.",
						"manual.%d.%s" % [slot_index, hash_field]
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


static func _new_copy_token(slot_index: int) -> String:
	var entropy := "%s|%s|%s" % [
		Time.get_ticks_usec(),
		Crypto.new().generate_random_bytes(8).hex_encode(),
		slot_index,
	]
	return "copy_%s" % entropy.sha256_text().substr(0, 20)


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
