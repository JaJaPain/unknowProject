extends SceneTree

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const Casting := preload("res://scripts/story/premise/PremiseCasting.gd")
const Composer := preload("res://scripts/story/premise/PremiseMissionComposer.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_every_mission_composes_into_a_valid_offer()
	if _failures.is_empty():
		print("[PASS] Premise composer tests")
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
		"outposts": [{"id": "outpost.gen_3_a", "display": "Iron Reach"}, {"id": "outpost.gen_3_b", "display": "Kova Station"}],
		"factions": [{"id": "faction.generated.tessin_guild", "display_name": "The Tessin Guild", "spawn_key": "gen_tessin"},
			{"id": "faction.generated.harrow", "display_name": "Harrow Consortium", "spawn_key": ""}],
		"hostile_factions": ["reavers", "dustborn"],
		"known_npcs": [{"id": "npc.known.mira", "display_name": "Mira Holt"}],
		"store_items": [{"item_id": "medical_kit", "display_name": "Medical kit", "quantity": 2,
			"station_id": "system.gen_3", "store_display": "Vessa Main", "base_price": 45}],
	}


func _test_every_mission_composes_into_a_valid_offer() -> void:
	var lib = LibraryType.new()
	lib.load_from_dir()
	var composed := 0
	var pending := 0
	var problems: Array[String] = []
	for card_id in lib.ids():
		var card: Dictionary = lib.get_card(card_id)
		var cast := Casting.cast_card(card, _world(), 7, "arc.0001")
		for beat in card.get("beats", []):
			var missions: Array = beat.get("missions", [])
			for i in missions.size():
				var ref := {"arc_id": "arc.0001", "card_id": card_id, "beat": int(beat["n"]), "mission_index": i,
					"mission": missions[i], "competing": false}
				var offer := Composer.compose(ref, card, cast, _world(), 3)
				if offer.is_empty():
					problems.append("%s b%s m%d: nothing composed" % [card_id, beat["n"], i])
					continue
				_check(str(offer["narrative_metadata"]["story_beat_id"]).begins_with(card_id), "story_beat_id must carry the card id")
				_check(not str(offer["dialogue"]).contains("{role:"), "%s: unfilled placeholder in dialogue" % card_id)
				var target_faction := str(offer["objective"].get("target_faction", ""))
				if not target_faction.is_empty():
					_check(target_faction in ["reavers", "dustborn", "gen_tessin"],
						"%s: combat target %s is not a spawnable faction key" % [card_id, target_faction])
				if bool(offer.get("premise_needs_completion", false)):
					pending += 1
					continue
				var built := Adapter.build_active_state(offer, offer["choices"][0], "mission.runtime.premise_test", "system.gen_3", 0)
				var validation = built.get("validation")
				if validation == null or not validation.is_valid():
					problems.append("%s b%s m%d (%s): %s" % [card_id, beat["n"], i, missions[i]["verb"],
						validation.summary() if validation != null else "no validation"])
				else:
					composed += 1
	_check(problems.is_empty(), "%d offers invalid, first: %s" % [problems.size(), str(problems.slice(0, 5))])
	_check(composed > 300, "expected hundreds of valid offers, got %d" % composed)
	print("  composed %d valid offers, %d investigations awaiting live completion" % [composed, pending])
