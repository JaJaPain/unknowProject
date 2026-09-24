class_name PremiseCardLibrary
extends RefCounted

## The approved premise-card deck (story skeletons; see
## docs/gemini_prompts/premise_card_prompt.md for the format).
##
## Cards are authored and validated offline by
## tools/premise_cards/validate_premise_cards.py. This loader repeats only the
## checks the runtime depends on, and skips a bad card rather than rejecting the
## deck: one malformed card must never take the whole story system down.

const DEFAULT_DIR := "res://data/content/premise_cards/approved"
const SUPPORTED_SCHEMA_VERSION := 1

const ValidationResultType := preload("res://scripts/domain/ValidationResult.gd")

## Card mission verb -> existing objective type (MissionObjectiveDefinition).
const VERB_TO_OBJECTIVE := {
	"kill_ships": "KILL_SHIPS",
	"comms_reversal": "TARGET_WITH_COMMS_REVERSAL",
	"recover_combat_drop": "RECOVER_COMBAT_DROP",
	"deliver_ore": "DELIVER_ORE",
	"delivery_courier": "DELIVERY_COURIER",
	"purchase_delivery": "PURCHASE_DELIVERY",
	"pickup_special": "PICKUP_SPECIAL",
	"investigate_signal": "INVESTIGATE_SIGNAL",
}

const SCALES := ["personal", "local", "regional"]

var cards: Dictionary = {}          # String id -> Dictionary (the card)
var skipped: Dictionary = {}        # String id or file -> String reason


func load_from_dir(dir_path: String = DEFAULT_DIR) -> ValidationResult:
	var result := ValidationResultType.new()
	cards = {}
	skipped = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		result.add_error("missing_deck", "No premise card folder at %s." % dir_path, dir_path)
		return result
	var names := dir.get_files()
	names.sort()
	var loaded: Array = []
	for file_name in names:
		# Exported builds may list "name.json.remap"-style entries; only read JSON.
		if not file_name.ends_with(".json"):
			continue
		var path := dir_path.path_join(file_name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			skipped[file_name] = "unreadable"
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			loaded.append(parsed)
		elif parsed is Array:
			loaded.append_array(parsed)
		else:
			skipped[file_name] = "not a JSON object or array"
	result.merge(load_from_array(loaded))
	if cards.is_empty():
		result.add_error("empty_deck", "No usable premise cards in %s." % dir_path, dir_path)
	return result


func load_from_array(source: Array) -> ValidationResult:
	var result := ValidationResultType.new()
	for raw in source:
		if not raw is Dictionary:
			result.add_warning("skipped_card", "A deck entry is not an object.")
			continue
		var card: Dictionary = raw
		var card_id := str(card.get("id", ""))
		var problem := card_problem(card)
		if card_id.is_empty():
			problem = "missing id"
		elif cards.has(card_id):
			problem = "duplicate id"
		if not problem.is_empty():
			skipped[card_id if not card_id.is_empty() else "<no id>"] = problem
			result.add_warning("skipped_card", "Skipped premise card %s: %s." % [card_id, problem], card_id)
			continue
		cards[card_id] = card.duplicate(true)
	return result


## Returns "" when the runtime can use the card, otherwise a short reason.
static func card_problem(card: Dictionary) -> String:
	if int(card.get("schema_version", 0)) != SUPPORTED_SCHEMA_VERSION:
		return "unsupported schema_version"
	if not str(card.get("scale", "")) in SCALES:
		return "unknown scale"
	var roles := {}
	for role in card.get("roles", []):
		if role is Dictionary:
			roles[str(role.get("id", ""))] = role
	if roles.is_empty():
		return "no roles"
	var beats: Variant = card.get("beats", [])
	if not beats is Array or (beats as Array).is_empty():
		return "no beats"
	var resolution_ids := {}
	for res in card.get("resolutions", []):
		if res is Dictionary:
			resolution_ids[str(res.get("id", ""))] = true
	if resolution_ids.size() < 2:
		return "fewer than two resolutions"
	if not resolution_ids.has(str(card.get("default_resolution", ""))):
		return "default_resolution does not exist"
	for beat in beats:
		if not beat is Dictionary or (beat.get("missions", []) as Array).is_empty():
			return "a beat has no missions"
		for mission in beat.get("missions", []):
			var verb := str(mission.get("verb", ""))
			if not VERB_TO_OBJECTIVE.has(verb):
				return "unsupported verb %s" % verb
			if not roles.has(str(mission.get("requester", ""))):
				return "mission requester is not a role"
			if not mission.get("routes") is Dictionary:
				return "mission has no routes"
	return ""


func has_card(card_id: String) -> bool:
	return cards.has(card_id)


func get_card(card_id: String) -> Dictionary:
	return cards.get(card_id, {})


func ids() -> Array[String]:
	var out: Array[String] = []
	for key in cards.keys():
		out.append(str(key))
	out.sort()
	return out


func size() -> int:
	return cards.size()


static func role(card: Dictionary, role_id: String) -> Dictionary:
	for r in card.get("roles", []):
		if r is Dictionary and str(r.get("id", "")) == role_id:
			return r
	return {}


static func beat(card: Dictionary, beat_n: int) -> Dictionary:
	for b in card.get("beats", []):
		if b is Dictionary and int(b.get("n", 0)) == beat_n:
			return b
	return {}


static func resolution(card: Dictionary, resolution_id: String) -> Dictionary:
	for r in card.get("resolutions", []):
		if r is Dictionary and str(r.get("id", "")) == resolution_id:
			return r
	return {}
