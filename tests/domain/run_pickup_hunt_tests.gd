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
	var story := {}
	var s: Dictionary = Hunt.state_for(story, "job1")
	_check(Hunt.state_for(story, "job1") == s, "one state per job")
	# Bystanders: deflect or point; never hand it over; the third always points.
	var r: Dictionary = Hunt.ask(s, "A", holder, "Sealed Actuator", 0.9, 0)
	_check(not bool(r["handed_over"]) and not str(r["line"]).contains("Corin"), "a bystander can just deflect")
	r = Hunt.ask(s, "B", holder, "Sealed Actuator", 0.9, 1)
	r = Hunt.ask(s, "C", holder, "Sealed Actuator", 0.9, 2)
	_check(str(r["line"]).contains("Corin Marl") and not bool(r["handed_over"]), "by the third bystander, someone points at the holder (by name, without the org)")
	_check(str(Hunt.ask(s, "A", holder, "Sealed Actuator", 0.9, 0)["line"]).contains("Corin Marl"), "asked again once it's out, they repeat it")
	# The holder: deny, hedge, give.
	r = Hunt.ask(s, holder, holder, "Sealed Actuator", 0.0, 0)
	_check(not bool(r["handed_over"]) and str(r["line"]) in [Hunt._fill(Hunt.HOLDER_DENY[0], "Sealed Actuator", "Corin Marl")], "first ask: denial")
	r = Hunt.ask(s, holder, holder, "Sealed Actuator", 0.0, 0)
	_check(not bool(r["handed_over"]) and str(r["line"]) == Hunt.HOLDER_HEDGE[0], "second: hedging")
	_check(bool(Hunt.ask(s, holder, holder, "Sealed Actuator", 0.0, 0)["handed_over"]), "third: hands it over")
	# A drink counts as an ask.
	var s2: Dictionary = Hunt.state_for(story, "job2")
	Hunt.drink(s2, "A", holder)
	Hunt.drink(s2, holder, holder)
	Hunt.drink(s2, holder, holder)
	_check(not bool(Hunt.ask(s2, "A", holder, "x", 0.9, 0)["handed_over"]), "a bystander's drink changes nothing")
	_check(bool(Hunt.ask(s2, holder, holder, "x", 0.0, 0)["handed_over"]), "drinks soften the holder, but the last step is still an ask")
	# Lines: filled, clean, dry.
	for pool in [Hunt.DEFLECT, Hunt.HINT, Hunt.HOLDER_DENY, Hunt.HOLDER_HEDGE, Hunt.HOLDER_GIVE]:
		for line in pool:
			var filled := Hunt._fill(str(line), "Sealed Actuator", "Corin Marl")
			_check(not filled.contains("{") and ReservedTopics.is_clean(filled), "clean: %s" % filled)

	# The next step names the place, and for a hunt never the person.
	var hunt := {"objective_type": "PICKUP_SPECIAL", "lounge_hunt": true, "part_name": "Sealed Actuator", "target_outpost_display": "QUARAIN BEACON", "target_npc": holder}
	var text := str(Next.for_quest(hunt)["text"])
	_check(text.contains("QUARAIN BEACON") and text.contains("lounge") and not text.contains("Corin"), "hunt: where, not who: %s" % text)
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
