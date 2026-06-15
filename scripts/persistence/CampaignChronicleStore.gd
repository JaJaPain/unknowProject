class_name CampaignChronicleStore
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

const INDEX_VERSION := 1

var campaign_path: String
var campaign: Dictionary = {}
var index: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> CampaignChronicleStore:
	var store := CampaignChronicleStore.new()
	store.campaign_path = path.trim_suffix("/")
	store._load()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func current_timeline_id() -> String:
	return str(index.get("current_timeline_id", ""))


func current_head_event_id() -> String:
	return str(index.get("current_head_event_id", ""))


func event_sequence(event_id: String) -> int:
	if not is_valid() or not DomainIdType.is_valid(event_id, "event"):
		return -1
	for metadata in index.get("segments", []):
		if not metadata is Dictionary:
			continue
		var parsed := DomainJsonType.read_object(
			"%s/%s" % [campaign_path, metadata.get("path", "")]
		)
		var parsed_validation := parsed["validation"] as ValidationResult
		if not parsed_validation.is_valid():
			return -1
		for event in parsed["data"].get("events", []):
			if event is Dictionary \
					and event.get("event_id", "") == event_id:
				return int(event.get("sequence", -1))
	return -1


func current_head_sequence() -> int:
	return event_sequence(current_head_event_id())


func append_event(
	event_type: String,
	subject_ids: Array,
	payload: Dictionary,
	checkpoint_id: String
) -> Dictionary:
	if not is_valid():
		return _failure("Campaign chronicle store is invalid.")
	if event_type.strip_edges().is_empty():
		return _failure("Chronicle event type cannot be empty.")
	if not DomainIdType.is_valid(checkpoint_id, "checkpoint"):
		return _failure("Chronicle event requires a checkpoint ID.")
	for subject_id in subject_ids:
		if not DomainIdType.is_valid(subject_id):
			return _failure("Chronicle event contains an invalid subject ID.")
	var sequence := int(index.get("next_sequence", 0))
	var timeline_id := str(index.get("current_timeline_id", ""))
	var event_id := _new_id("event", "%s_%d" % [event_type, sequence])
	var event := {
		"schema_version": SchemaType.SCHEMA_VERSION,
		"event_id": event_id,
		"timeline_id": timeline_id,
		"parent_event_id": str(index.get("current_head_event_id", "")),
		"checkpoint_id": checkpoint_id,
		"event_type": event_type.strip_edges(),
		"subject_ids": subject_ids.duplicate(true),
		"payload": payload.duplicate(true),
		"sequence": sequence,
	}
	var segment_id := _new_id("chronicle", "segment_%d" % sequence)
	var segment := {
		"document_type": SchemaType.CHRONICLE_SEGMENT,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.APPEND_ONLY,
		"id": segment_id,
		"campaign_id": campaign["id"],
		"timeline_id": timeline_id,
		"events": [event],
	}
	var segment_validation := SchemaType.validate_document(segment)
	if not segment_validation.is_valid():
		return _failure(
			"Chronicle event failed validation.",
			segment_validation
		)
	var segment_path := "chronicle/segments/%08d_%s.json" % [
		sequence,
		event_id.get_slice(".", 2),
	]
	var next_index: Dictionary = index.duplicate(true)
	var segments: Array = next_index.get("segments", []).duplicate(true)
	segments.append({
		"segment_id": segment_id,
		"path": segment_path,
		"timeline_id": timeline_id,
		"first_sequence": sequence,
		"last_sequence": sequence,
	})
	next_index["segments"] = segments
	next_index["current_head_event_id"] = event_id
	next_index["next_sequence"] = sequence + 1
	var committed := TransactionStoreType.commit_json_set(
		campaign_path,
		"chronicle_append",
		{
			segment_path: segment,
			"chronicle/index.json": next_index,
		},
		"chronicle/index.json",
		_validate_transaction_file
	)
	if not bool(committed.get("ok", false)):
		return committed
	index = next_index
	return {
		"ok": true,
		"event": event.duplicate(true),
		"segment_id": segment_id,
	}


