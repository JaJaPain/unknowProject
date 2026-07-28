class_name ChapterNarrativePacketStore
extends RefCounted

const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const DOCUMENT_VERSION := 1
const PACKETS_PATH := "chapter_narrative_packets.json"

const DEFAULT_OPPOSING_FORCE_DOSSIER := {
	"status": "unformed",
	"current_footprint": [],
	"identity": {"known": [], "unknown": []},
	"objectives": [],
	"capabilities": [],
	"limits": [],
	"chapter_move": "",
	"local_aftermath": [],
	"evidence_trail": [],
	"escalation_tier": 0,
}

var campaign_path: String
var data: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> RefCounted:
	var script: GDScript = load(
		"res://scripts/persistence/ChapterNarrativePacketStore.gd"
	)
	var store: RefCounted = script.new()
	store.campaign_path = path.trim_suffix("/")
	store._load_or_create()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func all_packets() -> Array:
	return (data.get("packets", []) as Array).duplicate(true)


func packet_ids() -> Array[String]:
	var ids: Array[String] = []
	for packet in all_packets():
		if packet is Dictionary:
			ids.append(str(packet.get("packet_id", "")))
	return ids


func append_packet(packet: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Chapter narrative packet store is invalid.")
	var packet_id := str(packet.get("packet_id", "")).strip_edges()
	if packet_id.is_empty():
		return _failure("Chapter narrative packet requires packet_id.")
	if packet_ids().has(packet_id):
		return _failure("Chapter narrative packet already exists: %s" % packet_id)
	var prepared := data.duplicate(true)
	var packets: Array = all_packets()
	packets.append(_normalized_packet(packet))
	prepared["packets"] = packets
	var committed := _commit(prepared, "chapter_packet_append")
	if not bool(committed.get("ok", false)):
		return committed
	data = prepared
	return {
		"ok": true,
		"packet_id": packet_id,
		"count": packets.size(),
	}


func latest_packet_for_chapter(chapter: int) -> Dictionary:
	var found: Dictionary = {}
	for packet in all_packets():
		if packet is Dictionary and int(packet.get("chapter", 0)) == chapter:
			found = (packet as Dictionary).duplicate(true)
	return found


func _load_or_create() -> void:
	var packets_path := "%s/%s" % [campaign_path, PACKETS_PATH]
	if not FileAccess.file_exists(packets_path):
		data = _default_document()
		var committed := _commit(data, "chapter_packets_bootstrap")
		if not bool(committed.get("ok", false)):
			validation.add_error(
				"chapter_packets_bootstrap_failed",
				str(committed.get("error", "Chapter packets could not be created.")),
				PACKETS_PATH
			)
		return
	var parsed := DomainJsonType.read_object(packets_path)
	validation.merge(parsed["validation"], "chapter_packets")
	if not validation.is_valid():
		return
	data = _migrate_legacy_document(parsed["data"])
	validation.merge(_validate_document(data), "chapter_packets")


func _commit(next_data: Dictionary, operation: String) -> Dictionary:
	return TransactionStoreType.commit_json_set(
		campaign_path,
		operation,
		{PACKETS_PATH: next_data},
		PACKETS_PATH,
		func(_path: String, value: Dictionary) -> ValidationResult:
			return _validate_document(value)
	)


static func _default_document() -> Dictionary:
	return {
		"schema_version": DOCUMENT_VERSION,
		"document_type": "chapter_narrative_packets",
		"packets": [],
	}


static func _migrate_legacy_document(source: Dictionary) -> Dictionary:
	var migrated := source.duplicate(true)
	var packets: Array = migrated.get("packets", []) \
		if migrated.get("packets", []) is Array else []
	var normalized_packets: Array = []
	for packet in packets:
		normalized_packets.append(
			_normalized_packet(packet as Dictionary) if packet is Dictionary else packet
		)
	migrated["packets"] = normalized_packets
	return migrated


static func _normalized_packet(packet: Dictionary) -> Dictionary:
	var normalized := packet.duplicate(true)
	normalized["attachment_beats"] = normalized.get("attachment_beats", []) \
		if normalized.get("attachment_beats", []) is Array else []
	normalized["opposing_force"] = _normalized_opposing_force_dossier(
		normalized.get("opposing_force", {})
	)
	return normalized


static func _normalized_opposing_force_dossier(value: Variant) -> Dictionary:
	var dossier: Dictionary = DEFAULT_OPPOSING_FORCE_DOSSIER.duplicate(true)
	if not value is Dictionary:
		return dossier
	var source: Dictionary = value
	dossier["status"] = str(source.get("status", dossier["status"])).strip_edges()
	if dossier["status"].is_empty():
		dossier["status"] = "unformed"
	for field in ["current_footprint", "objectives", "capabilities", "limits", "local_aftermath", "evidence_trail"]:
		dossier[field] = source.get(field, []) if source.get(field, []) is Array else []
	var identity_source: Dictionary = source.get("identity", {}) \
		if source.get("identity", {}) is Dictionary else {}
	dossier["identity"] = {
		"known": identity_source.get("known", []) if identity_source.get("known", []) is Array else [],
		"unknown": identity_source.get("unknown", []) if identity_source.get("unknown", []) is Array else [],
	}
	dossier["chapter_move"] = str(source.get("chapter_move", "")).strip_edges()
	dossier["escalation_tier"] = clampi(int(source.get("escalation_tier", 0)), 0, 5)
	return dossier


static func _validate_document(value: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(value.get("schema_version", 0)) != DOCUMENT_VERSION:
		result.add_error(
			"invalid_chapter_packets_version",
			"Chapter narrative packet document schema version is invalid.",
			"schema_version"
		)
	if str(value.get("document_type", "")) != "chapter_narrative_packets":
		result.add_error(
			"invalid_chapter_packets_type",
			"Chapter narrative packet document type is invalid.",
			"document_type"
		)
	if not value.get("packets", []) is Array:
		result.add_error(
			"invalid_chapter_packets_array",
			"Chapter narrative packet document requires a packets array.",
			"packets"
		)
		return result
	var seen := {}
	var packets: Array = value.get("packets", [])
	for index in range(packets.size()):
		if not packets[index] is Dictionary:
			result.add_error(
				"invalid_chapter_packet",
				"Chapter narrative packet must be an object.",
				"packets.%d" % index
			)
			continue
		var packet: Dictionary = packets[index]
		var packet_id := str(packet.get("packet_id", "")).strip_edges()
		if packet_id.is_empty():
			result.add_error(
				"missing_chapter_packet_id",
				"Chapter narrative packet requires packet_id.",
				"packets.%d.packet_id" % index
			)
		elif seen.has(packet_id):
			result.add_error(
				"duplicate_chapter_packet_id",
				"Chapter narrative packet IDs must be append-only and unique.",
				"packets.%d.packet_id" % index
			)
		seen[packet_id] = true
		if int(packet.get("chapter", 0)) < 1:
			result.add_error(
				"invalid_chapter_packet_chapter",
				"Chapter narrative packet chapter must be at least 1.",
				"packets.%d.chapter" % index
			)
		if not packet.get("attachment_beats", []) is Array:
			result.add_error(
				"invalid_chapter_attachment_beats",
				"Chapter narrative packet attachment_beats must be an array.",
				"packets.%d.attachment_beats" % index
			)
		_validate_opposing_force_dossier(
			packet.get("opposing_force", {}),
			result,
			"packets.%d.opposing_force" % index
		)
	return result


static func _validate_opposing_force_dossier(
	value: Variant,
	result: ValidationResult,
	prefix: String
) -> void:
	if not value is Dictionary:
		result.add_error("invalid_opposing_force_dossier", "Opposing-force dossier must be an object.", prefix)
		return
	var dossier: Dictionary = value
	if not ["unformed", "active"].has(str(dossier.get("status", ""))):
		result.add_error("invalid_opposing_force_status", "Opposing-force dossier status must be unformed or active.", "%s.status" % prefix)
	for field in ["current_footprint", "objectives", "capabilities", "limits", "local_aftermath", "evidence_trail"]:
		if not dossier.get(field, []) is Array:
			result.add_error("invalid_opposing_force_array", "Opposing-force dossier field '%s' must be an array." % field, "%s.%s" % [prefix, field])
	var identity: Variant = dossier.get("identity", {})
	if not identity is Dictionary:
		result.add_error("invalid_opposing_force_identity", "Opposing-force dossier identity must be an object.", "%s.identity" % prefix)
	elif not (identity as Dictionary).get("known", []) is Array or not (identity as Dictionary).get("unknown", []) is Array:
		result.add_error("invalid_opposing_force_identity_array", "Opposing-force dossier identity fields must be arrays.", "%s.identity" % prefix)
	if not dossier.get("chapter_move", "") is String:
		result.add_error("invalid_opposing_force_chapter_move", "Opposing-force dossier chapter_move must be a string.", "%s.chapter_move" % prefix)
	if int(dossier.get("escalation_tier", -1)) < 0 or int(dossier.get("escalation_tier", 6)) > 5:
		result.add_error("invalid_opposing_force_escalation_tier", "Opposing-force escalation_tier must be between 0 and 5.", "%s.escalation_tier" % prefix)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
