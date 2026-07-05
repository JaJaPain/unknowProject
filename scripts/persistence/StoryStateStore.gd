class_name StoryStateStore
extends RefCounted

const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const DOCUMENT_VERSION := 1
const STATE_PATH := "story_state.json"

var campaign_path: String
var data: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> StoryStateStore:
	var store := StoryStateStore.new()
	store.campaign_path = path.trim_suffix("/")
	store._load_or_create()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func prompt_context() -> String:
	if not is_valid() or data.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("Story State:")
	lines.append("- Chapter: %d" % int(data.get("chapter", 1)))
	var tensions: Array = data.get("active_tensions", [])
	if not tensions.is_empty():
		lines.append("- Active tensions: %s" % ", ".join(tensions))
	var known: Array = data.get("player_knows", [])
	if not known.is_empty():
		lines.append("- Player knows: %s" % ", ".join(known))
	var foreshadow := str(data.get("current_foreshadow", "")).strip_edges()
	if not foreshadow.is_empty():
		lines.append("- Foreshadow hint: %s" % foreshadow)
	var mood := str(data.get("kaelen_current_mood", "")).strip_edges()
	if not mood.is_empty():
		lines.append("- Kaelen mood: %s" % mood)
	var hooks: Array = data.get("pending_hooks", [])
	if not hooks.is_empty():
		lines.append("- Open story threads: %s" % ", ".join(hooks))
	return "\n".join(lines)


func save_state(next_data: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Story state store is invalid.")
	var prepared := next_data.duplicate(true)
	prepared["schema_version"] = DOCUMENT_VERSION
	prepared["document_type"] = "story_state"
	var committed := _commit(prepared, "story_state_save")
	if not bool(committed.get("ok", false)):
		return committed
	data = prepared
	return {"ok": true}


func _load_or_create() -> void:
	var state_path := "%s/%s" % [campaign_path, STATE_PATH]
	if not FileAccess.file_exists(state_path):
		data = _default_state()
		var committed := _commit(data, "story_state_bootstrap")
		if not bool(committed.get("ok", false)):
			validation.add_error(
				"story_state_bootstrap_failed",
				str(committed.get("error", "Story state could not be created.")),
				STATE_PATH
			)
		return
	var result := DomainJsonType.read_object(state_path)
	validation.merge(result["validation"], "story_state")
	if not validation.is_valid():
		return
	data = result["data"]
	validation.merge(_validate_data(data), "story_state")


func _commit(next_data: Dictionary, operation: String) -> Dictionary:
	return TransactionStoreType.commit_json_set(
		campaign_path,
		operation,
		{STATE_PATH: next_data},
		STATE_PATH,
		func(_path: String, value: Dictionary) -> ValidationResult:
			return _validate_data(value)
	)


static func _default_state() -> Dictionary:
	return {
		"schema_version": DOCUMENT_VERSION,
		"document_type": "story_state",
		"chapter": 1,
		"active_tensions": [],
		"player_knows": [],
		"player_does_not_know_yet": [],
		"pending_hooks": [],
		"current_foreshadow": "",
		"kaelen_current_mood": "guarded",
		"kaelen_hidden_angle": "",
		"intro_conversation_had": false,
		"intro_agent_visited": false,
		"intro_quest_delivered": false,
		"hinted_lounge_rumors": [],
		"agent_cooldown_until_minute": 0,
		"agent_cooldown_message_index": 0,
		"agent_contracts_since_cooldown": 0,
		"faction_pressure": {},
		"player_choices": [],
		"kaelen_hidden_hints": [],
		"kaelen_hints_delivered": [],
		"kaelen_hint_style": "",
		"nova_quirk": "",
		"nova_memory_flicker": "",
		"nova_glitch_hints": [],
		"ambient_used_topics": [],
		"lounge_warmth": {},
		"bible_seeded": false,
		"act_1_outline_consumed_index": 0,
		"story_arcs_consumed_index": 0,
		"rumor_trails_consumed_index": 0,
		"regeneration_fallback_count": 0,
	}


static func _validate_data(value: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(value.get("schema_version", 0)) != DOCUMENT_VERSION:
		result.add_error(
			"invalid_story_state_version",
			"Story state schema version is invalid.",
			"schema_version"
		)
	if str(value.get("document_type", "")) != "story_state":
		result.add_error(
			"invalid_story_state_type",
			"Story state document type is invalid.",
			"document_type"
		)
	if int(value.get("chapter", 0)) < 1:
		result.add_error(
			"invalid_story_state_chapter",
			"Story state chapter must be at least 1.",
			"chapter"
		)
	for field in ["active_tensions", "player_knows", "player_does_not_know_yet", "pending_hooks", "hinted_lounge_rumors"]:
		if not value.get(field, []) is Array:
			result.add_error(
				"invalid_story_state_array",
				"Story state field '%s' must be an array." % field,
				field
			)
	return result


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
