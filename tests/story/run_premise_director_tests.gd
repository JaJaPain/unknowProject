extends SceneTree

## Simulates a live campaign against PremiseDirector without the game: arrive,
## read the board, "fly" missions, answer decisions, save and reload, and let
## ignored stories settle on their own.

const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")
const HISTORY_PATH := "user://test_premise_director_history.json"

var _failures: Array[String] = []


func _initialize() -> void:
	_test_no_arcs_before_the_tutorial_ends()
	_test_campaign_simulation()
	_test_save_reload_keeps_arcs()
	_test_ignored_arcs_settle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HISTORY_PATH))
	if _failures.is_empty():
		print("[PASS] Premise director tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _world(system_n: int) -> Dictionary:
	return {
		"system_id": "system.gen_%d" % system_n, "system_display": "System %d" % system_n,
		"system_seed": 1000 + system_n, "star_type": ["red", "blue", "yellow", "white"][system_n % 4],
		"post_tutorial": true, "is_first_system": false, "investigation_fallback": true,
		"main_station": {"id": "system.gen_%d" % system_n, "display": "Main %d" % system_n},
		"outposts": [{"id": "outpost.%d_a" % system_n, "display": "Reach %d" % system_n},
			{"id": "outpost.%d_b" % system_n, "display": "Kova %d" % system_n}],
		"factions": [{"id": "faction.generated.a%d" % system_n, "display_name": "Guild %d" % system_n},
			{"id": "faction.generated.b%d" % system_n, "display_name": "Consortium %d" % system_n},
			{"id": "faction.generated.c%d" % system_n, "display_name": "Collective %d" % system_n}],
		"hostile_factions": ["reavers", "dustborn"], "known_npcs": [],
		"store_items": [{"item_id": "medical_kit", "display_name": "Medical kit", "quantity": 1,
			"station_id": "system.gen_%d" % system_n, "store_display": "Main", "base_price": 40}],
	}


func _director():
	var d = DirectorType.new()
	d.history_path = HISTORY_PATH
	d.reset_for_new_campaign(4242)
	return d


func _test_no_arcs_before_the_tutorial_ends() -> void:
	var d = _director()
	var w := _world(1)
	w["post_tutorial"] = false
	_check(d.ensure_arcs(w, 0).is_empty(), "no premise arcs during the tutorial")
	w["post_tutorial"] = true
	w["is_first_system"] = true
	_check(d.ensure_arcs(w, 0).is_empty(), "no premise arcs in the tutorial system")
	d.free()


## Visit four systems; take every posting, answer every decision, repeat.
func _test_campaign_simulation() -> void:
	var d = _director()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var now := 0
	var resolved := 0
	var d_signal: Array = []
	d.arc_resolved.connect(func(arc_id, res_id): d_signal.append(res_id))
	for system_n in [1, 2, 3, 4]:
		var w := _world(system_n)
		var started: Array = d.ensure_arcs(w, now)
		_check(not started.is_empty(), "arriving in a new system should start stories (system %d)" % system_n)
		for _round in 30:
			now += 90
			for decision in d.pending_decisions():
				var options: Array = decision["options"]
				d.apply_decision(str(decision["arc_id"]), str(options[rng.randi_range(0, options.size() - 1)]["id"]), now)
			var postings: Array = d.board_postings(w, now)
			if postings.is_empty():
				break
			var posting: Dictionary = postings[rng.randi_range(0, postings.size() - 1)]
			var quest: Dictionary = posting["quest_data"]
			var built := Adapter.build_active_state(quest, quest["choices"][0], "mission.runtime.sim", w["system_id"], now)
			_check(built["validation"].is_valid(), "posting failed validation: %s" % built["validation"].summary())
			var terminal := "completed" if rng.randi_range(0, 4) > 0 else "abandoned"
			var q := quest.duplicate(true)
			q["objective"]["branch_id"] = "accept_bribe" if rng.randi_range(0, 1) == 0 else "finish_kill"
			_check(d.on_mission_terminal(q, terminal, now), "a premise mission should be recognised")
	for arc_id in d.state["arcs"].keys():
		if d.state["arcs"][arc_id]["status"] == "resolved":
			resolved += 1
	_check(resolved >= 4, "several stories should have run to an end, got %d" % resolved)
	_check(d_signal.size() == resolved, "arc_resolved should fire once per resolution")
	_check((d.state["ledger"] as Array).size() > 10, "the story ledger should have grown")
	_check(not d.on_mission_terminal({"title": "Ordinary job", "narrative_metadata": {}}, "completed", now),
		"ordinary missions must be ignored")
	var history = load("res://scripts/story/premise/PremiseCardHistoryStore.gd").load_history(HISTORY_PATH)["history"]
	_check(int(history["counter"]) >= 4, "shown cards should be recorded in the machine history")
	d.free()


func _test_save_reload_keeps_arcs() -> void:
	var d = _director()
	d.ensure_arcs(_world(5), 0)
	var saved: Dictionary = d.to_dict()
	var e = _director()
	e.load_from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(e.to_dict()["arcs"]["arcs"].size() == saved["arcs"]["arcs"].size(), "arcs must survive a save round trip")
	_check(e.board_postings(_world(5), 10).size() == d.board_postings(_world(5), 10).size(), "a reloaded campaign offers the same postings")
	var f = _director()
	f.load_from_dict({"version": 99})
	_check(f.state["arcs"].is_empty(), "an unknown save version starts clean instead of crashing")
	d.free()
	e.free()
	f.free()


func _test_ignored_arcs_settle() -> void:
	var d = _director()
	d.ensure_arcs(_world(6), 0)
	var live_before: int = d.state["arcs"].size()
	d.tick(20 * 1440)
	var still_active := 0
	for arc_id in d.state["arcs"].keys():
		if d.state["arcs"][arc_id]["status"] == "active":
			still_active += 1
	_check(live_before > 0 and still_active == 0, "stories nobody touched should settle by themselves")
	d.free()
