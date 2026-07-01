class_name LLMDialogueContentRegistry
extends RefCounted

## Human-editable content accessor for LLM NPC dialogue.
##
## Loads res://data/content/llm_dialogue_content.json and exposes typed helpers
## so gameplay code does not dig through raw JSON. This registry owns WORDS
## (examples, tone, nickname rules, fallback lines) — it never owns mechanics.
## Reward formulas, ore amounts, kill counts, and spawns stay in code and are
## validated there. See docs/llm_dialogue_content_editing.md for editing rules.
##
## Design contract (see docs/plan_llm_dialogue_content_registry.md):
##  - Missing or malformed sections fall back to built-in minimal defaults.
##  - Bad JSON must never crash the game.
##  - Unknown fields are ignored so the file can evolve.
##
## Base + override safety net:
##  - BASE_PATH is the hand-authored, committed, trusted content. The in-game
##    editor never writes it.
##  - OVERRIDE_PATH is a DELTA the DevPanel writes — only the buckets you edited.
##    It is deep-merged on top of the base at load time, so runtime uses your
##    edits while the base stays clean and reviewable. A malformed override is
##    ignored (base still runs). Review = diff base vs override; promote = fold
##    the override into the base and delete it; discard = delete the override.

const BASE_PATH := "res://data/content/llm_dialogue_content.json"
const OVERRIDE_PATH := "res://data/content/llm_dialogue_content.override.json"
const SUPPORTED_SCHEMA_VERSION := 1

static var _shared: LLMDialogueContentRegistry

var base_data: Dictionary = {}       # trusted, from BASE_PATH
var override_data: Dictionary = {}   # delta, from OVERRIDE_PATH (panel edits)
var data: Dictionary = {}            # merged live view everything reads
var validation := ValidationResult.new()
var override_loaded: bool = false    # true if a valid override file was merged


static func shared() -> LLMDialogueContentRegistry:
	if _shared == null:
		_shared = LLMDialogueContentRegistry.new()
		_shared._load()
	return _shared


## Test/hot-reload hook: drop the cached instance so the next shared() reloads.
static func reset_shared() -> void:
	_shared = null


func is_valid() -> bool:
	return validation.is_valid()


## True if an override delta is currently in effect (loaded from disk or edited
## this session but not yet discarded).
func has_override() -> bool:
	return not override_data.is_empty()


func _load() -> void:
	var parsed := DomainJson.read_object(BASE_PATH)
	validation.merge(parsed["validation"], "llm_dialogue_content")
	if not parsed["validation"].is_valid():
		# Bad/missing base: keep data empty. Every accessor falls back to a
		# built-in default, so the game keeps working with code-side content.
		return
	var loaded: Dictionary = parsed["data"]
	var version := int(loaded.get("schema_version", 0))
	if version != SUPPORTED_SCHEMA_VERSION:
		validation.add_error(
			"unsupported_schema_version",
			"Expected schema_version %d, got %d." % [SUPPORTED_SCHEMA_VERSION, version],
			"schema_version"
		)
		return
	base_data = loaded
	_load_override()
	_rebuild()


## Best-effort load of the override delta. Never fails the registry: a missing
## file is normal; a malformed one is warned about and skipped so the base runs.
func _load_override() -> void:
	override_data = {}
	override_loaded = false
	if not FileAccess.file_exists(OVERRIDE_PATH):
		return
	var parsed := DomainJson.read_object(OVERRIDE_PATH)
	if not parsed["validation"].is_valid():
		validation.add_warning(
			"override_ignored",
			"Override file is malformed and was ignored; base content is in use.",
			OVERRIDE_PATH
		)
		return
	override_data = parsed["data"]
	override_loaded = true


## Recompute the merged live view. Honors override_enabled so the toggle can hide
## the delta without deleting it.
func _rebuild() -> void:
	if override_enabled and not override_data.is_empty():
		data = _deep_merge(base_data, override_data)
	else:
		data = base_data.duplicate(true)


