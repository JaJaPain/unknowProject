extends SceneTree

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const Arcs := preload("res://scripts/story/premise/ArcEngine.gd")
const Hand := preload("res://scripts/story/premise/HiddenHand.gd")
const Forge := preload("res://scripts/story/premise/HiddenHandForge.gd")
const Composer := preload("res://scripts/story/premise/PremiseMissionComposer.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")
const Fixture := preload("res://tests/story/run_showrunner_tests.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	# Never touch the player's Destination history (Lodestar.draw_for_new_campaign).
	load("res://scripts/domain/Lodestar.gd").history_path = ""
	_test_forged_card_is_valid_and_playable()
	if _failures.is_empty():
		print("[PASS] Hidden hand forge tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _world() -> Dictionary:
	return {"system_id": "system.v", "system_display": "Vessa", "main_station": {"id": "system.v", "display": "Vessa Main"},
		"outposts": [{"id": "outpost.a", "display": "Iron Reach"}], "hostile_factions": ["reavers"], "factions": []}


func _test_forged_card_is_valid_and_playable() -> void:
	var fixture: Dictionary = Fixture.build_fixture()
	var s: Dictionary = fixture["state"]
	_check(Forge.forge(s, _world()).is_empty(), "nothing is forged before the lock")
	s = Hand.lock_by_code(s, 50)["state"]
	var forged := Forge.forge(s, _world())
	_check(not forged.is_empty(), "a locked story forges a confrontation")
	var card: Dictionary = forged["card"]
	_check(LibraryType.card_problem(card).is_empty(), "the forged card must pass the runtime card checks: %s" % LibraryType.card_problem(card))
	_check(Forge.is_forged(card["id"]), "forged cards are recognisable by id")
	_check(forged["cast"]["culprit"]["entity_id"] == Hand.main_story(s)["lock"]["entity_id"], "the culprit is the locked identity")
	_check(load("res://scripts/story/ReservedTopics.gd").is_clean(JSON.stringify(card)), "forged text stays clear of reserved topics")

	var lib = LibraryType.new()
	lib.load_from_array([card])
	# Its missions compose into valid offers.
	for beat in card["beats"]:
		for i in (beat["missions"] as Array).size():
			var ref := {"arc_id": "arc.9999", "card_id": card["id"], "beat": int(beat["n"]), "mission_index": i, "mission": beat["missions"][i]}
			var offer := Composer.compose(ref, card, forged["cast"], _world(), 1)
			var built := Adapter.build_active_state(offer, offer["choices"][0], "mission.runtime.forge_test", "system.v", 0)
			_check(built["validation"].is_valid(), "forged beat %d offer invalid: %s" % [beat["n"], built["validation"].summary()])
			_check(not str(offer["dialogue"]).contains("{role:"), "forged dialogue has unfilled placeholders")
	var showdown: Dictionary = (card["beats"] as Array).filter(func(b): return str(b.get("function", "")) == "climax")[0]
	_check(bool(showdown.get("at_lodestar", false)), "the showdown waits for the Lodestar")
	_check(bool((showdown["missions"] as Array)[0].get("scales_with_lead", false)), "the showdown's fight grows with the culprit's lead")
	_check((card["beats"] as Array).size() == 3, "proof, chase, showdown")
	# Every route resolves: expose, quiet deal, bought off, slips away. The
	# race: proof, then the chase (lost or not, the trail goes on), then the
	# showdown at the Lodestar.
	var outcomes := {
		"exposed": [["completed", ""], ["completed", "finish_kill"], ["completed", "finish_kill"], ["choice", "expose"]],
		"quiet_deal": [["completed", ""], ["abandoned", ""], ["completed", "finish_kill"], ["choice", "quiet_deal"]],
		"bought_off": [["completed", ""], ["completed", "finish_kill"], ["completed", "accept_bribe"]],
		"hand_slips_away": [["abandoned", ""]],
	}
	for expected in outcomes.keys():
		var started := Arcs.start_arc(Arcs.empty_state(), card, "system.v", forged["cast"], 0)
		var st: Dictionary = started["state"]
		var arc_id: String = started["arc_id"]
		var beat_n := 1
		for step in outcomes[expected]:
			if step[0] == "choice":
				st = Arcs.apply_choice(st, lib, arc_id, step[1], 1)
			else:
				st = Arcs.apply_mission_result(st, lib, arc_id, beat_n, 0, step[0], step[1], 1)
				beat_n = int(Arcs.arc(st, arc_id)["beat"])
		_check(Arcs.arc(st, arc_id)["resolution_id"] == expected, "route to %s ended at %s" % [expected, Arcs.arc(st, arc_id)["resolution_id"]])
