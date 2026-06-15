class_name CampaignSlotRegistry
extends RefCounted

const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const SchemaType := preload(
	"res://scripts/persistence/CampaignSchemaCatalog.gd"
)
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ManifestStoreType := preload(
	"res://scripts/persistence/CampaignManifestStore.gd"
)
const ContentRegistryType := preload(
	"res://scripts/registry/GameContentRegistry.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const DEFAULT_ROOT := "user://campaigns"
const SLOT_REGISTRY_VERSION := 1
const SLOT_IDS: Array[String] = ["slot_01", "slot_02", "slot_03"]

var root_path: String
var slots_path: String
var selected_slot_id: String = ""
var slots: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String = DEFAULT_ROOT) -> CampaignSlotRegistry:
	var registry := CampaignSlotRegistry.new()
	registry.root_path = path.trim_suffix("/")
	registry.slots_path = "%s/slots.json" % registry.root_path
	registry._load_or_create()
	return registry


func is_valid() -> bool:
	return validation.is_valid()


func enumerate_slots() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for slot_id in SLOT_IDS:
		output.append((slots.get(slot_id, _empty_slot(slot_id)) as Dictionary).duplicate(true))
	return output


func get_slot(slot_id: String) -> Dictionary:
	if slot_id not in SLOT_IDS:
		return {}
	return (slots.get(slot_id, _empty_slot(slot_id)) as Dictionary).duplicate(true)


func first_empty_slot_id() -> String:
	for slot_id in SLOT_IDS:
		if not bool(slots.get(slot_id, {}).get("occupied", false)):
			return slot_id
	return ""