## Recursive merge: override wins at leaves; dict+dict recurse; arrays and scalars
## are replaced wholesale (editing a dialogue list replaces the whole list).
static func _deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in over:
		var over_value: Variant = over[key]
		if over_value is Dictionary and out.get(key) is Dictionary:
			out[key] = _deep_merge(out[key], over_value)
		elif over_value is Dictionary or over_value is Array:
			out[key] = (over_value as Variant).duplicate(true)
		else:
			out[key] = over_value
	return out


# ── Quest generation content ─────────────────────────────────────────────────

## Returns the few-shot example bundle for one agent voice × objective type.
## Shape mirrors the legacy LLMInterface._get_type_examples() contract:
##   { "dialogues": Array[String], "response_1": String,
##     "response_2": String, "response_3": String }
## agent_key is one of: zenith, aurelia, vanguard, neutral.
## Returns {} when the section is missing so callers can use their own fallback.
func quest_examples(agent_key: String, objective_type: String) -> Dictionary:
	var mission := _mission_type_section(objective_type)
	var by_agent: Variant = mission.get("examples_by_agent", {})
	if not by_agent is Dictionary:
		return {}
	var bundle: Variant = (by_agent as Dictionary).get(agent_key, {})
	if not bundle is Dictionary or (bundle as Dictionary).is_empty():
		return {}
	var out := {}
	var dialogues: Variant = (bundle as Dictionary).get("dialogues", [])
	out["dialogues"] = (dialogues as Array).duplicate() if dialogues is Array else []
	out["response_1"] = str((bundle as Dictionary).get("response_1", ""))
	out["response_2"] = str((bundle as Dictionary).get("response_2", ""))
	out["response_3"] = str((bundle as Dictionary).get("response_3", ""))
	return out


## Returns the dummy-name/fact instruction string appended to the quest prompt
## for one objective type. Returns "" when the section is missing.
func quest_dummy_constraints(objective_type: String) -> String:
	var mission := _mission_type_section(objective_type)
	return str(mission.get("dummy_constraints", ""))


# ── Override toggle ──────────────────────────────────────────────────────────
# The DevPanel can flip the override on/off live so you can A/B compare your
# edits against the trusted base without deleting anything.
var override_enabled: bool = true


## Turn the override delta on/off for the live view. Does not touch the file.
func set_override_enabled(enabled: bool) -> void:
	override_enabled = enabled
	_rebuild()


# ── Mutation + persistence (DevPanel content editor) ─────────────────────────
# Edits are recorded into the OVERRIDE delta (override_data), never into the
# trusted base. save() writes only that delta to OVERRIDE_PATH. Dev-tool only:
# writing to res:// works from the project folder, not from an exported build.

## Walk/create a nested dict path inside override_data and return the leaf dict.
## Dictionaries are references, so mutating the result mutates override_data.
func _override_branch(path: PackedStringArray) -> Dictionary:
	if override_data.get("schema_version") != SUPPORTED_SCHEMA_VERSION:
		override_data["schema_version"] = SUPPORTED_SCHEMA_VERSION
	var node := override_data
	for key in path:
		if not node.has(key) or not node[key] is Dictionary:
			node[key] = {}
		node = node[key]
	return node


## Record an edited quest bucket into the override delta and refresh the live
## view. Structure is created as needed. Turning override on makes it live now.
func set_quest_content(
	agent_key: String,
	objective_type: String,
	dialogues: Array,
	response_1: String,
	response_2: String,
	response_3: String,
	dummy_constraints: String
) -> void:
	var section := _override_branch(
		PackedStringArray(["quest_generation", "mission_types", objective_type])
	)
	section["dummy_constraints"] = dummy_constraints
	if not section.has("examples_by_agent") or not section["examples_by_agent"] is Dictionary:
		section["examples_by_agent"] = {}
	var by_agent: Dictionary = section["examples_by_agent"]
	by_agent[agent_key] = {
		"dialogues": dialogues.duplicate(),
		"response_1": response_1,
		"response_2": response_2,
		"response_3": response_3,
	}
	_rebuild()


