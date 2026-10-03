extends SceneTree

## Playtest 2026-10-03 finding 14 + Abe's design: board pickups are a lounge
## hunt (find who has it, talk it out of them, very dry), and every pickup's
## next step names where to go.
##   Godot --headless --path . --script res://tests/domain/run_pickup_hunt_tests.gd --log-file <path>

const Hunt := preload("res://scripts/domain/PickupHunt.gd")
const Next := preload("res://scripts/domain/QuestNextStep.gd")
const ReservedTopics := preload("res://scripts/story/ReservedTopics.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var holder := "Pilgrim Fleet Corin Marl"
	var part := "Sealed Actuator"
	var P: Dictionary = Hunt.pools()
	var filled_pool := func(name: String) -> Array:
		return (P[name] as Array).map(func(l): return Hunt._fill(str(l), part, "Corin Marl"))
	var story := {}
	var decks: Dictionary = Hunt.decks_for(story)
	var s: Dictionary = Hunt.state_for(story, "job1")
	_check(Hunt.state_for(story, "job1") == s, "one state per job")
	# Bystanders: deflect or point; never hand it over; the third always points.
	var r: Dictionary = Hunt.ask(s, "A", holder, part, 0.9, decks)
	_check(not bool(r["handed_over"]) and str(r["line"]) in filled_pool.call("deflect"), "a bystander can just deflect")
	r = Hunt.ask(s, "B", holder, part, 0.9, decks)
	r = Hunt.ask(s, "C", holder, part, 0.9, decks)
	_check(str(r["line"]).contains("Corin Marl") and not str(r["line"]).contains("Pilgrim") and not bool(r["handed_over"]), "by the third bystander, someone points at the holder (by name, without the org)")
	_check(str(Hunt.ask(s, "A", holder, part, 0.9, decks)["line"]).contains("Corin Marl"), "asked again once it's out, they repeat it")
	# The holder: deny with a tell, hedge, give.
	r = Hunt.ask(s, holder, holder, part, 0.0, decks)
	var line := str(r["line"])
	var denied := (filled_pool.call("deny") as Array).any(func(d): return line.begins_with(str(d)))
	var told := (P["tell"] as Array).any(func(x): return line.ends_with(str(x)))
	_check(not bool(r["handed_over"]) and denied and told, "first ask: a denial with a tell, so the player knows to push: %s" % line)
	_check(Hunt.suspect(s, holder) == holder, "caught out: the tracker can name them")
	_check(Hunt.suspect(Hunt.state_for({}, "fresh"), holder).is_empty(), "nobody suspected at the start")
	r = Hunt.ask(s, holder, holder, part, 0.0, decks)
	_check(not bool(r["handed_over"]) and str(r["line"]) in filled_pool.call("hedge"), "second: hedging")
	r = Hunt.ask(s, holder, holder, part, 0.0, decks)
	_check(bool(r["handed_over"]) and str(r["line"]) in filled_pool.call("give"), "third: hands it over")
	# A drink counts as an ask.
	var s2: Dictionary = Hunt.state_for(story, "job2")
	Hunt.drink(s2, "A", holder)
	Hunt.drink(s2, holder, holder)
	Hunt.drink(s2, holder, holder)
	_check(not bool(Hunt.ask(s2, "A", holder, "x", 0.9, decks)["handed_over"]), "a bystander's drink changes nothing")
	_check(bool(Hunt.ask(s2, holder, holder, "x", 0.0, decks)["handed_over"]), "drinks soften the holder, but the last step is still an ask")

	# A large pool (Abe), dealt from shuffled decks: random, no repeats until
	# every line has had its turn, and a fresh shuffle after.
	for name in Hunt.POOL_NAMES:
		_check((P[name] as Array).size() >= 25, "%s: a large pool (%d)" % [name, (P[name] as Array).size()])
		var fresh := {}
		var seen := {}
		for k in (P[name] as Array).size():
			seen[Hunt.draw(fresh, name)] = true
		_check(seen.size() == (P[name] as Array).size(), "%s: every line before any repeats" % name)
		_check(not Hunt.draw(fresh, name).is_empty(), "%s: then a new shuffle" % name)
	var orders := {}
	for k in 6:
		var d := {}
		orders[str([Hunt.draw(d, "deflect"), Hunt.draw(d, "deflect"), Hunt.draw(d, "deflect")])] = true
	_check(orders.size() > 1, "the order is random, not fixed")
	# Lines: filled, clean, grammatical, tells only from the holder.
	for name in Hunt.POOL_NAMES:
		for l in P[name]:
			var raw := str(l)
			var filled := Hunt._fill(raw, part, "Corin Marl")
			_check(not filled.contains("{") and ReservedTopics.is_clean(filled), "clean: %s" % filled)
			_check(not raw.contains(" a {part}") and not raw.begins_with("A {part}"), "no 'a {part}' (items can start with a vowel): %s" % raw)
			if name == "tell":
				_check(raw.begins_with("(") and raw.ends_with(")"), "a tell is a bracketed stage direction: %s" % raw)
			else:
				_check(not raw.contains("("), "only tells use brackets: %s" % raw)
			if name == "hint":
				_check(raw.contains("{holder}"), "a pointer names who: %s" % raw)
			elif name in ["deflect", "deny", "hedge"]:
				_check(not raw.contains("{holder}"), "%s never names the holder: %s" % [name, raw])

	# The next step names the place, and for a hunt never the person.
	var hunt := {"objective_type": "PICKUP_SPECIAL", "lounge_hunt": true, "part_name": "Sealed Actuator", "target_outpost_display": "QUARAIN BEACON", "target_npc": holder}
	var text := str(Next.for_quest(hunt)["text"])
	_check(text.contains("QUARAIN BEACON") and text.contains("lounge") and text.contains("keep pushing") and not text.contains("Corin"), "hunt: where, not who, and that it takes pushing: %s" % text)
	var direct := hunt.duplicate()
	direct["lounge_hunt"] = false
	text = str(Next.for_quest(direct)["text"])
	_check(text.contains("Corin Marl") and not text.contains("Pilgrim Fleet"), "a direct pickup names the person, short: %s" % text)
	direct["picked_up"] = true
	direct["destination"] = "QUARAIN DEPOT"
	_check(str(Next.for_quest(direct)["text"]).contains("QUARAIN DEPOT"), "after: the hand-in station")
	direct["destination"] = "Grease Monkeys"
	_check(not str(Next.for_quest(direct)["text"]).contains("Grease Monkeys"), "the old hard-coded name is never shown for a board job")
	direct["destination"] = "station.system_gen_x.s0"
	_check(not str(Next.for_quest(direct)["text"]).contains("station."), "a station id is never shown")
	var errand := direct.duplicate()
	errand["station_errand"] = true
	errand["destination"] = "Grease Monkeys"
	errand["agent_name"] = "Jenna Kross"
	_check(str(Next.for_quest(errand)["text"]).contains("Jenna Kross at Grease Monkeys"), "the mechanic's own parts run still goes back to her shop")
	_check(Next.person_name("Zeneshdramir Pilgrim Fleet Rook Harrow") == "Rook Harrow" and Next.person_name("Jenna Kross") == "Jenna Kross", "person names")
	# Wiring.
	_check(FileAccess.get_file_as_string("res://scripts/QuestManager.gd").contains('for lane in ["STATION", "AGENT", "BOARD"]'), "board pickups count as pickups")
	var gs_text := FileAccess.get_file_as_string("res://scripts/GlobalState.gd")
	var last_names := gs_text.substr(gs_text.find("GENERATED_CONTACT_LAST_NAMES"), 300)
	_check(not last_names.contains("\"Rook\""), "no Rook Rook")
	if _failures.is_empty():
		print("[PASS] Pickup hunt and next steps")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