func create_campaign(
	slot_id: String,
	display_name: String,
	game_version: String,
	initial_state: Dictionary,
	system_registry: SystemRegistry
) -> Dictionary:
	if not is_valid():
		return _failure("Slot registry is invalid.")
	if slot_id not in SLOT_IDS:
		return _failure("Unknown campaign slot '%s'." % slot_id)
	if bool(slots.get(slot_id, {}).get("occupied", false)):
		return _failure("Campaign slot '%s' is already occupied." % slot_id)
	if system_registry == null or not system_registry.is_valid():
		return _failure("System registry is unavailable or invalid.")
	if initial_state.is_empty():
		return _failure("Initial campaign state cannot be empty.")

	var clean_name := display_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Campaign %d" % (SLOT_IDS.find(slot_id) + 1)
	var clean_version := game_version.strip_edges()
	if clean_version.is_empty():
		return _failure("Game version cannot be empty.")

	var identity_key := _random_hex(16)
	var campaign_id := "campaign.local.%s" % identity_key
	var ids := {
		"manifest": "manifest.local.%s" % identity_key,
		"assets": "asset_registry.local.%s" % identity_key,
		"kaelen": "kaelen_meta.local.%s" % identity_key,
		"timeline": "timeline.local.%s" % identity_key,
		"checkpoint": "checkpoint.local.%s.initial" % identity_key,
		"map": "map_knowledge.local.%s.initial" % identity_key,
		"chronicle": "chronicle.local.%s.segment_000001" % identity_key,
		"event": "event.local.%s.start" % identity_key,
		"fact": "fact.local.%s.kaelen_present" % identity_key,
		"memory": "memory.local.%s.opening" % identity_key,
	}
	var documents := _build_initial_documents(
		campaign_id,
		_random_hex(32),
		clean_version,
		ids,
		initial_state,
		system_registry
	)
	if documents.is_empty():
		return _failure(
			"Initial campaign canon could not be built from the registries."
		)
	var bundle_validation := SchemaType.validate_bundle(documents)
	if not bundle_validation.is_valid():
		return _failure(
			"Initial campaign documents failed validation.",
			bundle_validation
		)

	var campaign_path := "%s/%s" % [root_path, slot_id]
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(campaign_path)):
		return _failure("Campaign slot directory already exists.")

	var document_paths := {
		SchemaType.CAMPAIGN: "campaign.json",
		SchemaType.MANIFEST: "manifest.json",
		SchemaType.ASSET_REGISTRY: "assets.json",
		SchemaType.KAELEN_META: "kaelen_meta.json",
		SchemaType.CHECKPOINT:
			"checkpoints/autosave/checkpoint.json",
		SchemaType.MAP_KNOWLEDGE:
			"checkpoints/autosave/map_knowledge.json",
		SchemaType.CHRONICLE_SEGMENT:
			"chronicle/segments/segment_000001.json",
	}
	var transaction_files: Dictionary = {}
	for document in documents:
		var document_type := str(document.get("document_type", ""))
		transaction_files[document_paths.get(document_type, "")] = document

	var checkpoint_index := {
		"schema_version": 1,
		"campaign_id": campaign_id,
		"active_checkpoint_id": ids["checkpoint"],
		"autosave": {
			"checkpoint_id": ids["checkpoint"],
			"path": "checkpoints/autosave",
			"source_reason": "initial",
		},
		"manual": [null, null, null],
	}
	var canon_index := ManifestStoreType.build_initial_canon_index(
		documents[1],
		documents[2]
	)
	transaction_files["canon/manifest_000001.json"] = documents[1]
	transaction_files["canon/assets_000001.json"] = documents[2]
	transaction_files["canon_index.json"] = canon_index
	transaction_files["checkpoint_index.json"] = checkpoint_index
	var campaign_commit := TransactionStoreType.commit_json_set(
		campaign_path,
		"campaign_create",
		transaction_files,
		"checkpoint_index.json",
		_validate_campaign_transaction_file
	)
	if not bool(campaign_commit.get("ok", false)):
		_remove_tree(campaign_path)
		return _failure(
			"Initial campaign transaction failed: %s" %
			campaign_commit.get("error", "unknown error")
		)

	var now := int(Time.get_unix_time_from_system())
	var slot_data := {
		"slot_id": slot_id,
		"occupied": true,
		"campaign_id": campaign_id,
		"display_name": clean_name,
		"created_at_unix": now,
		"last_played_at_unix": now,
		"game_version": clean_version,
		"checkpoint_summary": {
			"checkpoint_id": ids["checkpoint"],
			"source_reason": "initial",
			"system_id": str(
				documents[3]["safe_location"].get("system_id", "system.start")
			),
			"living": true,
		},
	}
	slots[slot_id] = slot_data
	selected_slot_id = slot_id
	if not _write_slot_registry():
		slots[slot_id] = _empty_slot(slot_id)
		selected_slot_id = ""
		_remove_tree(campaign_path)
		return _failure("Campaign slot registry could not be updated.")
	return {
		"ok": true,
		"slot": slot_data.duplicate(true),
		"campaign": documents[0].duplicate(true),
		"checkpoint": documents[3].duplicate(true),
	}


func create_first_available_campaign(
	display_name: String,
	game_version: String,
	initial_state: Dictionary,
	system_registry: SystemRegistry
) -> Dictionary:
	var slot_id := first_empty_slot_id()
	if slot_id.is_empty():
		return _failure("All three campaign slots are occupied.")
	return create_campaign(
		slot_id,
		display_name,
		game_version,
		initial_state,
		system_registry
	)


func select_campaign(slot_id: String) -> Dictionary:
	if slot_id not in SLOT_IDS:
		return _failure("Unknown campaign slot '%s'." % slot_id)
	var slot: Dictionary = slots.get(slot_id, {})
	if not bool(slot.get("occupied", false)):
		return _failure("Campaign slot '%s' is empty." % slot_id)
	var campaign := read_campaign_document(slot_id)
	if not bool(campaign.get("ok", false)):
		return campaign
	selected_slot_id = slot_id
	slot["last_played_at_unix"] = int(Time.get_unix_time_from_system())
	slots[slot_id] = slot
	if not _write_slot_registry():
		return _failure("Selected campaign could not be recorded.")
	return {
		"ok": true,
		"slot": slot.duplicate(true),
		"campaign": campaign["data"],
	}


