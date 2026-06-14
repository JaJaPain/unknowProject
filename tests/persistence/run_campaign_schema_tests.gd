extends SceneTree

const SchemaType := preload(
	"res://scripts/persistence/CampaignSchemaCatalog.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_test_ownership_catalog()
	_test_valid_documents()
	_test_valid_bundle()
	_test_missing_ids()
	_test_wrong_ownership()
	_test_unsupported_version()
	_test_disposable_checkpoint_state()
	_test_malformed_references()
	_test_kaelen_restrictions()

	if _failures.is_empty():
		print("[PASS] Campaign storage schema tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_ownership_catalog() -> void:
	_expect(
		SchemaType.ownership_for(SchemaType.MANIFEST) == SchemaType.PERMANENT,
		"Manifest ownership should be permanent."
	)
	_expect(
		SchemaType.ownership_for(SchemaType.CHECKPOINT) == SchemaType.REWINDABLE,
		"Checkpoint ownership should be rewindable."
	)
	var table := SchemaType.ownership_table()
	_expect(
		"autopilot_waypoint" in table[SchemaType.DISPOSABLE],
		"Disposable ownership table is missing tactical waypoints."
	)


func _test_valid_documents() -> void:
	for document in _valid_bundle():
		var validation = SchemaType.validate_document(document)
		_expect(
			validation.is_valid(),
			"Valid %s document failed: %s" % [
				document.get("document_type", "unknown"),
				validation.summary(),
			]
		)


func _test_valid_bundle() -> void:
	var validation = SchemaType.validate_bundle(_valid_bundle())
	_expect(validation.is_valid(), "Representative campaign bundle failed.")


func _test_missing_ids() -> void:
	var document := _campaign()
	document.erase("id")
	var validation = SchemaType.validate_document(document)
	_expect(not validation.is_valid(), "Campaign without ID was accepted.")
	_expect(
		_has_issue(validation.errors, "invalid_id", "id"),
		"Missing campaign ID did not report its precise path."
	)


func _test_wrong_ownership() -> void:
	var document := _manifest()
	document["ownership"] = SchemaType.REWINDABLE
	document["player_state"] = {"credits": 999}
	var validation = SchemaType.validate_document(document)
	_expect(not validation.is_valid(), "Wrong manifest ownership was accepted.")
	_expect(
		_has_issue(validation.errors, "wrong_ownership", "ownership")
			and _has_issue(
				validation.errors,
				"wrong_ownership",
				"player_state"
			),
		"Wrong ownership did not report both precise paths."
	)


func _test_unsupported_version() -> void:
	var document := _checkpoint()
	document["schema_version"] = 99
	var validation = SchemaType.validate_document(document)
	_expect(not validation.is_valid(), "Unsupported schema was accepted.")
	_expect(
		_has_issue(
			validation.errors,
			"unsupported_schema_version",
			"schema_version"
		),
		"Unsupported schema did not identify schema_version."
	)


func _test_disposable_checkpoint_state() -> void:
	var document := _checkpoint()
	document["state"]["player"]["autopilot_waypoints"] = [{"x": 1}]
	var validation = SchemaType.validate_document(document)
	_expect(
		not validation.is_valid(),
		"Checkpoint persisted a disposable autopilot waypoint."
	)
	_expect(
		_has_issue(
			validation.errors,
			"wrong_ownership",
			"state.player.autopilot_waypoints"
		),
		"Disposable field failure did not retain its nested path."
	)


func _test_malformed_references() -> void:
	var documents := _valid_bundle()
	documents[2]["assets"][0]["owner_entity_id"] = "npc.not_in_manifest"
	documents[4]["checkpoint_id"] = "checkpoint.missing"
	documents[6]["memories"][0]["fact_refs"] = ["fact.missing"]
	var validation = SchemaType.validate_bundle(documents)
	_expect(not validation.is_valid(), "Broken bundle references were accepted.")
	_expect(
		_has_issue(
			validation.errors,
			"unknown_entity_reference",
			"asset_registry.assets.0.owner_entity_id"
		),
		"Unknown asset owner path was not precise."
	)
	_expect(
		_has_issue(
			validation.errors,
			"unknown_checkpoint_reference",
			"map_knowledge.checkpoint_id"
		),
		"Unknown map checkpoint path was not precise."
	)
	_expect(
		_has_issue(
			validation.errors,
			"unknown_fact_reference",
			"kaelen_meta.memories.0.fact_refs.0"
		),
		"Unknown Kaelen fact path was not precise."
	)


func _test_kaelen_restrictions() -> void:
	var document := _kaelen_meta()
	document["memories"][0]["mission_progress"] = {"complete": true}
	var validation = SchemaType.validate_document(document)
	_expect(
		not validation.is_valid(),
		"Kaelen meta-memory accepted prohibited mission progress."
	)
	_expect(
		_has_issue(
			validation.errors,
			"wrong_ownership",
			"memories.0.mission_progress"
		),
		"Kaelen restriction did not report the memory field path."
	)


func _valid_bundle() -> Array:
	return [
		_campaign(),
		_manifest(),
		_asset_registry(),
		_checkpoint(),
		_map_knowledge(),
		_chronicle(),
		_kaelen_meta(),
	]


func _campaign() -> Dictionary:
	return {
		"document_type": SchemaType.CAMPAIGN,
		"schema_version": 1,
		"ownership": SchemaType.PERMANENT,
		"id": "campaign.local.alpha",
		"campaign_id": "campaign.local.alpha",
		"campaign_seed": "seed-alpha",
		"creation_version": "prototype-phase-2",
		"manifest_id": "manifest.local.alpha",
		"asset_registry_id": "asset_registry.local.alpha",
		"kaelen_meta_id": "kaelen_meta.local.alpha",
		"current_timeline_id": "timeline.local.alpha",
	}


func _manifest() -> Dictionary:
	return {
		"document_type": SchemaType.MANIFEST,
		"schema_version": 1,
		"ownership": SchemaType.PERMANENT,
		"id": "manifest.local.alpha",
		"campaign_id": "campaign.local.alpha",
		"entity_ids": [
			"system.start",
			"station.main",
			"npc.kaelen",
			"gate.start.to_test",
		],
		"canon_facts": [{
			"fact_id": "fact.opening.kaelen_present",
			"subject_ids": ["npc.kaelen", "system.start"],
			"value": true,
		}],
	}


func _asset_registry() -> Dictionary:
	return {
		"document_type": SchemaType.ASSET_REGISTRY,
		"schema_version": 1,
		"ownership": SchemaType.PERMANENT,
		"id": "asset_registry.local.alpha",
		"campaign_id": "campaign.local.alpha",
		"assets": [{
			"asset_id": "asset.portrait.kaelen",
			"owner_entity_id": "npc.kaelen",
			"generator_type": "curated",
			"generator_version": "portrait_sheet_v1",
			"generation_seed": "fixed-kaelen",
			"provenance_hash": "sha256:example",
			"source_path": "res://assets/QuestGivers.png",
			"fallback_path": "",
			"validation_status": "approved",
			"rebuild_instruction": "Restore the curated portrait source.",
		}],
	}


func _checkpoint() -> Dictionary:
	return {
		"document_type": SchemaType.CHECKPOINT,
		"schema_version": 1,
		"ownership": SchemaType.REWINDABLE,
		"id": "checkpoint.local.alpha.initial",
		"campaign_id": "campaign.local.alpha",
		"timeline_id": "timeline.local.alpha",
		"chronicle_head_event_id": "event.local.alpha.start",
		"source_reason": "initial",
		"living": true,
		"transitional": false,
		"safe_location": {
			"type": "initial",
			"system_id": "system.start",
		},
		"state": {
			"player": {"credits": 50, "hull": 100},
			"mission": {},
			"reputation": {},
			"entities": {},
		},
	}


func _map_knowledge() -> Dictionary:
	return {
		"document_type": SchemaType.MAP_KNOWLEDGE,
		"schema_version": 1,
		"ownership": SchemaType.REWINDABLE,
		"id": "map_knowledge.local.alpha.initial",
		"campaign_id": "campaign.local.alpha",
		"checkpoint_id": "checkpoint.local.alpha.initial",
		"known_gate_ids": [],
		"rumored_gate_ids": [],
		"hidden_gate_ids": ["gate.start.to_test"],
		"blocked_gate_ids": [],
		"damaged_gate_ids": [],
	}


func _chronicle() -> Dictionary:
	return {
		"document_type": SchemaType.CHRONICLE_SEGMENT,
		"schema_version": 1,
		"ownership": SchemaType.APPEND_ONLY,
		"id": "chronicle.local.alpha.segment_000001",
		"campaign_id": "campaign.local.alpha",
		"timeline_id": "timeline.local.alpha",
		"events": [{
			"event_id": "event.local.alpha.start",
			"timeline_id": "timeline.local.alpha",
			"parent_event_id": "",
			"checkpoint_id": "checkpoint.local.alpha.initial",
			"event_type": "campaign_started",
			"subject_ids": ["campaign.local.alpha", "system.start"],
			"payload": {"opening": true},
			"sequence": 0,
		}],
	}


func _kaelen_meta() -> Dictionary:
	return {
		"document_type": SchemaType.KAELEN_META,
		"schema_version": 1,
		"ownership": SchemaType.META_MEMORY,
		"id": "kaelen_meta.local.alpha",
		"campaign_id": "campaign.local.alpha",
		"timeline_reversal_count": 0,
		"memories": [{
			"memory_id": "memory.local.alpha.opening",
			"source_timeline_id": "timeline.local.alpha",
			"source_checkpoint_id": "checkpoint.local.alpha.initial",
			"event_sequence": 0,
			"category": "observation",
			"fact_refs": ["fact.opening.kaelen_present"],
			"summary": "Shiny arrived in the opening system.",
			"timeline_status": "current",
		}],
	}


func _has_issue(
	issues: Array[Dictionary],
	code: String,
	path: String
) -> bool:
	for issue in issues:
		if issue.get("code") == code and issue.get("path") == path:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
