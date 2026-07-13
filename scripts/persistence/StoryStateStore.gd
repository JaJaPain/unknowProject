class_name StoryStateStore
extends RefCounted

const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)
const ContextBlockBuilderType := preload(
	"res://scripts/ai/ContextBlockBuilder.gd"
)

const DOCUMENT_VERSION := 2
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
	return ContextBlockBuilderType.story_state_public_block(data)


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
	var raw_data: Dictionary = result["data"]
	data = _migrate_legacy_state(raw_data)
	if JSON.stringify(data) != JSON.stringify(raw_data):
		var committed := _commit(data, "story_state_migrate")
		if not bool(committed.get("ok", false)):
			validation.add_error(
				"story_state_migration_failed",
				str(committed.get("error", "Story state migration failed.")),
				STATE_PATH
			)
			return
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
		"kaelen_relationship": {
			"respect": 0,
			"band": "neutral",
			"revision": 0,
			"last_outcome": "",
			"last_mission_title": "",
			"recent_reason": "",
			"last_changed_minute": 0,
		},
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
		"screenshot_systems_seen": [],
		"screenshot_stations_seen": [],
		"bible_seeded": false,
		"act_1_outline_consumed_index": 0,
		"story_arcs_consumed_index": 0,
		"rumor_trails_consumed_index": 0,
		"regeneration_fallback_count": 0,
		"story_revision": 0,
		"knowledge_revision": 0,
		"mission_history_revision": 0,
		"knowledge_states": {},
		"beat_states": {},
		"chapter_packet_generation_queued": {},
		"declined_offer_cooldowns": {},
		"story_consequences": [],
		"asked_question_intents": [],
	}


static func _migrate_legacy_state(source: Dictionary) -> Dictionary:
	var migrated := _default_state()
	for key in source.keys():
		migrated[key] = source[key]
	migrated["schema_version"] = DOCUMENT_VERSION
	migrated["document_type"] = "story_state"
	if not migrated.get("player_knows", []) is Array:
		migrated["player_knows"] = []
	for revision_field in [
		"story_revision",
		"knowledge_revision",
		"mission_history_revision",
	]:
		migrated[revision_field] = maxi(0, int(migrated.get(revision_field, 0)))
	if not migrated.get("knowledge_states", {}) is Dictionary:
		migrated["knowledge_states"] = {}
	if not migrated.get("beat_states", {}) is Dictionary:
		migrated["beat_states"] = {}
	if not migrated.get("chapter_packet_generation_queued", {}) is Dictionary:
		migrated["chapter_packet_generation_queued"] = {}
	if not migrated.get("declined_offer_cooldowns", {}) is Dictionary:
		migrated["declined_offer_cooldowns"] = {}
	if not migrated.get("kaelen_relationship", {}) is Dictionary:
		migrated["kaelen_relationship"] = _default_state()["kaelen_relationship"]
	else:
		migrated["kaelen_relationship"] = _migrate_kaelen_relationship(
			migrated.get("kaelen_relationship", {})
		)
	if not migrated.get("story_consequences", []) is Array:
		migrated["story_consequences"] = []
	_backfill_legacy_player_knows(migrated)
	return migrated


static func legacy_player_knows_fact_id(text: String) -> String:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return ""
	return "fact.legacy_player_knows.%s" % clean_text.sha256_text().substr(0, 16)


static func _backfill_legacy_player_knows(state: Dictionary) -> void:
	var player_knows: Array = state.get("player_knows", [])
	if player_knows.is_empty():
		return
	var knowledge_states: Dictionary = state.get("knowledge_states", {})
	for item in player_knows:
		var text := str(item).strip_edges()
		if text.is_empty():
			continue
		var fact_id := legacy_player_knows_fact_id(text)
		if fact_id.is_empty() or knowledge_states.has(fact_id):
			continue
		knowledge_states[fact_id] = {
			"state": "known",
			"source": "legacy_player_knows",
			"learned_at_minute": 0,
			"confidence": "legacy",
			"legacy_text": text,
		}
	state["knowledge_states"] = knowledge_states


static func _migrate_kaelen_relationship(source: Dictionary) -> Dictionary:
	var relationship: Dictionary = _default_state()["kaelen_relationship"].duplicate(true)
	for key in source.keys():
		relationship[key] = source[key]
	relationship["respect"] = clampi(int(relationship.get("respect", 0)), -6, 6)
	relationship["revision"] = maxi(0, int(relationship.get("revision", 0)))
	relationship["last_changed_minute"] = maxi(
		0,
		int(relationship.get("last_changed_minute", 0))
	)
	relationship["band"] = _kaelen_relationship_band_for_respect(
		int(relationship.get("respect", 0))
	)
	return relationship


static func _kaelen_relationship_band_for_respect(respect: int) -> String:
	if respect <= -4:
		return "strained"
	if respect <= -1:
		return "wary"
	if respect >= 5:
		return "favored"
	if respect >= 2:
		return "reliable"
	return "neutral"


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
	for revision_field in [
		"story_revision",
		"knowledge_revision",
		"mission_history_revision",
	]:
		if not _is_non_negative_integer(value.get(revision_field, 0)):
			result.add_error(
				"invalid_story_state_revision",
				(
					"Story state field '%s' must be a non-negative integer."
					% revision_field
				),
				revision_field
			)
	for dictionary_field in [
		"knowledge_states",
		"beat_states",
		"chapter_packet_generation_queued",
		"declined_offer_cooldowns",
		"kaelen_relationship",
	]:
		if not value.get(dictionary_field, {}) is Dictionary:
			result.add_error(
				"invalid_story_state_dictionary",
				"Story state field '%s' must be a dictionary." % dictionary_field,
				dictionary_field
			)
	for field in [
		"active_tensions",
		"player_knows",
		"player_does_not_know_yet",
		"pending_hooks",
		"hinted_lounge_rumors",
		"asked_question_intents",
		"story_consequences",
	]:
		if not value.get(field, []) is Array:
			result.add_error(
				"invalid_story_state_array",
				"Story state field '%s' must be an array." % field,
				field
			)
	return result


static func _is_non_negative_integer(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var numeric := float(value)
	return numeric >= 0.0 and is_equal_approx(numeric, floorf(numeric))


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