func rename_campaign(
	slot_id: String,
	display_name: String
) -> Dictionary:
	if slot_id not in SLOT_IDS:
		return _failure("Unknown campaign slot '%s'." % slot_id)
	var slot: Dictionary = slots.get(slot_id, {})
	if not bool(slot.get("occupied", false)):
		return _failure("Campaign slot '%s' is empty." % slot_id)
	var clean_name := display_name.strip_edges()
	if clean_name.is_empty():
		return _failure("Campaign name cannot be empty.")
	clean_name = clean_name.substr(0, 48)
	slot["display_name"] = clean_name
	slots[slot_id] = slot
	if not _write_slot_registry():
		return _failure("Campaign name could not be updated.")
	return {
		"ok": true,
		"slot": slot.duplicate(true),
	}


func update_checkpoint_summary(
	slot_id: String,
	checkpoint_id: String,
	source_reason: String,
	system_id: String,
	living: bool
) -> bool:
	if slot_id not in SLOT_IDS:
		return false
	var slot: Dictionary = slots.get(slot_id, {})
	if not bool(slot.get("occupied", false)):
		return false
	if not DomainIdType.is_valid(checkpoint_id, "checkpoint") \
			or not DomainIdType.is_valid(system_id, "system") \
			or not living:
		return false
	slot["last_played_at_unix"] = int(Time.get_unix_time_from_system())
	slot["checkpoint_summary"] = {
		"checkpoint_id": checkpoint_id,
		"source_reason": source_reason,
		"system_id": system_id,
		"living": true,
	}
	slots[slot_id] = slot
	return _write_slot_registry()


func delete_campaign(slot_id: String) -> Dictionary:
	if slot_id not in SLOT_IDS:
		return _failure("Unknown campaign slot '%s'." % slot_id)
	if not bool(slots.get(slot_id, {}).get("occupied", false)):
		return _failure("Campaign slot '%s' is already empty." % slot_id)
	var slot_path := "%s/%s" % [root_path, slot_id]
	if not _remove_tree(slot_path):
		return _failure("Campaign slot files could not be removed.")
	slots[slot_id] = _empty_slot(slot_id)
	if selected_slot_id == slot_id:
		selected_slot_id = ""
	if not _write_slot_registry():
		return _failure("Campaign deletion could not update the slot registry.")
	return {"ok": true, "slot_id": slot_id}


func read_campaign_document(slot_id: String) -> Dictionary:
	if slot_id not in SLOT_IDS:
		return _failure("Unknown campaign slot '%s'." % slot_id)
	var path := "%s/%s/campaign.json" % [root_path, slot_id]
	var parsed := DomainJsonType.read_object(path)
	var parse_validation := parsed["validation"] as ValidationResult
	if not parse_validation.is_valid():
		return _failure("Campaign document could not be read.", parse_validation)
	var document: Dictionary = parsed["data"]
	var document_validation := SchemaType.validate_document(document)
	if not document_validation.is_valid():
		return _failure(
			"Campaign document failed validation.",
			document_validation
		)
	var slot: Dictionary = slots.get(slot_id, {})
	if bool(slot.get("occupied", false)) \
			and str(slot.get("campaign_id", "")) != str(document.get("id", "")):
		return _failure(
			"Campaign document does not match its occupied slot."
		)
	return {"ok": true, "data": document}


func load_initial_bundle(slot_id: String) -> Dictionary:
	if slot_id not in SLOT_IDS:
		return _failure("Unknown campaign slot '%s'." % slot_id)
	var base := "%s/%s" % [root_path, slot_id]
	var paths := [
		"%s/campaign.json" % base,
		"%s/manifest.json" % base,
		"%s/assets.json" % base,
		"%s/checkpoints/autosave/checkpoint.json" % base,
		"%s/checkpoints/autosave/map_knowledge.json" % base,
		"%s/chronicle/segments/segment_000001.json" % base,
		"%s/kaelen_meta.json" % base,
	]
	var documents: Array = []
	var result := ValidationResultType.new()
	for index in range(paths.size()):
		var parsed := DomainJsonType.read_object(paths[index])
		result.merge(parsed["validation"], "documents.%d" % index)
		if (parsed["validation"] as ValidationResult).is_valid():
			documents.append(parsed["data"])
	if result.is_valid():
		result.merge(SchemaType.validate_bundle(documents))
	if not result.is_valid():
		return _failure("Initial campaign bundle failed validation.", result)
	return {"ok": true, "documents": documents}


