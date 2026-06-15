class_name CampaignSchemaCatalog
extends RefCounted

const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const SCHEMA_VERSION := 1

const CAMPAIGN := "campaign"
const MANIFEST := "manifest"
const ASSET_REGISTRY := "asset_registry"
const CHECKPOINT := "checkpoint"
const MAP_KNOWLEDGE := "map_knowledge"
const CHRONICLE_SEGMENT := "chronicle_segment"
const KAELEN_META := "kaelen_meta"

const PERMANENT := "permanent"
const REWINDABLE := "rewindable"
const APPEND_ONLY := "append_only"
const META_MEMORY := "meta_memory"
const DISPOSABLE := "disposable"

const DOCUMENT_OWNERSHIP: Dictionary = {
	CAMPAIGN: PERMANENT,
	MANIFEST: PERMANENT,
	ASSET_REGISTRY: PERMANENT,
	CHECKPOINT: REWINDABLE,
	MAP_KNOWLEDGE: REWINDABLE,
	CHRONICLE_SEGMENT: APPEND_ONLY,
	KAELEN_META: META_MEMORY,
}

const OWNERSHIP_TABLE: Dictionary = {
	PERMANENT: [
		"campaign_identity",
		"campaign_seed",
		"generated_entity_identity",
		"canon_fact",
		"generated_asset_identity",
	],
	REWINDABLE: [
		"player_state",
		"mission_state",
		"reputation",
		"world_entity_state",
		"map_knowledge",
		"story_state",
	],
	APPEND_ONLY: [
		"chronicle_event",
		"timeline_branch",
	],
	META_MEMORY: [
		"timeline_reversal_count",
		"discarded_death_category",
		"approved_kaelen_memory",
	],
	DISPOSABLE: [
		"projectile",
		"aggro",
		"autopilot_waypoint",
		"transient_spawn_timer",
		"speech_request",
		"generation_temp_file",
	],
}

const _FORBIDDEN_CHECKPOINT_KEYS: Array[String] = [
	"projectiles",
	"aggro",
	"attack_target",
	"attack_targets",
	"autopilot_waypoint",
	"autopilot_waypoints",
	"position",
	"rotation",
	"velocity",
	"current_speed",
	"target_position",
	"nav_mode",
	"is_docked",
	"jump_transition",
	"death_screen",
	"speech_request",
	"model_request",
	"transient_spawn_timer",
]

const _FORBIDDEN_MANIFEST_KEYS: Array[String] = [
	"player_state",
	"mission_state",
	"reputation",
	"cargo",
	"credits",
	"hull",
	"map_knowledge",
]

const _FORBIDDEN_KAELEN_KEYS: Array[String] = [
	"credits",
	"reputation",
	"mission_progress",
	"mission_state",
	"cargo",
	"rewards",
	"future_outcome",
	"tactical_state",
]


