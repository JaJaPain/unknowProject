class_name CampaignManifestStore
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

const CANON_INDEX_VERSION := 1

var campaign_path: String
var manifest: Dictionary = {}
var assets: Dictionary = {}
var generation: int = 0
var validation := ValidationResultType.new()


static func open(path: String) -> CampaignManifestStore:
	var store := CampaignManifestStore.new()
	store.campaign_path = path.trim_suffix("/")
	store._load()
	return store


static func build_handcrafted_documents(
	campaign_id: String,
	manifest_id: String,
	asset_registry_id: String,
	system_registry: SystemRegistry,
	content_registry: GameContentRegistry,
	opening_fact_id: String = ""
) -> Dictionary:
	var result := ValidationResultType.new()
	if not DomainIdType.is_valid(campaign_id, "campaign"):
		result.add_error(
			"invalid_campaign_id",
			"Campaign ID is invalid.",
			"campaign_id"
		)
	if system_registry == null or not system_registry.is_valid():
		result.add_error(
			"invalid_system_registry",
			"System registry is unavailable."
		)
	if content_registry == null or not content_registry.is_valid():
		result.add_error(
			"invalid_content_registry",
			"Game content registry is unavailable."
		)
	if not result.is_valid():
		return {"ok": false, "validation": result, "error": result.summary()}

	var entity_records: Array[Dictionary] = []
	var asset_records: Array[Dictionary] = []
	for system: SystemDefinition in system_registry.systems.values():
		_add_entity_record(
			entity_records,
			system.id,
			"system",
			system.origin,
			SystemRegistry.DEFAULT_PATH,
			system.to_dict()
		)
		_add_asset_record(
			asset_records,
			system.id,
			system.scene_path,
			"",
			"curated_system_scene"
		)
		for station_id in system.station_ids:
			_add_entity_record(
				entity_records,
				station_id,
				"station",
				system.origin,
				SystemRegistry.DEFAULT_PATH,
				{"system_id": str(system.id), "station_id": str(station_id)}
			)
		for gate: GateDefinition in system.gates:
			_add_entity_record(
				entity_records,
				gate.id,
				"gate",
				system.origin,
				SystemRegistry.DEFAULT_PATH,
				gate.to_dict()
			)

	for definition: FactionDefinition in content_registry.factions.values():
		_add_entity_record(
			entity_records,
			definition.id,
			"faction",
			"authored",
			"res://data/content/factions.json",
			_faction_snapshot(definition)
		)
	for definition: NpcDefinition in content_registry.npcs.values():
		_add_entity_record(
			entity_records,
			definition.id,
			"npc",
			"authored",
			"res://data/content/npcs.json",
			_npc_snapshot(definition)
		)
	for definition: VoiceProfileDefinition in content_registry.voices.values():
		_add_entity_record(
			entity_records,
			definition.id,
			"voice",
			"authored",
			"res://data/content/voices.json",
			_voice_snapshot(definition)
		)
	for definition: ShipDesignDefinition in content_registry.ships.values():
		_add_entity_record(
			entity_records,
			definition.id,
			"ship_design",
			"authored",
			"res://data/content/ship_designs.json",
			_ship_snapshot(definition)
		)
		_add_asset_record(
			asset_records,
			definition.id,
			definition.asset_path,
			definition.fallback_asset_path,
			"curated_ship_model"
		)
	for definition: PortraitDefinition in content_registry.portraits.values():
		_add_entity_record(
			entity_records,
			definition.id,
			"portrait",
			"authored",
			definition.source_path,
			_portrait_snapshot(definition)
		)
		_add_asset_record(
			asset_records,
			definition.id,
			definition.source_path,
			"",
			"curated_portrait_sheet"
		)

	entity_records.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["entity_id"]) < str(b["entity_id"])
	)
	asset_records.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["asset_id"]) < str(b["asset_id"])
	)
	var entity_ids: Array[String] = []
	for record in entity_records:
		entity_ids.append(str(record["entity_id"]))
	if opening_fact_id.is_empty():
		opening_fact_id = "fact.%s.kaelen_present" % _campaign_key(campaign_id)
	var manifest_document := {
		"document_type": SchemaType.MANIFEST,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.PERMANENT,
		"id": manifest_id,
		"campaign_id": campaign_id,
		"entity_ids": entity_ids,
		"entity_records": entity_records,
		"canon_facts": [{
			"fact_id": opening_fact_id,
			"subject_ids": ["npc.kaelen", "system.start"],
			"value": true,
		}],
	}
	var asset_document := {
		"document_type": SchemaType.ASSET_REGISTRY,
		"schema_version": SchemaType.SCHEMA_VERSION,
		"ownership": SchemaType.PERMANENT,
		"id": asset_registry_id,
		"campaign_id": campaign_id,
		"assets": _deduplicate_assets(asset_records),
	}
	var bundle_validation := SchemaType.validate_bundle([
		manifest_document,
		asset_document,
	])
	result.merge(bundle_validation)
	return {
		"ok": result.is_valid(),
		"manifest": manifest_document,
		"assets": asset_document,
		"validation": result,
		"error": "" if result.is_valid() else result.summary(),
	}