func _load_or_create() -> void:
	if not _make_directory(root_path):
		validation.add_error(
			"campaign_root_unavailable",
			"Campaign storage directory could not be created.",
			root_path
		)
		return
	if not FileAccess.file_exists(slots_path):
		for slot_id in SLOT_IDS:
			slots[slot_id] = _empty_slot(slot_id)
		if not _write_slot_registry():
			validation.add_error(
				"slot_registry_unwritable",
				"Campaign slot registry could not be created.",
				slots_path
			)
		return

	var recovered := TransactionStoreType.recover_index(
		root_path,
		"slots.json",
		_validate_slot_registry_file
	)
	if not bool(recovered.get("ok", false)):
		validation.add_error(
			"slot_registry_unrecoverable",
			recovered.get("error", "Campaign slot registry is unavailable."),
			slots_path
		)
		return
	var parsed := {
		"data": recovered["data"],
		"validation": ValidationResultType.new(),
	}
	validation.merge(parsed["validation"])
	if not validation.is_valid():
		return
	_load_slot_registry(parsed["data"])


func _load_slot_registry(data: Dictionary) -> void:
	if int(data.get("schema_version", -1)) != SLOT_REGISTRY_VERSION:
		validation.add_error(
			"unsupported_slot_registry",
			"Slot registry version is unsupported.",
			"schema_version"
		)
	var raw_slots: Variant = data.get("slots", null)
	if not raw_slots is Array or raw_slots.size() != SLOT_IDS.size():
		validation.add_error(
			"invalid_slot_count",
			"Slot registry must contain exactly three slots.",
			"slots"
		)
		return
	var seen: Dictionary = {}
	for index in range(raw_slots.size()):
		var raw: Variant = raw_slots[index]
		if not raw is Dictionary:
			validation.add_error(
				"invalid_slot",
				"Slot entry must be an object.",
				"slots.%d" % index
			)
			continue
		var slot := raw as Dictionary
		var slot_id := str(slot.get("slot_id", ""))
		if slot_id not in SLOT_IDS or seen.has(slot_id):
			validation.add_error(
				"invalid_slot_id",
				"Slot ID must be one of the three stable IDs.",
				"slots.%d.slot_id" % index
			)
			continue
		seen[slot_id] = true
		var occupied: Variant = slot.get("occupied", null)
		if not occupied is bool:
			validation.add_error(
				"invalid_occupied_flag",
				"occupied must be a boolean.",
				"slots.%d.occupied" % index
			)
			continue
		if occupied and str(slot.get("campaign_id", "")).is_empty():
			validation.add_error(
				"missing_campaign_id",
				"Occupied slot requires a campaign ID.",
				"slots.%d.campaign_id" % index
			)
		elif occupied and not DomainIdType.is_valid(
			slot.get("campaign_id", ""),
			"campaign"
		):
			validation.add_error(
				"invalid_campaign_id",
				"Occupied slot requires a valid campaign ID.",
				"slots.%d.campaign_id" % index
			)
		if occupied:
			for key in ["display_name", "game_version"]:
				if str(slot.get(key, "")).strip_edges().is_empty():
					validation.add_error(
						"missing_slot_metadata",
						"Occupied slot requires %s." % key,
						"slots.%d.%s" % [index, key]
					)
			for key in ["created_at_unix", "last_played_at_unix"]:
				if int(slot.get(key, 0)) <= 0:
					validation.add_error(
						"invalid_slot_timestamp",
						"Occupied slot requires a positive %s." % key,
						"slots.%d.%s" % [index, key]
					)
			if not slot.get("checkpoint_summary", null) is Dictionary:
				validation.add_error(
					"invalid_checkpoint_summary",
					"Occupied slot requires a checkpoint summary.",
					"slots.%d.checkpoint_summary" % index
				)
			else:
				var summary: Dictionary = slot["checkpoint_summary"]
				if not DomainIdType.is_valid(
					summary.get("checkpoint_id", ""),
					"checkpoint"
				):
					validation.add_error(
						"invalid_checkpoint_summary",
						"Checkpoint summary requires a valid checkpoint ID.",
						"slots.%d.checkpoint_summary.checkpoint_id" % index
					)
				if not DomainIdType.is_valid(
					summary.get("system_id", ""),
					"system"
				):
					validation.add_error(
						"invalid_checkpoint_summary",
						"Checkpoint summary requires a valid system ID.",
						"slots.%d.checkpoint_summary.system_id" % index
					)
				if summary.get("living", null) != true:
					validation.add_error(
						"invalid_checkpoint_summary",
						"Checkpoint summary must identify a living checkpoint.",
						"slots.%d.checkpoint_summary.living" % index
					)
		slots[slot_id] = slot.duplicate(true)
	for slot_id in SLOT_IDS:
		if not seen.has(slot_id):
			validation.add_error(
				"missing_slot",
				"Stable slot '%s' is missing." % slot_id,
				"slots"
			)
	selected_slot_id = str(data.get("selected_slot_id", ""))
	if not selected_slot_id.is_empty():
		if selected_slot_id not in SLOT_IDS \
				or not bool(slots.get(selected_slot_id, {}).get("occupied", false)):
			validation.add_error(
				"invalid_selected_slot",
				"Selected slot must reference an occupied stable slot.",
				"selected_slot_id"
			)