## Pretty-print the override delta to OVERRIDE_PATH. The base file is never
## touched. Returns a ValidationResult so the caller can surface write/parse
## errors. Saving with an empty delta deletes the override file instead.
func save() -> ValidationResult:
	var result := ValidationResult.new()
	if override_data.is_empty():
		discard_override()
		return result
	var text := DomainJson.stringify(override_data, true)
	var file := FileAccess.open(OVERRIDE_PATH, FileAccess.WRITE)
	if file == null:
		result.add_error(
			"save_failed",
			"Could not open override file for writing (exported build?).",
			OVERRIDE_PATH
		)
		return result
	file.store_string(text)
	file.close()
	override_loaded = true
	# Round-trip check: parse what we just wrote.
	var parsed := DomainJson.parse_object(text, OVERRIDE_PATH)
	result.merge(parsed["validation"], "resave")
	return result


## Drop the override delta entirely: clear it in memory, delete the file, and
## fall back to the trusted base. Leaves the base file untouched.
func discard_override() -> void:
	override_data = {}
	override_loaded = false
	if FileAccess.file_exists(OVERRIDE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDE_PATH))
	_rebuild()


## Discard in-memory edits and re-read base + override from disk.
func reload() -> void:
	base_data = {}
	override_data = {}
	data = {}
	validation = ValidationResult.new()
	_load()


func _mission_type_section(objective_type: String) -> Dictionary:
	var quest: Variant = data.get("quest_generation", {})
	if not quest is Dictionary:
		return {}
	var mission_types: Variant = (quest as Dictionary).get("mission_types", {})
	if not mission_types is Dictionary:
		return {}
	var section: Variant = (mission_types as Dictionary).get(objective_type, {})
	return section if section is Dictionary else {}


# ── Global / speaker rules ───────────────────────────────────────────────────
# Currently documentation for editors and future prompt wiring. The live persona
# strings still live in LLMInterface.gd; these accessors let tests assert the
# JSON stays consistent and give future callers a typed entry point.

func global_non_kaelen_rules() -> Dictionary:
	var rules: Variant = data.get("global_rules", {})
	return (rules as Dictionary).duplicate(true) if rules is Dictionary else {}


func speaker_tone(speaker_id: String) -> String:
	return str(_speaker(speaker_id).get("tone_card", ""))


func speaker_address_rule(speaker_id: String) -> String:
	return str(_speaker(speaker_id).get("address_rule", ""))


func _speaker(speaker_id: String) -> Dictionary:
	var speakers: Variant = data.get("speakers", {})
	if not speakers is Dictionary:
		return {}
	var speaker: Variant = (speakers as Dictionary).get(speaker_id, {})
	return speaker if speaker is Dictionary else {}


## Full copy of one speaker card (address_rule, tone_card, voice_profile_id).
func speaker(speaker_id: String) -> Dictionary:
	return _speaker(speaker_id).duplicate(true)


## Record edited speaker-card text into the override delta. voice_profile_id is
## left as-is (it belongs to the voice/content registry, not the dialogue text).
func set_speaker(speaker_id: String, address_rule: String, tone_card: String) -> void:
	var speakers := _override_branch(PackedStringArray(["speakers"]))
	var base_entry := _speaker(speaker_id)
	var entry: Dictionary = base_entry.duplicate(true)
	entry["address_rule"] = address_rule
	entry["tone_card"] = tone_card
	speakers[speaker_id] = entry
	_rebuild()


## Record an edited global nickname/address rule block into the override delta.
func set_global_rules(rules: Dictionary) -> void:
	if override_data.get("schema_version") != SUPPORTED_SCHEMA_VERSION:
		override_data["schema_version"] = SUPPORTED_SCHEMA_VERSION
	override_data["global_rules"] = rules.duplicate(true)
	_rebuild()