static func validate_document(data: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	var document_type := str(data.get("document_type", ""))
	if not DOCUMENT_OWNERSHIP.has(document_type):
		return result.add_error(
			"unsupported_document_type",
			"document_type '%s' is not supported." % document_type,
			"document_type"
		)

	_validate_schema_header(data, document_type, result)
	match document_type:
		CAMPAIGN:
			_validate_campaign(data, result)
		MANIFEST:
			_validate_manifest(data, result)
		ASSET_REGISTRY:
			_validate_asset_registry(data, result)
		CHECKPOINT:
			_validate_checkpoint(data, result)
		MAP_KNOWLEDGE:
			_validate_map_knowledge(data, result)
		CHRONICLE_SEGMENT:
			_validate_chronicle(data, result)
		KAELEN_META:
			_validate_kaelen_meta(data, result)
	return result


static func validate_bundle(documents: Array) -> ValidationResult:
	var result := ValidationResultType.new()
	var by_type: Dictionary = {}
	var known_ids: Dictionary = {}
	var entity_ids: Dictionary = {}
	var fact_ids: Dictionary = {}
	var checkpoint_ids: Dictionary = {}
	var timeline_ids: Dictionary = {}
	var event_ids: Dictionary = {}

	for index in range(documents.size()):
		var raw: Variant = documents[index]
		if not raw is Dictionary:
			result.add_error(
				"invalid_document",
				"Bundle entry must be an object.",
				"documents.%d" % index
			)
			continue
		var document := raw as Dictionary
		var validation := validate_document(document)
		result.merge(validation, "documents.%d" % index)
		var document_type := str(document.get("document_type", ""))
		if not document_type.is_empty():
			if by_type.has(document_type):
				result.add_error(
					"duplicate_document_type",
					"Bundle contains more than one '%s' document." % document_type,
					"documents.%d.document_type" % index
				)
			else:
				by_type[document_type] = document
		var document_id := str(document.get("id", ""))
		if not document_id.is_empty():
			if known_ids.has(document_id):
				result.add_error(
					"duplicate_document_id",
					"Duplicate document ID '%s'." % document_id,
					"documents.%d.id" % index
				)
			known_ids[document_id] = true

	if by_type.has(MANIFEST):
		for entity_id in by_type[MANIFEST].get("entity_ids", []):
			entity_ids[str(entity_id)] = true
		for fact in by_type[MANIFEST].get("canon_facts", []):
			if fact is Dictionary:
				fact_ids[str(fact.get("fact_id", ""))] = true
	if by_type.has(CHECKPOINT):
		var checkpoint: Dictionary = by_type[CHECKPOINT]
		checkpoint_ids[str(checkpoint.get("id", ""))] = true
		timeline_ids[str(checkpoint.get("timeline_id", ""))] = true
	if by_type.has(CHRONICLE_SEGMENT):
		var chronicle: Dictionary = by_type[CHRONICLE_SEGMENT]
		timeline_ids[str(chronicle.get("timeline_id", ""))] = true
		for event in chronicle.get("events", []):
			if event is Dictionary:
				event_ids[str(event.get("event_id", ""))] = true

	_validate_campaign_links(by_type, timeline_ids, result)
	_validate_manifest_links(by_type, entity_ids, result)
	_validate_asset_links(by_type, entity_ids, result)
	_validate_checkpoint_links(
		by_type,
		entity_ids,
		checkpoint_ids,
		timeline_ids,
		event_ids,
		result
	)
	_validate_chronicle_links(
		by_type,
		entity_ids,
		checkpoint_ids,
		timeline_ids,
		result
	)
	_validate_kaelen_links(
		by_type,
		fact_ids,
		checkpoint_ids,
		timeline_ids,
		result
	)
	return result


static func ownership_for(document_type: String) -> String:
	return str(DOCUMENT_OWNERSHIP.get(document_type, ""))


static func ownership_table() -> Dictionary:
	return OWNERSHIP_TABLE.duplicate(true)


static func _validate_schema_header(
	data: Dictionary,
	document_type: String,
	result: ValidationResult
) -> void:
	var raw_version: Variant = data.get("schema_version", null)
	if raw_version == null:
		result.add_error(
			"missing_schema_version",
			"Document is missing schema_version.",
			"schema_version"
		)
	elif not _is_whole_number(raw_version):
		result.add_error(
			"invalid_schema_version",
			"schema_version must be a whole number.",
			"schema_version"
		)
	elif int(raw_version) != SCHEMA_VERSION:
		result.add_error(
			"unsupported_schema_version",
			"Schema version %d is unsupported; expected %d." % [
				int(raw_version),
				SCHEMA_VERSION,
			],
			"schema_version"
		)

	var expected_ownership := ownership_for(document_type)
	var actual_ownership := str(data.get("ownership", ""))
	if actual_ownership != expected_ownership:
		result.add_error(
			"wrong_ownership",
			"%s documents require '%s' ownership." % [
				document_type,
				expected_ownership,
			],
			"ownership"
		)


static func _validate_campaign(data: Dictionary, result: ValidationResult) -> void:
	_require_id(data, "id", "campaign", result)
	_require_same_id(data, "campaign_id", data.get("id", ""), result)
	_require_nonempty_string(data, "campaign_seed", result)
	_require_nonempty_string(data, "creation_version", result)
	_require_id(data, "manifest_id", "manifest", result)
	_require_id(data, "asset_registry_id", "asset_registry", result)
	_require_id(data, "kaelen_meta_id", "kaelen_meta", result)
	_require_id(data, "current_timeline_id", "timeline", result)


static func _validate_manifest(data: Dictionary, result: ValidationResult) -> void:
	_require_id(data, "id", "manifest", result)
	_require_id(data, "campaign_id", "campaign", result)
	_validate_id_array(data, "entity_ids", "", result)
	var raw_records: Variant = data.get("entity_records", [])
	if not raw_records is Array:
		result.add_error(
			"invalid_type",
			"entity_records must be an array.",
			"entity_records"
		)
	else:
		var seen_records: Dictionary = {}
		for index in range(raw_records.size()):
			var raw: Variant = raw_records[index]
			if not raw is Dictionary:
				result.add_error(
					"invalid_type",
					"Entity record must be an object.",
					"entity_records.%d" % index
				)
				continue
			var record := raw as Dictionary
			var prefix := "entity_records.%d." % index
			_require_id(record, "entity_id", "", result, prefix)
			_require_nonempty_string(record, "entity_type", result, prefix)
			_require_nonempty_string(record, "origin", result, prefix)
			_require_nonempty_string(record, "source_registry", result, prefix)
			_require_nonempty_string(record, "definition_hash", result, prefix)
			var entity_id := str(record.get("entity_id", ""))
			if not entity_id.is_empty() and seen_records.has(entity_id):
				result.add_error(
					"duplicate_entity_record",
					"Duplicate entity record '%s'." % entity_id,
					"%sentity_id" % prefix
				)
			seen_records[entity_id] = true
	_validate_object_array(data, "canon_facts", result)
	_reject_keys(data, _FORBIDDEN_MANIFEST_KEYS, result)
	for index in range(data.get("canon_facts", []).size()):
		var fact: Variant = data["canon_facts"][index]
		if fact is Dictionary:
			_require_id(
				fact as Dictionary,
				"fact_id",
				"fact",
				result,
				"canon_facts.%d." % index
			)
			_validate_id_array(
				fact as Dictionary,
				"subject_ids",
				"",
				result,
				"canon_facts.%d." % index
			)


static func _validate_asset_registry(
	data: Dictionary,
	result: ValidationResult
) -> void:
	_require_id(data, "id", "asset_registry", result)
	_require_id(data, "campaign_id", "campaign", result)
	_validate_object_array(data, "assets", result)
	var seen: Dictionary = {}
	for index in range(data.get("assets", []).size()):
		var raw: Variant = data["assets"][index]
		if not raw is Dictionary:
			continue
		var asset := raw as Dictionary
		var prefix := "assets.%d." % index
		_require_id(asset, "asset_id", "asset", result, prefix)
		_require_id(asset, "owner_entity_id", "", result, prefix)
		_require_nonempty_string(asset, "generator_type", result, prefix)
		_require_nonempty_string(asset, "generator_version", result, prefix)
		_require_nonempty_string(asset, "generation_seed", result, prefix)
		_require_nonempty_string(asset, "provenance_hash", result, prefix)
		_require_nonempty_string(asset, "source_path", result, prefix)
		_require_nonempty_string(asset, "rebuild_instruction", result, prefix)
		var status := str(asset.get("validation_status", ""))
		if status not in ["approved", "fallback", "missing", "rebuild_required"]:
			result.add_error(
				"invalid_validation_status",
				"Asset validation_status is unsupported.",
				"%svalidation_status" % prefix
			)
		var asset_id := str(asset.get("asset_id", ""))
		if not asset_id.is_empty() and seen.has(asset_id):
			result.add_error(
				"duplicate_asset_id",
				"Duplicate asset ID '%s'." % asset_id,
				"%sasset_id" % prefix
			)
		seen[asset_id] = true


static func _validate_checkpoint(data: Dictionary, result: ValidationResult) -> void:
	_require_id(data, "id", "checkpoint", result)
	_require_id(data, "campaign_id", "campaign", result)
	_require_id(data, "timeline_id", "timeline", result)
	_require_optional_id(data, "chronicle_head_event_id", "event", result)
	var source := str(data.get("source_reason", ""))
	if source not in [
		"initial",
		"dock",
		"undock",
		"gate_arrival",
		"manual_copy",
		"legacy_import",
	]:
		result.add_error(
			"invalid_source_reason",
			"Checkpoint source_reason is unsupported.",
			"source_reason"
		)
	if data.get("living", null) != true:
		result.add_error(
			"checkpoint_not_living",
			"A safe checkpoint must record a living player.",
			"living"
		)
	if data.get("transitional", null) != false:
		result.add_error(
			"checkpoint_transitional",
			"A safe checkpoint cannot be transitional.",
			"transitional"
		)
	var location: Variant = data.get("safe_location", null)
	if not location is Dictionary:
		result.add_error(
			"invalid_safe_location",
			"safe_location must be an object.",
			"safe_location"
		)
	else:
		_validate_safe_location(location as Dictionary, result)
	var state: Variant = data.get("state", null)
	if not state is Dictionary:
		result.add_error(
			"invalid_checkpoint_state",
			"state must be an object.",
			"state"
		)
	else:
		_reject_nested_keys(
			state as Dictionary,
			_FORBIDDEN_CHECKPOINT_KEYS,
			"state",
			result
		)


static func _validate_map_knowledge(
	data: Dictionary,
	result: ValidationResult
) -> void:
	_require_id(data, "id", "map_knowledge", result)
	_require_id(data, "campaign_id", "campaign", result)
	_require_id(data, "checkpoint_id", "checkpoint", result)
	var classified_gate_ids: Dictionary = {}
	for key in ["known_gate_ids", "rumored_gate_ids", "hidden_gate_ids",
			"blocked_gate_ids", "damaged_gate_ids"]:
		_validate_id_array(data, key, "gate", result)
		for gate_id in data.get(key, []):
			var canonical_gate_id := str(gate_id)
			if classified_gate_ids.has(canonical_gate_id):
				result.add_error(
					"duplicate_gate_knowledge_state",
					"Map gate '%s' appears in more than one knowledge state." %
						canonical_gate_id,
					key
				)
			classified_gate_ids[canonical_gate_id] = key


static func _validate_chronicle(data: Dictionary, result: ValidationResult) -> void:
	_require_id(data, "id", "chronicle", result)
	_require_id(data, "campaign_id", "campaign", result)
	_require_id(data, "timeline_id", "timeline", result)
	_validate_object_array(data, "events", result)
	var seen: Dictionary = {}
	var previous_sequence := -1
	for index in range(data.get("events", []).size()):
		var raw: Variant = data["events"][index]
		if not raw is Dictionary:
			continue
		var event := raw as Dictionary
		var prefix := "events.%d." % index
		var event_schema_version: Variant = event.get(
			"schema_version",
			null
		)
		if not _is_whole_number(event_schema_version) \
				or int(event_schema_version) != SCHEMA_VERSION:
			result.add_error(
				"invalid_event_schema_version",
				"Chronicle event schema version must be %d." %
					SCHEMA_VERSION,
				"%sschema_version" % prefix
			)
		_require_id(event, "event_id", "event", result, prefix)
		_require_id(event, "timeline_id", "timeline", result, prefix)
		_require_optional_id(event, "parent_event_id", "event", result, prefix)
		_require_id(event, "checkpoint_id", "checkpoint", result, prefix)
		_require_nonempty_string(event, "event_type", result, prefix)
		_validate_id_array(event, "subject_ids", "", result, prefix)
		if not event.get("payload", null) is Dictionary:
			result.add_error(
				"invalid_payload",
				"Chronicle event payload must be an object.",
				"%spayload" % prefix
			)
		var sequence: Variant = event.get("sequence", null)
		if not _is_whole_number(sequence) or int(sequence) < 0:
			result.add_error(
				"invalid_event_sequence",
				"Chronicle sequence must be a non-negative integer.",
				"%ssequence" % prefix
			)
		elif int(sequence) <= previous_sequence:
			result.add_error(
				"unordered_event_sequence",
				"Chronicle event sequences must increase.",
				"%ssequence" % prefix
			)
		else:
			previous_sequence = int(sequence)
		var event_id := str(event.get("event_id", ""))
		if not event_id.is_empty() and seen.has(event_id):
			result.add_error(
				"duplicate_event_id",
				"Duplicate event ID '%s'." % event_id,
				"%sevent_id" % prefix
			)
		seen[event_id] = true


static func _validate_kaelen_meta(data: Dictionary, result: ValidationResult) -> void:
	_require_id(data, "id", "kaelen_meta", result)
	_require_id(data, "campaign_id", "campaign", result)
	var reversal_count: Variant = data.get("timeline_reversal_count", null)
	if not _is_whole_number(reversal_count) or int(reversal_count) < 0:
		result.add_error(
			"invalid_reversal_count",
			"timeline_reversal_count must be a non-negative integer.",
			"timeline_reversal_count"
		)
	var next_sequence: Variant = data.get("next_memory_sequence", 0)
	if not _is_whole_number(next_sequence) or int(next_sequence) < 0:
		result.add_error(
			"invalid_memory_sequence",
			"next_memory_sequence must be a non-negative integer.",
			"next_memory_sequence"
		)
	_validate_object_array(data, "memories", result)
	_reject_nested_keys(data, _FORBIDDEN_KAELEN_KEYS, "", result)
	var seen: Dictionary = {}
	for index in range(data.get("memories", []).size()):
		var raw: Variant = data["memories"][index]
		if not raw is Dictionary:
			continue
		var memory := raw as Dictionary
		var prefix := "memories.%d." % index
		_require_id(memory, "memory_id", "memory", result, prefix)
		_require_id(memory, "source_timeline_id", "timeline", result, prefix)
		_require_id(memory, "source_checkpoint_id", "checkpoint", result, prefix)
		var sequence: Variant = memory.get("event_sequence", null)
		if not _is_whole_number(sequence) or int(sequence) < 0:
			result.add_error(
				"invalid_memory_sequence",
				"event_sequence must be a non-negative integer.",
				"%sevent_sequence" % prefix
			)
		var local_sequence: Variant = memory.get("local_sequence", 0)
		if not _is_whole_number(local_sequence) or int(local_sequence) < 0:
			result.add_error(
				"invalid_local_memory_sequence",
				"local_sequence must be a non-negative integer.",
				"%slocal_sequence" % prefix
			)
		_require_nonempty_string(memory, "category", result, prefix)
		_validate_id_array(memory, "fact_refs", "fact", result, prefix)
		_require_nonempty_string(memory, "summary", result, prefix)
		var status := str(memory.get("timeline_status", ""))
		if status not in ["current", "discarded"]:
			result.add_error(
				"invalid_timeline_status",
				"timeline_status must be 'current' or 'discarded'.",
				"%stimeline_status" % prefix
			)
		var death_category := str(memory.get("death_category", ""))
		if str(memory.get("category", "")) == "death":
			if death_category not in [
				"combat",
				"collision",
				"environment",
				"unknown",
			]:
				result.add_error(
					"invalid_death_category",
					"Death memory requires a verified death category.",
					"%sdeath_category" % prefix
				)
		elif not death_category.is_empty():
			result.add_error(
				"unexpected_death_category",
				"Only death memories may contain death_category.",
				"%sdeath_category" % prefix
			)
		var memory_id := str(memory.get("memory_id", ""))
		if not memory_id.is_empty() and seen.has(memory_id):
			result.add_error(
				"duplicate_memory_id",
				"Duplicate memory ID '%s'." % memory_id,
				"%smemory_id" % prefix
			)
		seen[memory_id] = true


static func _validate_safe_location(
	location: Dictionary,
	result: ValidationResult
) -> void:
	var location_type := str(location.get("type", ""))
	if location_type not in ["initial", "docked", "gate_arrival"]:
		result.add_error(
			"invalid_safe_location_type",
			"Safe location type is unsupported.",
			"safe_location.type"
		)
	_require_id(location, "system_id", "system", result, "safe_location.")
	if location_type == "docked":
		_require_id(location, "station_id", "station", result, "safe_location.")
	elif location_type == "gate_arrival":
		_require_id(location, "gate_id", "gate", result, "safe_location.")


static func _validate_campaign_links(
	by_type: Dictionary,
	timeline_ids: Dictionary,
	result: ValidationResult
) -> void:
	if not by_type.has(CAMPAIGN):
		return
	var campaign: Dictionary = by_type[CAMPAIGN]
	for link in [
		["manifest_id", MANIFEST],
		["asset_registry_id", ASSET_REGISTRY],
		["kaelen_meta_id", KAELEN_META],
	]:
		var field := str(link[0])
		var target_type := str(link[1])
		if by_type.has(target_type) and str(campaign.get(field, "")) != str(
			by_type[target_type].get("id", "")
		):
			result.add_error(
				"malformed_reference",
				"%s does not reference the supplied %s." % [field, target_type],
				"campaign.%s" % field
			)
	var campaign_id := str(campaign.get("id", ""))
	if not timeline_ids.has(str(campaign.get("current_timeline_id", ""))):
		result.add_error(
			"unknown_timeline_reference",
			"Campaign current_timeline_id is absent from the bundle.",
			"campaign.current_timeline_id"
		)
	for document_type in by_type:
		var document: Dictionary = by_type[document_type]
		if document_type != CAMPAIGN \
				and str(document.get("campaign_id", "")) != campaign_id:
			result.add_error(
				"campaign_reference_mismatch",
				"%s belongs to a different campaign." % document_type,
				"%s.campaign_id" % document_type
			)


static func _validate_manifest_links(
	by_type: Dictionary,
	entity_ids: Dictionary,
	result: ValidationResult
) -> void:
	if not by_type.has(MANIFEST):
		return
	var manifest: Dictionary = by_type[MANIFEST]
	var listed_ids: Dictionary = {}
	for entity_id in manifest.get("entity_ids", []):
		listed_ids[str(entity_id)] = true
	for index in range(manifest.get("entity_records", []).size()):
		var record: Variant = manifest["entity_records"][index]
		if not record is Dictionary:
			continue
		var record_id := str(record.get("entity_id", ""))
		if not listed_ids.has(record_id):
			result.add_error(
				"unlisted_entity_record",
				"Entity record '%s' is absent from entity_ids." % record_id,
				"manifest.entity_records.%d.entity_id" % index
			)
	for index in range(manifest.get("canon_facts", []).size()):
		var fact: Variant = manifest["canon_facts"][index]
		if not fact is Dictionary:
			continue
		for subject_index in range(fact.get("subject_ids", []).size()):
			var subject_id := str(fact["subject_ids"][subject_index])
			if not entity_ids.has(subject_id):
				result.add_error(
					"unknown_entity_reference",
					"Canon fact subject '%s' is absent from the manifest." % subject_id,
					"manifest.canon_facts.%d.subject_ids.%d" % [
						index,
						subject_index,
					]
				)


static func _validate_asset_links(
	by_type: Dictionary,
	entity_ids: Dictionary,
	result: ValidationResult
) -> void:
	if not by_type.has(ASSET_REGISTRY) or not by_type.has(MANIFEST):
		return
	for index in range(by_type[ASSET_REGISTRY].get("assets", []).size()):
		var asset: Variant = by_type[ASSET_REGISTRY]["assets"][index]
		if asset is Dictionary:
			var owner := str(asset.get("owner_entity_id", ""))
			if not entity_ids.has(owner):
				result.add_error(
					"unknown_entity_reference",
					"Asset owner '%s' is absent from the manifest." % owner,
					"asset_registry.assets.%d.owner_entity_id" % index
				)


static func _validate_checkpoint_links(
	by_type: Dictionary,
	entity_ids: Dictionary,
	checkpoint_ids: Dictionary,
	timeline_ids: Dictionary,
	event_ids: Dictionary,
	result: ValidationResult
) -> void:
	if by_type.has(MAP_KNOWLEDGE):
		var knowledge: Dictionary = by_type[MAP_KNOWLEDGE]
		if not checkpoint_ids.has(str(knowledge.get("checkpoint_id", ""))):
			result.add_error(
				"unknown_checkpoint_reference",
				"Map knowledge references an unknown checkpoint.",
				"map_knowledge.checkpoint_id"
			)
		for key in ["known_gate_ids", "rumored_gate_ids", "hidden_gate_ids",
				"blocked_gate_ids", "damaged_gate_ids"]:
			for index in range(knowledge.get(key, []).size()):
				var gate_id := str(knowledge[key][index])
				if not entity_ids.has(gate_id):
					result.add_error(
						"unknown_entity_reference",
						"Map gate '%s' is absent from the manifest." % gate_id,
						"map_knowledge.%s.%d" % [key, index]
					)
	if by_type.has(CHECKPOINT):
		var checkpoint: Dictionary = by_type[CHECKPOINT]
		if not timeline_ids.has(str(checkpoint.get("timeline_id", ""))):
			result.add_error(
				"unknown_timeline_reference",
				"Checkpoint references an unknown timeline.",
				"checkpoint.timeline_id"
			)
		var head_event_id := str(
			checkpoint.get("chronicle_head_event_id", "")
		)
		if not head_event_id.is_empty() and not event_ids.has(head_event_id):
			result.add_error(
				"unknown_event_reference",
				"Checkpoint chronicle head is absent from the bundle.",
				"checkpoint.chronicle_head_event_id"
			)


static func _validate_chronicle_links(
	by_type: Dictionary,
	entity_ids: Dictionary,
	checkpoint_ids: Dictionary,
	timeline_ids: Dictionary,
	result: ValidationResult
) -> void:
	if not by_type.has(CHRONICLE_SEGMENT):
		return
	var chronicle: Dictionary = by_type[CHRONICLE_SEGMENT]
	for index in range(chronicle.get("events", []).size()):
		var event: Variant = chronicle["events"][index]
		if not event is Dictionary:
			continue
		if not checkpoint_ids.has(str(event.get("checkpoint_id", ""))):
			result.add_error(
				"unknown_checkpoint_reference",
				"Chronicle event references an unknown checkpoint.",
				"chronicle_segment.events.%d.checkpoint_id" % index
			)
		if not timeline_ids.has(str(event.get("timeline_id", ""))):
			result.add_error(
				"unknown_timeline_reference",
				"Chronicle event references an unknown timeline.",
				"chronicle_segment.events.%d.timeline_id" % index
			)
		for subject_index in range(event.get("subject_ids", []).size()):
			var subject_id := str(event["subject_ids"][subject_index])
			var is_campaign := DomainIdType.namespace_of(subject_id) == "campaign"
			if not is_campaign and not entity_ids.has(subject_id):
				result.add_error(
					"unknown_entity_reference",
					"Chronicle subject '%s' is absent from the manifest." % subject_id,
					"chronicle_segment.events.%d.subject_ids.%d" % [
						index,
						subject_index,
					]
				)


static func _validate_kaelen_links(
	by_type: Dictionary,
	fact_ids: Dictionary,
	checkpoint_ids: Dictionary,
	timeline_ids: Dictionary,
	result: ValidationResult
) -> void:
	if not by_type.has(KAELEN_META):
		return
	var kaelen: Dictionary = by_type[KAELEN_META]
	for index in range(kaelen.get("memories", []).size()):
		var memory: Variant = kaelen["memories"][index]
		if not memory is Dictionary:
			continue
		if not checkpoint_ids.has(str(memory.get("source_checkpoint_id", ""))):
			result.add_error(
				"unknown_checkpoint_reference",
				"Kaelen memory references an unknown checkpoint.",
				"kaelen_meta.memories.%d.source_checkpoint_id" % index
			)
		if not timeline_ids.has(str(memory.get("source_timeline_id", ""))):
			result.add_error(
				"unknown_timeline_reference",
				"Kaelen memory references an unknown timeline.",
				"kaelen_meta.memories.%d.source_timeline_id" % index
			)
		for fact_index in range(memory.get("fact_refs", []).size()):
			var fact_id := str(memory["fact_refs"][fact_index])
			if not fact_ids.has(fact_id):
				result.add_error(
					"unknown_fact_reference",
					"Kaelen memory fact '%s' is absent from the manifest." % fact_id,
					"kaelen_meta.memories.%d.fact_refs.%d" % [
						index,
						fact_index,
					]
				)


static func _require_id(
	data: Dictionary,
	key: String,
	expected_namespace: String,
	result: ValidationResult,
	path_prefix: String = ""
) -> void:
	var value: Variant = data.get(key, "")
	var error := DomainIdType.validation_error(value, expected_namespace)
	if not error.is_empty():
		result.add_error(
			"invalid_id",
			error,
			"%s%s" % [path_prefix, key]
		)


static func _require_optional_id(
	data: Dictionary,
	key: String,
	expected_namespace: String,
	result: ValidationResult,
	path_prefix: String = ""
) -> void:
	if str(data.get(key, "")).is_empty():
		return
	_require_id(data, key, expected_namespace, result, path_prefix)


static func _require_same_id(
	data: Dictionary,
	key: String,
	expected: Variant,
	result: ValidationResult
) -> void:
	_require_id(data, key, "campaign", result)
	if str(data.get(key, "")) != str(expected):
		result.add_error(
			"identity_mismatch",
			"%s must match the document ID." % key,
			key
		)


static func _require_nonempty_string(
	data: Dictionary,
	key: String,
	result: ValidationResult,
	path_prefix: String = ""
) -> void:
	var value: Variant = data.get(key, null)
	if not value is String or str(value).strip_edges().is_empty():
		result.add_error(
			"missing_value",
			"%s must be a non-empty string." % key,
			"%s%s" % [path_prefix, key]
		)


static func _validate_id_array(
	data: Dictionary,
	key: String,
	expected_namespace: String,
	result: ValidationResult,
	path_prefix: String = ""
) -> void:
	var raw: Variant = data.get(key, null)
	if not raw is Array:
		result.add_error(
			"invalid_type",
			"%s must be an array." % key,
			"%s%s" % [path_prefix, key]
		)
		return
	var seen: Dictionary = {}
	for index in range(raw.size()):
		var value: Variant = raw[index]
		var error := DomainIdType.validation_error(value, expected_namespace)
		var path := "%s%s.%d" % [path_prefix, key, index]
		if not error.is_empty():
			result.add_error("invalid_reference", error, path)
		elif seen.has(str(value)):
			result.add_error(
				"duplicate_reference",
				"Duplicate reference '%s'." % value,
				path
			)
		seen[str(value)] = true


static func _validate_object_array(
	data: Dictionary,
	key: String,
	result: ValidationResult
) -> void:
	var raw: Variant = data.get(key, null)
	if not raw is Array:
		result.add_error(
			"invalid_type",
			"%s must be an array." % key,
			key
		)
		return
	for index in range(raw.size()):
		if not raw[index] is Dictionary:
			result.add_error(
				"invalid_type",
				"%s entry must be an object." % key,
				"%s.%d" % [key, index]
			)


static func _reject_keys(
	data: Dictionary,
	keys: Array[String],
	result: ValidationResult
) -> void:
	for key in keys:
		if data.has(key):
			result.add_error(
				"wrong_ownership",
				"Field '%s' does not belong in this document." % key,
				key
			)


static func _reject_nested_keys(
	data: Dictionary,
	keys: Array[String],
	path: String,
	result: ValidationResult
) -> void:
	for key in data:
		var child_path := str(key) if path.is_empty() else "%s.%s" % [path, key]
		if str(key) in keys:
			result.add_error(
				"wrong_ownership",
				"Disposable field '%s' cannot be persisted." % key,
				child_path
			)
		var value: Variant = data[key]
		if value is Dictionary:
			_reject_nested_keys(value as Dictionary, keys, child_path, result)
		elif value is Array:
			for index in range(value.size()):
				if value[index] is Dictionary:
					_reject_nested_keys(
						value[index] as Dictionary,
						keys,
						"%s.%d" % [child_path, index],
						result
					)


static func _is_whole_number(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_equal_approx(
		float(value),
		floorf(float(value))
	)
