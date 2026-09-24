extends SceneTree

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const Casting := preload("res://scripts/story/premise/PremiseCasting.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_every_card_casts_and_fills()
	_test_reuse_and_distinct_places()
	_test_deterministic()
	if _failures.is_empty():
		print("[PASS] Premise casting tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _world() -> Dictionary:
	return {
		"system_id": "system.gen_3", "system_display": "Vessa",
		"main_station": {"id": "system.gen_3", "display": "Vessa Main"},
		"outposts": [{"id": "outpost.a", "display": "Iron Reach"}, {"id": "outpost.b", "display": "Kova Station"}],
		"factions": [{"id": "faction.generated.one", "display_name": "The Tessin Guild", "spawn_key": "gen_one"},
			{"id": "faction.generated.two", "display_name": "Harrow Consortium", "spawn_key": "gen_two"}],
		"hostile_factions": ["reavers", "dustborn"],
		"known_npcs": [{"id": "npc.known.mira", "display_name": "Mira Holt"}],
	}


func _all_text(card: Dictionary) -> String:
	var parts: PackedStringArray = [str(card.get("logline", "")), str(card.get("public_situation", "")), str(card.get("private_truth", ""))]
	for beat in card.get("beats", []):
		parts.append(str(beat.get("public_change", "")))
		for m in beat.get("missions", []):
			parts.append(str(m.get("reason", "")))
			parts.append(str(m.get("private_fact", "")))
		if beat.get("player_choice") is Dictionary:
			parts.append(str(beat["player_choice"].get("prompt", "")))
	for r in card.get("resolutions", []):
		parts.append(str(r.get("summary", "")))
		for q in r.get("consequences", []):
			parts.append(str(q.get("public_summary", "")))
	for h in card.get("radio_hooks", []):
		parts.append(str(h))
	return "\n".join(parts)


func _test_every_card_casts_and_fills() -> void:
	var lib = LibraryType.new()
	lib.load_from_dir()
	var unfilled: Array[String] = []
	for card_id in lib.ids():
		var card: Dictionary = lib.get_card(card_id)
		var cast := Casting.cast_card(card, _world(), 99, "arc.0001")
		for role in card.get("roles", []):
			var entry: Dictionary = cast.get(str(role["id"]), {})
			_check(not entry.is_empty() and not str(entry.get("display_name", "")).is_empty(),
				"%s: role %s not cast" % [card_id, role["id"]])
			if str(role.get("kind", "")) == "ship":
				_check(not str(entry.get("faction_key", "")).is_empty(), "%s: ship %s has no faction to spawn from" % [card_id, role["id"]])
		var filled := Casting.fill_text(_all_text(card), cast, _world())
		if filled.contains("{role:") or filled.contains("{system}") or filled.contains("{player}"):
			unfilled.append(card_id)
	_check(unfilled.is_empty(), "placeholders left unfilled in: %s" % str(unfilled))


func _test_reuse_and_distinct_places() -> void:
	var card := {"id": "premise.t", "roles": [
		{"id": "old_friend", "kind": "person", "reuse": "prefer_existing"},
		{"id": "stranger", "kind": "person", "reuse": "must_be_new"},
		{"id": "origin", "kind": "place"}, {"id": "dest", "kind": "place"},
		{"id": "harrow_consortium", "kind": "faction"}, {"id": "consortium_enforcer", "kind": "ship"},
		{"id": "sample_cases", "kind": "object"}],
		"beats": [{"n": 1, "missions": [{"target": "dest"}, {"target": "origin"}]}]}
	var cast := Casting.cast_card(card, _world(), 5, "arc.0007")
	_check(cast["old_friend"]["entity_id"] == "npc.known.mira" and bool(cast["old_friend"]["reused"]), "prefer_existing should reuse a known NPC")
	_check(not bool(cast["stranger"]["reused"]) and str(cast["stranger"]["entity_id"]).begins_with("npc.arc_0007"), "must_be_new should create a new person")
	_check(cast["dest"]["entity_id"] != cast["origin"]["entity_id"], "two places should get two different docks")
	_check(cast["consortium_enforcer"]["faction_key"] == cast["harrow_consortium"]["spawn_key"], "a ship sharing a faction role's name should fly under that faction's spawn key")
	var no_spawn := _world()
	for f in no_spawn["factions"]:
		f["spawn_key"] = ""
	var fallback := Casting.cast_card(card, no_spawn, 5, "arc.0007")
	_check(fallback["consortium_enforcer"]["faction_key"] in ["reavers", "dustborn"], "without a spawn key, a ship must fall back to a hostile faction that can spawn")
	_check(cast["sample_cases"]["display_name"] == "sample cases", "objects get readable item names")


func _test_deterministic() -> void:
	var lib = LibraryType.new()
	lib.load_from_dir()
	var card: Dictionary = lib.get_card(lib.ids()[0])
	_check(Casting.cast_card(card, _world(), 11, "arc.1") == Casting.cast_card(card, _world(), 11, "arc.1"), "casting must be deterministic per seed")