func _build_initial_documents(
	campaign_id: String,
	campaign_seed: String,
	game_version: String,
	ids: Dictionary,
	initial_state: Dictionary,
	system_registry: SystemRegistry
) -> Array:
	var current_system_id := str(
		initial_state.get("current_system_id", "system.start")
	)
	var system_definition := system_registry.get_system(current_system_id)
	if system_definition == null:
		current_system_id = "system.start"
		system_definition = system_registry.get_system(current_system_id)
	var hidden_gates: Array[String] = []
	for gate in system_definition.gates:
		hidden_gates.append(str(gate.id))

	var campaign := {
		"document_type": SchemaType.CAMPAIGN,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.PERMANENT,
		"id": campaign_id,
		"campaign_id": campaign_id,
		"campaign_seed": campaign_seed,
		"creation_version": game_version,
		"manifest_id": ids["manifest"],
		"asset_registry_id": ids["assets"],
		"kaelen_meta_id": ids["kaelen"],
		"current_timeline_id": ids["timeline"],
	}
	var canon_result := ManifestStoreType.build_handcrafted_documents(
		campaign_id,
		ids["manifest"],
		ids["assets"],
		system_registry,
		ContentRegistryType.shared(),
		ids["fact"]
	)
	if not bool(canon_result.get("ok", false)):
		return []
	var manifest: Dictionary = canon_result["manifest"]
	var assets: Dictionary = canon_result["assets"]
	var checkpoint_state: Dictionary = initial_state.duplicate(true)
	checkpoint_state.erase("current_system_id")
	_strip_tactical_state(checkpoint_state)
	var checkpoint := {
		"document_type": SchemaType.CHECKPOINT,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.REWINDABLE,
		"id": ids["checkpoint"],
		"campaign_id": campaign_id,
		"timeline_id": ids["timeline"],
		"chronicle_head_event_id": ids["event"],
		"source_reason": "initial",
		"living": true,
		"transitional": false,
		"safe_location": {
			"type": "initial",
			"system_id": current_system_id,
		},
		"state": checkpoint_state,
	}
	var map_knowledge := {
		"document_type": SchemaType.MAP_KNOWLEDGE,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.REWINDABLE,
		"id": ids["map"],
		"campaign_id": campaign_id,
		"checkpoint_id": ids["checkpoint"],
		"known_gate_ids": [],
		"rumored_gate_ids": [],
		"hidden_gate_ids": hidden_gates,
		"blocked_gate_ids": [],
		"damaged_gate_ids": [],
	}
	var chronicle := {
		"document_type": SchemaType.CHRONICLE_SEGMENT,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.APPEND_ONLY,
		"id": ids["chronicle"],
		"campaign_id": campaign_id,
		"timeline_id": ids["timeline"],
		"events": [{
			"event_id": ids["event"],
			"timeline_id": ids["timeline"],
			"parent_event_id": "",
			"checkpoint_id": ids["checkpoint"],
			"event_type": "campaign_started",
			"subject_ids": [campaign_id, current_system_id],
			"payload": {"initial_checkpoint": true},
			"sequence": 0,
		}],
	}
	var kaelen_meta := {
		"document_type": SchemaType.KAELEN_META,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.META_MEMORY,
		"id": ids["kaelen"],
		"campaign_id": campaign_id,
		"timeline_reversal_count": 0,
		"memories": [{
			"memory_id": ids["memory"],
			"source_timeline_id": ids["timeline"],
			"source_checkpoint_id": ids["checkpoint"],
			"event_sequence": 0,
			"category": "observation",
			"fact_refs": [ids["fact"]],
			"summary": "Shiny arrived in the opening system.",
			"timeline_status": "current",
		}],
	}
	return [
		campaign,
		manifest,
		assets,
		checkpoint,
		map_knowledge,
		chronicle,
		kaelen_meta,
	]


