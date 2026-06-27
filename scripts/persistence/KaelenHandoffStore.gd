class_name KaelenHandoffStore
extends RefCounted

const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const DOCUMENT_VERSION := 1
const STORE_PATH := "kaelen_handoffs.json"

var campaign_path: String
var _pools: Dictionary = {}   # { agent_name: Array[String] }
var _valid: bool = false


static func open(path: String) -> KaelenHandoffStore:
	var store := KaelenHandoffStore.new()
	store.campaign_path = path.trim_suffix("/")
	store._load_or_create()
	return store


func is_valid() -> bool:
	return _valid


func draw(agent_name: String) -> String:
	var pool: Array = _pools.get(agent_name, [])
	if pool.is_empty():
		return ""
	var line: String = pool.pop_front()
	_pools[agent_name] = pool
	_commit()
	return line


func pool_size(agent_name: String) -> int:
	return (_pools.get(agent_name, []) as Array).size()


func refill(agent_name: String, lines: Array) -> void:
	_pools[agent_name] = lines.duplicate()
	_commit()


func _load_or_create() -> void:
	var file_path := "%s/%s" % [campaign_path, STORE_PATH]
	if not FileAccess.file_exists(file_path):
		_pools = {}
		_valid = true
		_commit()
		return
	var result := DomainJsonType.read_object(file_path)
	var validation: ValidationResult = result["validation"]
	if not validation.is_valid():
		push_warning("[KaelenHandoffStore] Failed to load: %s" % validation.format_errors())
		_valid = false
		return
	var data: Dictionary = result["data"]
	if str(data.get("document_type", "")) != "kaelen_handoffs":
		push_warning("[KaelenHandoffStore] Wrong document_type in %s" % file_path)
		_valid = false
		return
	_pools = data.get("pools", {}).duplicate(true)
	_valid = true


func _commit() -> void:
	var payload := {
		"schema_version": DOCUMENT_VERSION,
		"document_type": "kaelen_handoffs",
		"pools": _pools.duplicate(true),
	}
	TransactionStoreType.commit_json_set(
		campaign_path,
		"kaelen_handoffs_save",
		{STORE_PATH: payload},
		STORE_PATH,
		func(_path: String, _value: Dictionary) -> ValidationResult:
			return ValidationResultType.new()
	)