func branch_from_checkpoint(checkpoint: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Campaign chronicle store is invalid.")
	var checkpoint_id := str(checkpoint.get("id", ""))
	var parent_timeline_id := str(checkpoint.get("timeline_id", ""))
	var branch_head_event_id := str(
		checkpoint.get("chronicle_head_event_id", "")
	)
	if not DomainIdType.is_valid(checkpoint_id, "checkpoint") \
			or not DomainIdType.is_valid(parent_timeline_id, "timeline"):
		return _failure("Loaded checkpoint cannot anchor a timeline branch.")
	if branch_head_event_id.is_empty() \
			or not DomainIdType.is_valid(branch_head_event_id, "event"):
		return _failure("Loaded checkpoint has no valid chronicle head.")
	var current_timeline_id := str(index.get("current_timeline_id", ""))
	var current_head_event_id := str(index.get("current_head_event_id", ""))
	if parent_timeline_id == current_timeline_id \
			and branch_head_event_id == current_head_event_id:
		return {
			"ok": true,
			"branched": false,
			"timeline_id": current_timeline_id,
			"head_event_id": current_head_event_id,
		}
	var timeline_id := _new_id("timeline", "branch")
	var next_index: Dictionary = index.duplicate(true)
	var timelines: Dictionary = next_index.get("timelines", {}).duplicate(true)
	timelines[timeline_id] = {
		"timeline_id": timeline_id,
		"parent_timeline_id": parent_timeline_id,
		"branch_checkpoint_id": checkpoint_id,
		"branch_head_event_id": branch_head_event_id,
		"created_sequence": int(index.get("next_sequence", 0)),
	}
	next_index["timelines"] = timelines
	next_index["current_timeline_id"] = timeline_id
	next_index["current_head_event_id"] = branch_head_event_id
	var next_campaign: Dictionary = campaign.duplicate(true)
	next_campaign["current_timeline_id"] = timeline_id
	var committed := TransactionStoreType.commit_json_set(
		campaign_path,
		"chronicle_branch",
		{
			"campaign.json": next_campaign,
			"chronicle/index.json": next_index,
		},
		"chronicle/index.json",
		_validate_transaction_file
	)
	if not bool(committed.get("ok", false)):
		return committed
	campaign = next_campaign
	index = next_index
	return {
		"ok": true,
		"branched": true,
		"timeline_id": timeline_id,
		"head_event_id": branch_head_event_id,
		"parent_timeline_id": parent_timeline_id,
	}


func current_branch_events() -> Dictionary:
	if not is_valid():
		return _failure("Campaign chronicle store is invalid.")
	var timeline_id := str(index.get("current_timeline_id", ""))
	var all_events: Array = []
	for metadata in index.get("segments", []):
		if not metadata is Dictionary:
			continue
		var parsed := DomainJsonType.read_object(
			"%s/%s" % [campaign_path, metadata.get("path", "")]
		)
		var parsed_validation := parsed["validation"] as ValidationResult
		if not parsed_validation.is_valid():
			return _failure(
				"Chronicle segment could not be read.",
				parsed_validation
			)
		for event in parsed["data"].get("events", []):
			all_events.append((event as Dictionary).duplicate(true))
	var event_by_id: Dictionary = {}
	for event in all_events:
		event_by_id[str(event.get("event_id", ""))] = event
	var timeline_limits := {timeline_id: 9223372036854775807}
	var cursor := timeline_id
	var timelines: Dictionary = index.get("timelines", {})
	while timelines.has(cursor):
		var metadata: Dictionary = timelines[cursor]
		var parent_timeline_id := str(
			metadata.get("parent_timeline_id", "")
		)
		if parent_timeline_id.is_empty():
			break
		var branch_head_event_id := str(
			metadata.get("branch_head_event_id", "")
		)
		var branch_head: Dictionary = event_by_id.get(
			branch_head_event_id,
			{}
		)
		if branch_head.is_empty():
			return _failure(
				"Timeline branch head is absent from the chronicle."
			)
		timeline_limits[parent_timeline_id] = int(
			branch_head.get("sequence", -1)
		)
		cursor = parent_timeline_id
	var events: Array = []
	for event in all_events:
		var event_timeline_id := str(event.get("timeline_id", ""))
		if timeline_limits.has(event_timeline_id) \
				and int(event.get("sequence", -1)) \
					<= int(timeline_limits[event_timeline_id]):
			events.append(event)
	events.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("sequence", 0)) \
				< int(right.get("sequence", 0))
	)
	return {
		"ok": true,
		"timeline_id": timeline_id,
		"events": events,
	}


func import_legacy_quest_history(
	history_text: String,
	checkpoint_id: String
) -> Dictionary:
	if bool(index.get("legacy_quest_history_imported", false)):
		return {"ok": true, "imported": 0, "already_imported": true}
	var imported := 0
	for raw_line in history_text.split("\n"):
		var line := str(raw_line).strip_edges()
		if not line.begins_with("- **"):
			continue
		var event_result := append_event(
			"legacy_quest_history",
			[campaign["id"]],
			{"legacy_markdown": line},
			checkpoint_id
		)
		if not bool(event_result.get("ok", false)):
			return event_result
		imported += 1
	var next_index: Dictionary = index.duplicate(true)
	next_index["legacy_quest_history_imported"] = true
	next_index["legacy_quest_history_hash"] = history_text.sha256_text()
	var committed := TransactionStoreType.commit_json_set(
		campaign_path,
		"chronicle_legacy_import",
		{"chronicle/index.json": next_index},
		"chronicle/index.json",
		_validate_transaction_file
	)
	if not bool(committed.get("ok", false)):
		return committed
	index = next_index
	return {"ok": true, "imported": imported, "already_imported": false}


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
	if not FileAccess.file_exists("%s/chronicle/index.json" % campaign_path):
		var bootstrapped := _bootstrap_index()
		if not bool(bootstrapped.get("ok", false)):
			validation.add_error(
				"chronicle_index_unavailable",
				bootstrapped.get("error", "Chronicle index is unavailable.")
			)
			return
	var recovered := TransactionStoreType.recover_index(
		campaign_path,
		"chronicle/index.json",
		_validate_chronicle_index
	)
	if not bool(recovered.get("ok", false)):
		validation.add_error(
			"chronicle_index_unavailable",
			recovered.get("error", "Chronicle index is unavailable.")
		)
		return
	index = recovered["data"]