static func build_initial_canon_index(
	manifest_document: Dictionary,
	asset_document: Dictionary
) -> Dictionary:
	return {
		"schema_version": CANON_INDEX_VERSION,
		"campaign_id": manifest_document.get("campaign_id", ""),
		"generation": 1,
		"manifest_path": "canon/manifest_000001.json",
		"asset_registry_path": "canon/assets_000001.json",
		"manifest_hash": _stable_hash(manifest_document),
		"asset_registry_hash": _stable_hash(asset_document),
	}


static func validate_canon_index(
	path: String,
	data: Dictionary
) -> ValidationResult:
	return _validate_canon_index(path, data)


func is_valid() -> bool:
	return validation.is_valid()


func register_entity(record: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Campaign canon store is invalid.")
	var entity_id := str(record.get("entity_id", ""))
	if not DomainIdType.is_valid(entity_id):
		return _failure("Generated entity ID is invalid.")
	var existing := _find_record(manifest.get("entity_records", []), "entity_id", entity_id)
	if not existing.is_empty():
		if _stable_hash(existing) == _stable_hash(record):
			return {"ok": true, "unchanged": true, "entity_id": entity_id}
		return _failure("Permanent entity identity already exists with different canon.")
	var updated_manifest := manifest.duplicate(true)
	updated_manifest["entity_ids"].append(entity_id)
	updated_manifest["entity_records"].append(record.duplicate(true))
	return _commit_generation(updated_manifest, assets)


func register_canon_fact(fact: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Campaign canon store is invalid.")
	var fact_id := str(fact.get("fact_id", ""))
	if not DomainIdType.is_valid(fact_id, "fact"):
		return _failure("Canon fact ID is invalid.")
	var existing := _find_record(manifest.get("canon_facts", []), "fact_id", fact_id)
	if not existing.is_empty():
		if _stable_hash(existing) == _stable_hash(fact):
			return {"ok": true, "unchanged": true, "fact_id": fact_id}
		return _failure("Permanent canon fact already exists with a different value.")
	var updated_manifest := manifest.duplicate(true)
	updated_manifest["canon_facts"].append(fact.duplicate(true))
	return _commit_generation(updated_manifest, assets)


func register_asset(record: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Campaign canon store is invalid.")
	var asset_id := str(record.get("asset_id", ""))
	var existing := _find_record(assets.get("assets", []), "asset_id", asset_id)
	if not existing.is_empty():
		if _stable_identity_hash(existing) == _stable_identity_hash(record):
			return {"ok": true, "unchanged": true, "asset_id": asset_id}
		return _failure("Permanent asset identity already exists with different provenance.")
	var updated_assets := assets.duplicate(true)
	updated_assets["assets"].append(record.duplicate(true))
	return _commit_generation(manifest, updated_assets)


func audit_assets() -> Dictionary:
	if not is_valid():
		return _failure("Campaign canon store is invalid.")
	var report: Array[Dictionary] = []
	var updated_assets := assets.duplicate(true)
	var changed := false
	for index in range(updated_assets.get("assets", []).size()):
		var record: Dictionary = updated_assets["assets"][index]
		var status := _asset_status(
			str(record.get("source_path", "")),
			str(record.get("fallback_path", ""))
		)
		var effective_path := str(status.get("effective_path", ""))
		var new_status := str(status.get("validation_status", "missing"))
		if record.get("validation_status") != new_status:
			record["validation_status"] = new_status
			updated_assets["assets"][index] = record
			changed = true
		report.append({
			"asset_id": record.get("asset_id", ""),
			"owner_entity_id": record.get("owner_entity_id", ""),
			"validation_status": new_status,
			"effective_path": effective_path,
			"rebuild_instruction": record.get("rebuild_instruction", ""),
		})
	if changed:
		var committed := _commit_generation(manifest, updated_assets)
		if not bool(committed.get("ok", false)):
			return committed
	return {"ok": true, "changed": changed, "assets": report}


func _load() -> void:
	var recovered := TransactionStoreType.recover_index(
		campaign_path,
		"canon_index.json",
		_validate_canon_index
	)
	if not bool(recovered.get("ok", false)):
		validation.add_error(
			"canon_index_unavailable",
			recovered.get("error", "Campaign canon index is unavailable.")
		)
		return
	var index: Dictionary = recovered["data"]
	generation = int(index.get("generation", 0))
	var manifest_result := DomainJsonType.read_object(
		"%s/%s" % [campaign_path, index.get("manifest_path", "")]
	)
	var asset_result := DomainJsonType.read_object(
		"%s/%s" % [campaign_path, index.get("asset_registry_path", "")]
	)
	validation.merge(manifest_result["validation"], "manifest")
	validation.merge(asset_result["validation"], "assets")
	if not validation.is_valid():
		return
	manifest = manifest_result["data"]
	assets = asset_result["data"]
	validation.merge(SchemaType.validate_document(manifest), "manifest")
	validation.merge(SchemaType.validate_document(assets), "assets")
	validation.merge(SchemaType.validate_bundle([manifest, assets]))
	if _stable_hash(manifest) != str(index.get("manifest_hash", "")):
		validation.add_error(
			"manifest_hash_mismatch",
			"Permanent manifest does not match its canon index.",
			"manifest_hash"
		)
	if _stable_hash(assets) != str(index.get("asset_registry_hash", "")):
		validation.add_error(
			"asset_registry_hash_mismatch",
			"Permanent asset registry does not match its canon index.",
			"asset_registry_hash"
		)


func _commit_generation(
	updated_manifest: Dictionary,
	updated_assets: Dictionary
) -> Dictionary:
	var next_generation := generation + 1
	var suffix := "%06d" % next_generation
	var manifest_path := "canon/manifest_%s.json" % suffix
	var asset_path := "canon/assets_%s.json" % suffix
	var index := {
		"schema_version": CANON_INDEX_VERSION,
		"campaign_id": updated_manifest.get("campaign_id", ""),
		"generation": next_generation,
		"manifest_path": manifest_path,
		"asset_registry_path": asset_path,
		"manifest_hash": _stable_hash(updated_manifest),
		"asset_registry_hash": _stable_hash(updated_assets),
	}
	var committed := TransactionStoreType.commit_json_set(
		campaign_path,
		"canon_append",
		{
			manifest_path: updated_manifest,
			asset_path: updated_assets,
			"manifest.json": updated_manifest,
			"assets.json": updated_assets,
			"canon_index.json": index,
		},
		"canon_index.json",
		_validate_canon_transaction_file
	)
	if not bool(committed.get("ok", false)):
		return committed
	manifest = updated_manifest.duplicate(true)
	assets = updated_assets.duplicate(true)
	generation = next_generation
	return {"ok": true, "generation": generation}


func _validate_canon_transaction_file(
	path: String,
	data: Dictionary
) -> ValidationResult:
	if path.get_file() == "canon_index.json":
		return _validate_canon_index(path, data)
	return SchemaType.validate_document(data)


static func _validate_canon_index(
	_path: String,
	data: Dictionary
) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(data.get("schema_version", -1)) != CANON_INDEX_VERSION:
		result.add_error(
			"invalid_canon_index",
			"Canon index version must be 1.",
			"schema_version"
		)
	if not DomainIdType.is_valid(data.get("campaign_id", ""), "campaign"):
		result.add_error(
			"invalid_canon_index",
			"Canon index requires a campaign ID.",
			"campaign_id"
		)
	if int(data.get("generation", 0)) < 1:
		result.add_error(
			"invalid_canon_index",
			"Canon index generation must be positive.",
			"generation"
		)
	var generation_value := int(data.get("generation", 0))
	var expected_suffix := "%06d" % generation_value
	if str(data.get("manifest_path", "")) \
			!= "canon/manifest_%s.json" % expected_suffix:
		result.add_error(
			"invalid_canon_index",
			"Canon manifest path must match its generation.",
			"manifest_path"
		)
	if str(data.get("asset_registry_path", "")) \
			!= "canon/assets_%s.json" % expected_suffix:
		result.add_error(
			"invalid_canon_index",
			"Canon asset path must match its generation.",
			"asset_registry_path"
		)
	for key in [
		"manifest_path",
		"asset_registry_path",
		"manifest_hash",
		"asset_registry_hash",
	]:
		if str(data.get(key, "")).is_empty():
			result.add_error(
				"invalid_canon_index",
				"Canon index requires %s." % key,
				key
			)
	return result


static func _add_entity_record(
	output: Array[Dictionary],
	entity_id: Variant,
	entity_type: String,
	origin: String,
	source_registry: String,
	snapshot: Dictionary
) -> void:
	output.append({
		"entity_id": str(entity_id),
		"entity_type": entity_type,
		"origin": origin,
		"source_registry": source_registry,
		"definition_hash": _stable_hash(snapshot),
	})


static func _add_asset_record(
	output: Array[Dictionary],
	owner_entity_id: Variant,
	source_path: String,
	fallback_path: String,
	generator_type: String
) -> void:
	if source_path.is_empty():
		return
	var identity := "%s|%s" % [owner_entity_id, source_path]
	var status := _asset_status(source_path, fallback_path)
	output.append({
		"asset_id": "asset.curated.%s" % identity.sha256_text().substr(0, 20),
		"owner_entity_id": str(owner_entity_id),
		"generator_type": generator_type,
		"generator_version": "phase_1_registry_v1",
		"generation_seed": "authored",
		"provenance_hash": _file_hash_or_identity(source_path),
		"source_path": source_path,
		"fallback_path": fallback_path,
		"validation_status": status["validation_status"],
		"rebuild_instruction":
			"Restore the original curated asset or provide a validated fallback.",
	})


static func _deduplicate_assets(records: Array[Dictionary]) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var seen: Dictionary = {}
	for record in records:
		var asset_id := str(record.get("asset_id", ""))
		if not seen.has(asset_id):
			seen[asset_id] = true
			output.append(record)
	return output


static func _asset_status(source_path: String, fallback_path: String) -> Dictionary:
	if _asset_exists(source_path):
		return {"validation_status": "approved", "effective_path": source_path}
	if not fallback_path.is_empty() and _asset_exists(fallback_path):
		return {"validation_status": "fallback", "effective_path": fallback_path}
	return {"validation_status": "rebuild_required", "effective_path": ""}


static func _asset_exists(path: String) -> bool:
	return not path.is_empty() and (
		FileAccess.file_exists(path) or ResourceLoader.exists(path)
	)


static func _file_hash_or_identity(path: String) -> String:
	if FileAccess.file_exists(path):
		var hash := FileAccess.get_sha256(path)
		if not hash.is_empty():
			return "sha256:%s" % hash
	return "identity:%s" % path.sha256_text()


static func _find_record(
	records: Array,
	key: String,
	value: String
) -> Dictionary:
	for raw in records:
		if raw is Dictionary and str(raw.get(key, "")) == value:
			return (raw as Dictionary).duplicate(true)
	return {}


static func _stable_identity_hash(record: Dictionary) -> String:
	var identity := record.duplicate(true)
	identity.erase("validation_status")
	return _stable_hash(identity)


static func _stable_hash(value: Variant) -> String:
	var normalized: Variant = JSON.parse_string(
		JSON.stringify(value, "", true)
	)
	return JSON.stringify(normalized, "", true).sha256_text()


static func _campaign_key(campaign_id: String) -> String:
	return campaign_id.replace(".", "_")


static func _faction_snapshot(definition: FactionDefinition) -> Dictionary:
	return {
		"id": str(definition.id),
		"display_name": definition.display_name,
		"classification": definition.classification,
		"agent_npc_id": str(definition.agent_npc_id),
		"voice_profile_id": str(definition.voice_profile_id),
	}


static func _npc_snapshot(definition: NpcDefinition) -> Dictionary:
	return {
		"id": str(definition.id),
		"display_name": definition.display_name,
		"faction_id": str(definition.faction_id),
		"portrait_id": str(definition.portrait_id),
		"voice_profile_id": str(definition.voice_profile_id),
		"location_id": str(definition.location_id),
		"protected": definition.protected,
	}


static func _voice_snapshot(definition: VoiceProfileDefinition) -> Dictionary:
	return {
		"id": str(definition.id),
		"display_name": definition.display_name,
		"language": definition.language,
		"style_tags": definition.style_tags,
		"fallback_voice_profile_id": str(definition.fallback_voice_profile_id),
	}


static func _ship_snapshot(definition: ShipDesignDefinition) -> Dictionary:
	return {
		"id": str(definition.id),
		"display_name": definition.display_name,
		"faction_id": str(definition.faction_id),
		"role": definition.role,
		"asset_path": definition.asset_path,
		"fallback_asset_path": definition.fallback_asset_path,
	}


static func _portrait_snapshot(definition: PortraitDefinition) -> Dictionary:
	return {
		"id": str(definition.id),
		"sheet_id": str(definition.sheet_id),
		"source_path": definition.source_path,
		"bounds": [
			definition.bounds.position.x,
			definition.bounds.position.y,
			definition.bounds.size.x,
			definition.bounds.size.y,
		],
		"tags": definition.tags,
	}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
