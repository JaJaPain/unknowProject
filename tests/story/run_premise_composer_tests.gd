extends SceneTree

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const Casting := preload("res://scripts/story/premise/PremiseCasting.gd")
const Composer := preload("res://scripts/story/premise/PremiseMissionComposer.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_every_mission_composes_into_a_valid_offer()
	_test_investigations_become_real()
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


## A live-like system: three stations far apart and one gate, no hazards.
func _investigation_world() -> Dictionary:
	return {"ok": true, "system_id": "system.gen_3",
		"stations": [
			{"id": "station.vessa_main", "ids": ["station.vessa_main", "VessaMain", ""], "position": Vector3(0, 0, 0)},
			{"id": "outpost.gen_3_a", "ids": ["outpost.gen_3_a", "IronReach", "outpost.gen_3_a"], "position": Vector3(2400, 0, 900)},
			{"id": "outpost.gen_3_b", "ids": ["outpost.gen_3_b", "KovaStation", "outpost.gen_3_b"], "position": Vector3(-1800, 0, -2200)}],
		"gates": [{"position": Vector3(5000, 0, 0)}], "hazards": []}


func _test_investigations_become_real() -> void:
	var lib = LibraryType.new()
	lib.load_from_dir()
	var world := _world()
	world["main_station"]["station_id"] = "station.vessa_main"
	world["investigation_world"] = _investigation_world()
	var real := 0
	var fell_back := 0
	var recipes := {}
	var problems: Array[String] = []
	for card_id in lib.ids():
		var card: Dictionary = lib.get_card(card_id)
		var cast := Casting.cast_card(card, world, 7, "arc.0001")
		for beat in card.get("beats", []):
			var missions: Array = beat.get("missions", [])
			for i in missions.size():
				if str(missions[i].get("verb", "")) != "investigate_signal":
					continue
				var ref := {"arc_id": "arc.0001", "card_id": card_id, "beat": int(beat["n"]), "mission_index": i,
					"mission": missions[i], "competing": false}
				var offer := Composer.compose(ref, card, cast, world, 3)
				_check(not bool(offer.get("premise_needs_completion", false)), "with a live world nothing awaits completion")
				if str(offer["objective"].get("type", "")) != "INVESTIGATE_SIGNAL":
					fell_back += 1
					continue
				var built := Adapter.build_active_state(offer, offer["choices"][0], "mission.runtime.premise_inv", "system.gen_3", 0)
				var validation = built.get("validation")
				if validation == null or not validation.is_valid():
					problems.append("%s b%s m%d: %s" % [card_id, beat["n"], i, validation.summary() if validation != null else "no validation"])
					continue
				_check(str(offer["objective"]["turn_in_station_id"]) == "station.vessa_main", "turned in at the main station")
				real += 1
				var r := str(offer["objective"]["recipe"])
				recipes[r] = int(recipes.get(r, 0)) + 1
	print("  investigations: %d real, %d fell back; recipes %s" % [real, fell_back, str(recipes)])
	_check(problems.is_empty(), "%d investigations invalid, first: %s" % [problems.size(), str(problems.slice(0, 3))])
	_check(real >= 95 and fell_back == 0, "every deck investigation should be real here (%d real, %d fell back)" % [real, fell_back])
	_check(recipes.size() >= 2, "the deck's wording should reach every investigation type the game can run")
	# No live world (headless director tests): the old pickup, never a half-built job.
	var plain := _world()
	plain["investigation_fallback"] = true
	var card: Dictionary = lib.get_card(lib.ids()[0])
	for beat in card.get("beats", []):
		for i in (beat.get("missions", []) as Array).size():
			var m: Dictionary = beat["missions"][i]
			if str(m.get("verb", "")) == "investigate_signal":
				var offer := Composer.compose({"arc_id": "arc.0001", "card_id": card["id"], "beat": int(beat["n"]), "mission_index": i, "mission": m},
					card, Casting.cast_card(card, plain, 7, "arc.0001"), plain, 3)
				_check(str(offer["objective"]["type"]) == "PICKUP_SPECIAL", "without a live world, investigations fall back to the pickup")