func _bootstrap_index() -> Dictionary:
	var segment_path := "chronicle/segments/segment_000001.json"
	var parsed := DomainJsonType.read_object(
		"%s/%s" % [campaign_path, segment_path]
	)
	var parsed_validation := parsed["validation"] as ValidationResult
	if not parsed_validation.is_valid():
		return _failure(
			"Initial chronicle segment could not be read.",
			parsed_validation
		)
	var segment: Dictionary = parsed["data"]
	var segment_validation := SchemaType.validate_document(segment)
	if not segment_validation.is_valid():
		return _failure(
			"Initial chronicle segment failed validation.",
			segment_validation
		)
	var events: Array = segment.get("events", [])
	var head_event_id := ""
	var next_sequence := 0
	if not events.is_empty():
		var last_event: Dictionary = events[-1]
		head_event_id = str(last_event.get("event_id", ""))
		next_sequence = int(last_event.get("sequence", 0)) + 1
	var timeline_id := str(segment.get("timeline_id", ""))
	var initial_index := {
		"schema_version": INDEX_VERSION,
		"campaign_id": campaign["id"],
		"current_timeline_id": timeline_id,
		"current_head_event_id": head_event_id,
		"next_sequence": next_sequence,
		"legacy_quest_history_imported": false,
		"legacy_quest_history_hash": "",
		"timelines": {
			timeline_id: {
				"timeline_id": timeline_id,
				"parent_timeline_id": "",
				"branch_checkpoint_id": "",
				"branch_head_event_id": head_event_id,
				"created_sequence": 0,
			},
		},
		"segments": [{
			"segment_id": segment["id"],
			"path": segment_path,
			"timeline_id": timeline_id,
			"first_sequence": 0,
			"last_sequence": max(0, next_sequence - 1),
		}],
	}
	return TransactionStoreType.commit_json_set(
		campaign_path,
		"chronicle_bootstrap",
		{"chronicle/index.json": initial_index},
		"chronicle/index.json",
		_validate_transaction_file
	)


func _validate_transaction_file(
	path: String,
	data: Dictionary
) -> ValidationResult:
	if path == "chronicle/index.json" or path.get_file() == "index.json":
		return _validate_chronicle_index(path, data)
	return SchemaType.validate_document(data)


static func _validate_chronicle_index(
	_path: String,
	data: Dictionary
) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(data.get("schema_version", -1)) != INDEX_VERSION:
		result.add_error(
			"invalid_chronicle_index",
			"Chronicle index version must be 1.",
			"schema_version"
		)
	if not DomainIdType.is_valid(data.get("campaign_id", ""), "campaign"):
		result.add_error(
			"invalid_chronicle_index",
			"Chronicle index requires a campaign ID.",
			"campaign_id"
		)
	if not DomainIdType.is_valid(
		data.get("current_timeline_id", ""),
		"timeline"
	):
		result.add_error(
			"invalid_chronicle_index",
			"Chronicle index requires a current timeline ID.",
			"current_timeline_id"
		)
	if not DomainIdType.is_valid(
		data.get("current_head_event_id", ""),
		"event"
	):
		result.add_error(
			"invalid_chronicle_index",
			"Chronicle index requires a current head event ID.",
			"current_head_event_id"
		)
	var next_sequence: Variant = data.get("next_sequence", null)
	var sequence_is_number := next_sequence is int or next_sequence is float
	if not sequence_is_number \
			or float(next_sequence) != floor(float(next_sequence)) \
			or int(next_sequence) < 0:
		result.add_error(
			"invalid_chronicle_index",
			"Chronicle next sequence must be non-negative.",
			"next_sequence"
		)
	if not data.get("timelines", null) is Dictionary:
		result.add_error(
			"invalid_chronicle_index",
			"Chronicle timelines must be an object.",
			"timelines"
		)
	if not data.get("segments", null) is Array:
		result.add_error(
			"invalid_chronicle_index",
			"Chronicle segments must be an array.",
			"segments"
		)
	return result


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


static func _failure(
	message: String,
	result: ValidationResult = null
) -> Dictionary:
	var output := {"ok": false, "error": message}
	if result != null:
		output["validation"] = result.to_dict()
	return output
