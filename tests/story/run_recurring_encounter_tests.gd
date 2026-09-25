extends SceneTree

## The recurring cast in person: some arrivals bring someone from an earlier
## story; bitter ones come for the captain, warm ones repay them; a feud that
## ends in a kill ends for good; nobody shows up too often.
##   Godot --headless --path . --script res://tests/story/run_recurring_encounter_tests.gd --log-file <path> -- --baseline-offline

const Enc := preload("res://scripts/story/premise/RecurringEncounters.gd")
const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const RunnerType := preload("res://scripts/story/RecurringEncounterRunner.gd")
const RC := preload("res://scripts/story/premise/RecurringCast.gd")

var _failures: Array[String] = []


func _state() -> Dictionary:
	return {
		"arcs": {
			"arc.0001": {"shown": true, "status": "resolved", "system_id": "sys.a", "cast": {
				"smuggler": {"kind": "person", "entity_id": "npc.vessa", "display_name": "Vessa Orl"},
				"clerk": {"kind": "person", "entity_id": "npc.dask", "display_name": "Dask Moor"},
				"guild": {"kind": "faction", "entity_id": "faction.guild", "display_name": "Ore Guild"}}},
		},
		"fates": {"npc.vessa": ["alive_grudge"], "npc.dask": ["alive_grateful"]},
		"deeds": [],
	}


func _initialize() -> void:
	await process_frame
	var names := {"sys.a": "Tarn"}
	# Over many arrivals: encounters happen, never back to back, and each
	# person not again for a long stretch.
	var state := _state()
	var log := Enc.empty_log()
	var hits: Array = []
	for i in 60:
		var r := Enc.on_arrival(state, log, names, 7)
		log = r["log"]
		if not (r["encounter"] as Dictionary).is_empty():
			hits.append([int(log["arrivals"]), r["encounter"]])
	_check(hits.size() >= 3, "people do come back (%d times in 60 arrivals)" % hits.size())
	for i in range(1, hits.size()):
		_check(int(hits[i][0]) - int(hits[i - 1][0]) >= Enc.MIN_ARRIVALS_BETWEEN, "never back to back")
	var by_person := {}
	for h in hits:
		var pid := str(h[1]["person_id"])
		if by_person.has(pid):
			_check(int(h[0]) - int(by_person[pid]) >= Enc.MIN_ARRIVALS_SAME_PERSON, "the same face not again for a while")
		by_person[pid] = h[0]
	var bitter := hits.filter(func(h): return h[1]["attitude"] == "bitter")
	var warm := hits.filter(func(h): return h[1]["attitude"] == "warm")
	_check(not bitter.is_empty() and not warm.is_empty(), "both grudges and debts come back")
	if not bitter.is_empty():
		var b: Dictionary = bitter[0][1]
		_check(b["display_name"] == "Vessa Orl" and str(b["line"]).contains("Tarn"), "the bitter one names where it went wrong: %s" % b["line"])
		_check(not b.has("gift"), "and brings no gift")
	if not warm.is_empty():
		var w: Dictionary = warm[0][1]
		_check(w["display_name"] == "Dask Moor" and w.has("gift"), "the warm one repays: %s" % str(w))

	# Nobody in a live story, and nobody neutral, comes looking.
	var busy := _state()
	busy["arcs"]["arc.0002"] = {"shown": true, "status": "active", "system_id": "sys.a", "cast": {
		"x": {"kind": "person", "entity_id": "npc.vessa", "display_name": "Vessa Orl"},
		"y": {"kind": "person", "entity_id": "npc.dask", "display_name": "Dask Moor"}}}
	var none := 0
	var blog := Enc.empty_log()
	for i in 40:
		var r := Enc.on_arrival(busy, blog, names, 3)
		blog = r["log"]
		none += 0 if (r["encounter"] as Dictionary).is_empty() else 1
	_check(none == 0, "people busy in a live story stay there")

	# A feud ended in a kill ends for good, and is a deed.
	var ended := Enc.feud_ended(state, "npc.vessa", "Vessa Orl", "sys.a")
	_check(RC.people(ended)["npc.vessa"]["attitude"] == "gone", "the feud is over")
	_check((ended["deeds"] as Array).back()["tag"] == "killed_old_enemy", "and the factions hear of it")

	# The director keeps the log; the runner repays and ends feuds.
	var d = DirectorType.new()
	root.add_child(d)
	d.state = _state()
	var seen := 0
	for i in 30:
		if not d.on_arrival_encounter("sys.a").is_empty():
			seen += 1
	_check(seen > 0 and int(d.state["encounters"]["arrivals"]) == 30, "the director counts arrivals and keeps the log")
	var runner = RunnerType.new()
	runner.director = d
	runner.set_process(false)
	root.add_child(runner)
	var gs: Node = root.get_node("GlobalState")
	var credits: int = gs.player_credits
	runner.play({"person_id": "npc.dask", "display_name": "Dask Moor", "attitude": "warm", "line": "I owe you.", "gift": {"credits": 150}})
	_check(gs.player_credits == credits + 150, "a warm face repays in credits")
	runner.feud_over("npc.vessa", "Vessa Orl", "sys.a")
	_check(RC.people(d.state)["npc.vessa"]["attitude"] == "gone", "ending a feud through the runner reaches the story")
	var reloaded = DirectorType.new()
	reloaded.load_from_dict(d.to_dict())
	_check(int(reloaded.state.get("encounters", {}).get("arrivals", 0)) == 30, "the log survives a save")
	reloaded.free()
	runner.free()
	d.free()
	if _failures.is_empty():
		print("[PASS] Recurring encounters")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
