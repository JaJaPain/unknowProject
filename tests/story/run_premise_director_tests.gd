extends SceneTree

## Simulates a live campaign against PremiseDirector without the game: arrive,
## read the board, "fly" missions, answer decisions, save and reload, and let
## ignored stories settle on their own.

const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")
const HISTORY_PATH := "user://test_premise_director_history.json"

var _failures: Array[String] = []


func _initialize() -> void:
	# Never touch the player's Destination history (Lodestar.draw_for_new_campaign).
	load("res://scripts/domain/Lodestar.gd").history_path = ""
	_test_no_arcs_before_the_tutorial_ends()
	_test_campaign_simulation()
	_test_save_reload_keeps_arcs()
	_test_ignored_arcs_settle()
	_test_main_story_season()
	_test_written_lines()
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
	d.use_showrunner = false
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
	var bribed_twists := 0
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
			# Treat every kill job as twisted (few kill jobs come up in four
			# systems); the deed hook reads only the twist mark and the branch.
			if str(q["objective"].get("type", "")) in ["KILL_SHIPS", "TARGET_WITH_COMMS_REVERSAL"]:
				q["twist_id"] = "counter_offer"
				q["twist_target_name"] = "the mark"
			if not str(q.get("twist_id", "")).is_empty() and q["objective"]["branch_id"] == "accept_bribe":
				bribed_twists += 1
			_check(d.on_mission_terminal(q, terminal, now), "a premise mission should be recognised")
	for arc_id in d.state["arcs"].keys():
		if d.state["arcs"][arc_id]["status"] == "resolved":
			resolved += 1
	_check(resolved >= 4, "several stories should have run to an end, got %d" % resolved)
	var bribe_deeds := (d.state.get("deeds", []) as Array).filter(func(x): return str(x.get("tag", "")) == "sold_out_contract").size()
	_check(bribed_twists > 0, "the simulation should take at least one bribe on a twisted job")
	_check(bribe_deeds == bribed_twists, "every bribe taken on a twisted job leaves a deed (%d of %d)" % [bribe_deeds, bribed_twists])
	_check(d_signal.size() == resolved, "arc_resolved should fire once per resolution")
	_check((d.state["ledger"] as Array).size() > 10, "the story ledger should have grown")
	# N.O.V.A.'s journal: the stories seen, newest first, in plain filled text.
	var journal: Array = d.journal()
	_check(journal.size() >= 4, "the journal should hold the stories played (%d)" % journal.size())
	for e in journal:
		_check(not str(e["title"]).is_empty() and not str(e["text"]).is_empty(), "journal entries have a title and text")
		_check(not str(e["text"]).contains("{role:") and not str(e["text"]).contains("{system"), "journal text is filled: %s" % e["text"])
	for i in range(1, journal.size()):
		_check(int(journal[i - 1]["minute"]) >= int(journal[i]["minute"]), "journal newest first")
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