func _strip_tactical_state(value: Variant) -> void:
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			if str(key) in [
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
			]:
				(value as Dictionary).erase(key)
			else:
				_strip_tactical_state((value as Dictionary)[key])
	elif value is Array:
		for item in value:
			_strip_tactical_state(item)


func _write_slot_registry() -> bool:
	var data := {
		"schema_version": SLOT_REGISTRY_VERSION,
		"selected_slot_id": selected_slot_id,
		"slots": enumerate_slots(),
	}
	var committed := TransactionStoreType.commit_json_set(
		root_path,
		"slot_registry",
		{"slots.json": data},
		"slots.json",
		_validate_slot_registry_file
	)
	return bool(committed.get("ok", false))


func _validate_slot_registry_file(
	path: String,
	data: Dictionary
) -> ValidationResult:
	var result := ValidationResultType.new()
	if path.get_file() != "slots.json":
		return result
	if int(data.get("schema_version", -1)) != SLOT_REGISTRY_VERSION:
		result.add_error(
			"unsupported_slot_registry",
			"Slot registry version is unsupported.",
			"schema_version"
		)
	var raw_slots: Variant = data.get("slots", null)
	if not raw_slots is Array or raw_slots.size() != SLOT_IDS.size():
		result.add_error(
			"invalid_slot_count",
			"Slot registry must contain exactly three slots.",
			"slots"
		)
	return result


func _validate_campaign_transaction_file(
	path: String,
	data: Dictionary
) -> ValidationResult:
	var result := ValidationResultType.new()
	if path.get_file() == "checkpoint_index.json":
		if int(data.get("schema_version", -1)) != 1:
			result.add_error(
				"invalid_checkpoint_index",
				"Checkpoint index version must be 1.",
				"schema_version"
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
		return result
	if path.get_file() == "canon_index.json":
		return ManifestStoreType.validate_canon_index(path, data)
	return SchemaType.validate_document(data)


func _write_json(path: String, data: Dictionary) -> bool:
	if path.is_empty():
		return false
	var parent := path.get_base_dir()
	if not _make_directory(parent):
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(DomainJsonType.stringify(data, true))
	return file.get_error() == OK


func _make_directory(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	return DirAccess.make_dir_recursive_absolute(absolute) in [OK, ERR_ALREADY_EXISTS]


func _remove_tree(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	var directory := DirAccess.open(absolute)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := "%s/%s" % [absolute, entry]
			if directory.current_is_dir():
				if not _remove_tree(child):
					directory.list_dir_end()
					return false
			elif DirAccess.remove_absolute(child) != OK:
				directory.list_dir_end()
				return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute) == OK


static func _empty_slot(slot_id: String) -> Dictionary:
	return {
		"slot_id": slot_id,
		"occupied": false,
		"campaign_id": "",
		"display_name": "",
		"created_at_unix": 0,
		"last_played_at_unix": 0,
		"game_version": "",
		"checkpoint_summary": {},
	}


static func _random_hex(byte_count: int) -> String:
	return Crypto.new().generate_random_bytes(byte_count).hex_encode()


static func _failure(
	message: String,
	details: ValidationResult = null
) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"validation": (
			details.to_dict()
			if details != null
			else {}
		),
	}
