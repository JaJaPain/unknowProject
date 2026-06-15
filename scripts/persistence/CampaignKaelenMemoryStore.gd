class_name CampaignKaelenMemoryStore
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

const MAX_CURRENT_MEMORIES := 64
const MAX_DISCARDED_MEMORIES := 32
const ALLOWED_CATEGORIES: Array[String] = [
	"observation",
	"relationship",
	"death",
]
const ALLOWED_DEATH_CATEGORIES: Array[String] = [
	"combat",
	"collision",
	"environment",
	"unknown",
]

var campaign_path: String
var campaign: Dictionary = {}
var data: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> CampaignKaelenMemoryStore:
	var store := CampaignKaelenMemoryStore.new()
	store.campaign_path = path.trim_suffix("/")
	store._load()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func reversal_count() -> int:
	return int(data.get("timeline_reversal_count", 0))


func current_memories() -> Array:
	var output: Array = []
	for memory in data.get("memories", []):
		if memory is Dictionary \
				and memory.get("timeline_status", "") == "current":
			output.append((memory as Dictionary).duplicate(true))
	return output


func diagnostic_discarded_memories() -> Array:
	var output: Array = []
	for memory in data.get("memories", []):
		if memory is Dictionary \
				and memory.get("timeline_status", "") == "discarded":
			output.append((memory as Dictionary).duplicate(true))
	return output


func append_memory(
	category: String,
	summary: String,
	fact_refs: Array,
	timeline_id: String,
	checkpoint_id: String,
	event_sequence: int,
	death_category: String = ""
) -> Dictionary:
	if not is_valid():
		return _failure("Kaelen memory store is invalid.")
	if category not in ALLOWED_CATEGORIES \
			or summary.strip_edges().is_empty() \
			or not DomainIdType.is_valid(timeline_id, "timeline") \
			or not DomainIdType.is_valid(checkpoint_id, "checkpoint") \
			or event_sequence < 0:
		return _failure("Kaelen memory is not approved for retention.")
	if category == "death":
		if death_category not in ALLOWED_DEATH_CATEGORIES:
			return _failure("Death memory requires a verified category.")
	elif not death_category.is_empty():
		return _failure("Non-death memory cannot contain a death category.")
	for fact_id in fact_refs:
		if not DomainIdType.is_valid(fact_id, "fact"):
			return _failure("Kaelen memory contains an invalid fact reference.")
	var next_sequence := int(data.get("next_memory_sequence", 0))
	var memory := {
		"memory_id": _new_id("memory", next_sequence),
		"source_timeline_id": timeline_id,
		"source_checkpoint_id": checkpoint_id,
		"event_sequence": event_sequence,
		"local_sequence": next_sequence,
		"category": category,
		"fact_refs": fact_refs.duplicate(true),
		"summary": summary.strip_edges(),
		"timeline_status": "current",
	}
	if category == "death":
		memory["death_category"] = death_category
	var next_data: Dictionary = data.duplicate(true)
	var memories: Array = next_data.get("memories", []).duplicate(true)
	memories.append(memory)
	next_data["memories"] = _bounded_memories(memories)
	next_data["next_memory_sequence"] = next_sequence + 1
	var committed := _commit(next_data, "kaelen_memory_append")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "memory": memory.duplicate(true)}


func classify_rollback(
	timeline_id: String,
	checkpoint_id: String,
	event_sequence: int
) -> Dictionary:
	if not is_valid() \
			or not DomainIdType.is_valid(timeline_id, "timeline") \
			or not DomainIdType.is_valid(checkpoint_id, "checkpoint") \
			or event_sequence < 0:
		return _failure("Rollback memory boundary is invalid.")
	var next_data: Dictionary = data.duplicate(true)
	var memories: Array = next_data.get("memories", []).duplicate(true)
	var archived := 0
	for index in range(memories.size()):
		if not memories[index] is Dictionary:
			continue
		var memory: Dictionary = memories[index].duplicate(true)
		if memory.get("timeline_status", "") == "current" \
				and int(memory.get("event_sequence", -1)) > event_sequence:
			memory["timeline_status"] = "discarded"
			memories[index] = memory
			archived += 1
	if archived == 0:
		return {"ok": true, "archived": 0, "reversal_counted": false}
	next_data["timeline_reversal_count"] = reversal_count() + 1
	next_data["memories"] = _bounded_memories(memories)
	var committed := _commit(next_data, "kaelen_memory_rollback")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {
		"ok": true,
		"archived": archived,
		"reversal_counted": true,
		"checkpoint_id": checkpoint_id,
	}


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
	var memory_result := DomainJsonType.read_object(
		"%s/kaelen_meta.json" % campaign_path
	)
	validation.merge(memory_result["validation"], "kaelen_meta")
	if validation.is_valid():
		data = memory_result["data"]
		validation.merge(
			SchemaType.validate_document(data),
			"kaelen_meta"
		)
	if validation.is_valid() \
			and str(data.get("campaign_id", "")) \
				!= str(campaign.get("id", "")):
		validation.add_error(
			"kaelen_campaign_mismatch",
			"Kaelen memory belongs to a different campaign.",
			"campaign_id"
		)
	if validation.is_valid() and not data.has("next_memory_sequence"):
		data["next_memory_sequence"] = data.get("memories", []).size()


func _commit(next_data: Dictionary, operation: String) -> Dictionary:
	return TransactionStoreType.commit_json_set(
		campaign_path,
		operation,
		{"kaelen_meta.json": next_data},
		"kaelen_meta.json",
		func(_path: String, value: Dictionary) -> ValidationResult:
			return SchemaType.validate_document(value)
	)


func _bounded_memories(memories: Array) -> Array:
	var current: Array = []
	var discarded: Array = []
	for memory in memories:
		if not memory is Dictionary:
			continue
		if memory.get("timeline_status", "") == "discarded":
			discarded.append(memory)
		else:
			current.append(memory)
	current.sort_custom(_sequence_less)
	discarded.sort_custom(_sequence_less)
	while current.size() > MAX_CURRENT_MEMORIES:
		current.pop_front()
	while discarded.size() > MAX_DISCARDED_MEMORIES:
		discarded.pop_front()
	return current + discarded


static func _sequence_less(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("local_sequence", 0)) \
		< int(right.get("local_sequence", 0))


static func _new_id(id_namespace: String, sequence: int) -> String:
	var entropy := "%s|%s|%d" % [
		Time.get_ticks_usec(),
		Crypto.new().generate_random_bytes(12).hex_encode(),
		sequence,
	]
	return "%s.local.%s" % [
		id_namespace,
		entropy.sha256_text().substr(0, 24),
	]


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