## Play system after system until the main story locks, its confrontation
## resolves, and a second season begins.
func _test_main_story_season() -> void:
	var d = _director()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var locked_name := []
	var closed := []
	d.main_story_locked.connect(func(name, arc_id): locked_name.append(name))
	d.season_closed.connect(func(season, res): closed.append(res))
	var now := 0
	# The player drops the confrontation's first job (the proof) once: the
	# season goes on, with the culprit ahead.
	var dropped_proof := {"done": false, "lead_before": -1, "lead_after": -1}
	# The reveal needs evidence from 9 systems (tuned to reveal around hours
	# 8-12, campaign spine plan); allow 25.
	for system_n in range(1, 26):
		var w := _world(system_n)
		# The showdown happens at the Lodestar (the race): arrive there two
		# systems after the reveal.
		var ms: Dictionary = d.state.get("main_story", {})
		if ms.has("_locked_at_system") and system_n >= int(ms["_locked_at_system"]) + 2:
			w["at_lodestar"] = true
		d.ensure_arcs(w, now)
		for _round in 40:
			now += 60
			for decision in d.pending_decisions():
				var options: Array = decision["options"]
				d.apply_decision(str(decision["arc_id"]), str(options[rng.randi_range(0, options.size() - 1)]["id"]), now)
			var postings: Array = d.board_postings(w, now)
			if postings.is_empty():
				break
			# Once revealed, the main story leads the board and a player follows it.
			var pick: Dictionary = postings[rng.randi_range(0, postings.size() - 1)]
			if not locked_name.is_empty():
				pick = postings[0]
			var quest: Dictionary = pick["quest_data"].duplicate(true)
			quest["objective"]["branch_id"] = "finish_kill"
			var conf := str(d.state["main_story"].get("confrontation_arc_id", ""))
			if not dropped_proof["done"] and not conf.is_empty() and str(pick.get("arc_id", "")) == conf:
				dropped_proof["done"] = true
				dropped_proof["lead_before"] = int(d.state["main_story"].get("race_steps", 0))
				d.on_mission_terminal(quest, "abandoned", now)
				dropped_proof["lead_after"] = int(d.state["main_story"].get("race_steps", 0))
				continue
			d.on_mission_terminal(quest, "completed", now)
		if not locked_name.is_empty() and not d.state["main_story"].has("_locked_at_system"):
			d.state["main_story"]["_locked_at_system"] = system_n
		if not closed.is_empty():
			print("  main story: locked at system %s, closed at system %d (%s)" % [d.state["main_story"].get("_locked_at_system", "?"), system_n, closed[0]])
			break
	_check(not locked_name.is_empty(), "the main story should lock within twenty-five systems")
	_check(not closed.is_empty(), "the confrontation should resolve and close the season")
	_check(bool(dropped_proof["done"]), "the test should have dropped the proof job once")
	_check(int(dropped_proof["lead_after"]) == int(dropped_proof["lead_before"]) + d.PROOF_LOST_HEAD_START,
		"dropping the proof gives the culprit a head start (%d -> %d)" % [dropped_proof["lead_before"], dropped_proof["lead_after"]])
	_check(closed.is_empty() or str(closed[0]) != "hand_slips_away", "dropping the proof doesn't end the season (closed by %s)" % [closed[0] if not closed.is_empty() else ""])
	if not locked_name.is_empty():
		var lock: Dictionary = d.state["main_story"]["lock"]
		_check(str(locked_name[0]) == str(lock["display_name"]), "the signal names the locked identity")
		_check((lock["arcs"] as Array).size() >= 2, "the culprit should have appeared in at least two stories before the reveal (got %d)" % (lock["arcs"] as Array).size())
	var threads: Array = d.main_story_threads()
	_check(not threads.is_empty() and not str(threads[0]["text"]).contains("{role:"), "seen threads are readable")
	# The next arrival starts season two.
	d.ensure_arcs(_world(40), now + 60)
	_check(int(d.state["main_story"]["season"]) == 2 and d.state["main_story"]["stage"] == "hidden", "a new season should begin after the old one closes")
	# Forged cards survive a save round trip.
	var e = _director()
	e.load_from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
	var forged_id := "premise.hidden_hand.s1"
	_check(e.library.has_card(forged_id), "the forged confrontation card must come back with the save")
	d.free()
	e.free()


func _test_written_lines() -> void:
	var d = _director()
	d.ensure_arcs(_world(6), 0)
	var postings: Array = d.board_postings(_world(6), 5)
	_check(postings.size() >= 2, "need two postings to test lines")
	if postings.size() < 2:
		d.free()
		return
	_check(not postings[0].has("voice_line"), "nothing is voiced before a line is written")
	var note := str(postings[0]["quest_data"]["dialogue"])
	var key := DirectorType.line_key(str(postings[0]["arc_id"]), postings[0]["quest_data"])
	var line := "I need that cargo moved before the shift change, and I need it done quietly."
	d.store_line({"key": key}, {"ok": true, "line": line, "reason": ""})
	var again: Dictionary = d.board_postings(_world(6), 6)[0]
	_check(str(again["body"]).begins_with(line), "the written line replaces the director note on the board")
	_check(str(again.get("voice_line", "")) == line and str(again.get("voice_profile", "")).begins_with("voice.generated."), "the posting carries the line and a generated voice")
	_check(str(again["quest_data"]["dialogue"]) == line and str(again["quest_data"]["premise_director_note"]) == note, "the accepted job speaks the line and keeps the note")
	var key2 := DirectorType.line_key(str(postings[1]["arc_id"]), postings[1]["quest_data"])
	var job := {"key": key2}
	d.store_line(job, {"ok": false, "line": "", "reason": "stock_phrase"})
	_check(d._line_queue.size() == 1 and str(d.state["written_lines"][key2].get("status", "")) == "", "a failed line gets one retry")
	d.store_line(job, {"ok": false, "line": "", "reason": "length"})
	_check(str(d.state["written_lines"][key2]["status"]) == "failed", "after the retry the note stands for good")
	_check(not d.board_postings(_world(6), 7)[1].has("voice_line"), "a failed line is never voiced")
	var e = _director()
	e.load_from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
	_check(e.written_line(str(postings[0]["arc_id"]), postings[0]["quest_data"]) == line, "written lines survive a save round trip")
	d.free()
	e.free()
