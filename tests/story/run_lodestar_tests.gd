extends SceneTree

## Core loop step 9: the Lodestar deck, the draw, the state, the star map
## wedge's numbers, and N.O.V.A.'s first hint (once, after the tutorial, away
## from home). Every player-facing line is checked against the reserved topics.
##   Godot --headless --path . --script res://tests/story/run_lodestar_tests.gd --log-file <path> -- --baseline-offline

const Lodestar := preload("res://scripts/domain/Lodestar.gd")
const ReservedTopics := preload("res://scripts/story/ReservedTopics.gd")
const GuideType := preload("res://scripts/story/LodestarGuide.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	# Never touch the player's Destination history (Lodestar.draw_for_new_campaign).
	load("res://scripts/domain/Lodestar.gd").history_path = ""
	await process_frame
	# --- The deck ---------------------------------------------------------------
	var cards: Array = Lodestar.deck()
	_check(cards.size() == 6, "six Lodestars (%d)" % cards.size())
	# Across campaigns (season sim 2026-10-06): a new campaign's first
	# Destination is fresh until all have been used, never one of the last 3.
	var hist_path := "user://test_destination_history.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(hist_path))
	Lodestar.history_path = hist_path
	var picks: Array = []
	for i in 12:
		picks.append(str(Lodestar.draw_for_new_campaign(1000 + i).get("id", "")))
	var first_six := {}
	for i in 6:
		first_six[picks[i]] = true
	_check(first_six.size() == 6, "six campaigns, six different Destinations: %s" % str(picks.slice(0, 6)))
	for i in range(3, 12):
		_check(not picks.slice(i - 3, i).has(picks[i]), "campaign %d's Destination isn't one of the last three: %s" % [i, str(picks)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(hist_path))
	Lodestar.history_path = ""
	var ids := {}
	for card in cards:
		var id := str(card.get("id", ""))
		_check(not id.is_empty() and not ids.has(id), "unique id: %s" % id)
		ids[id] = true
		for field in ["title", "first_hint", "nova_first", "director", "arrival"]:
			_check(not str(card.get(field, "")).is_empty(), "%s has a %s" % [id, field])
		var bearings: Array = card.get("bearings", [])
		_check(bearings.size() == Lodestar.BEARINGS, "%s has five bearings" % id)
		var texts: Array[String] = [str(card["title"]), str(card["first_hint"]), str(card["nova_first"]), str(card["director"]), str(card["arrival"])]
		for b in bearings:
			_check(not str(b.get("text", "")).is_empty() and not str(b.get("nova", "")).is_empty(), "%s: every bearing has a line and N.O.V.A.'s reaction" % id)
			texts.append(str(b.get("text", "")))
			texts.append(str(b.get("nova", "")))
		_check(str(bearings[-1]["text"]).contains("past the edge of the charts"), "%s: the last bearing marks the place" % id)
		for text in texts:
			_check(ReservedTopics.is_clean(text), "%s stays clear of the fixed-cast canon: %s" % [id, ReservedTopics.find_in(text)])
			# The canon's own motifs (vision doc 5.7) stay out of the Lodestars too.
			for motif in ["callsign", "ship id", "your ship's name", "kaelen"]:
				_check(not text.to_lower().contains(motif), "%s doesn't touch '%s'" % [id, motif])

	# --- The draw and the state -------------------------------------------------
	_check(Lodestar.draw(7) == Lodestar.draw(7), "the same campaign draws the same Lodestar")
	var drawn := {}
	for seed_value in 300:
		drawn[str(Lodestar.draw(seed_value)["id"])] = true
	_check(drawn.size() == 6, "every Lodestar comes up across campaigns (%d)" % drawn.size())
	var story := {}
	var s: Dictionary = Lodestar.state(story, 99)
	_check(str(s["id"]) == str(Lodestar.draw(99)["id"]) and not bool(s["known"]) and Lodestar.bearings_found(s) == 0, "a new campaign: drawn, unknown, no bearings")
	_check(Lodestar.state(story, 12345)["id"] == s["id"], "a saved card is kept, whatever the seed says")
	story[Lodestar.STATE_KEY] = {"id": "no_such_card"}
	_check(Lodestar.card_of(Lodestar.state(story, 99)) == Lodestar.draw(99), "an unknown card is replaced")

	# --- The wedge ----------------------------------------------------------------
	for i in Lodestar.BEARINGS:
		_check(Lodestar.wedge_degrees(i + 1) < Lodestar.wedge_degrees(i), "bearing %d narrows the wedge" % (i + 1))
	_check(Lodestar.wedge_degrees(Lodestar.BEARINGS) == 0.0, "the last bearing marks the place")
	for seed_value in 200:
		var a := rad_to_deg(wrapf(Lodestar.wedge_angle(seed_value), -PI, PI))
		_check(not (a > -120.0 and a < -60.0), "the wedge never points straight up into the title bar (%.0f)" % a)
	_check(Lodestar.bearing_class(0) == 2 and Lodestar.bearing_class(4) == 6, "one bearing per class, II to VI")

	# --- N.O.V.A.'s first hint ----------------------------------------------------
	var gs: Node = root.get_node("GlobalState")
	var sm: Node = root.get_node("StoryManager")
	var saved_story: Dictionary = sm.story_state.duplicate(true)
	var saved_system := str(gs.current_system_id)
	sm.story_state.erase(Lodestar.STATE_KEY)
	var depths := {"home": 0, "next": 1}
	var guide = GuideType.new()
	guide.set_process(false)
	guide.depth_of = func(id: String) -> int: return int(depths.get(id, -1))
	root.add_child(guide)
	sm.story_state["first_contract_handed_in"] = false
	gs.current_system_id = "next"
	_check(not guide.try_introduce(), "not during the tutorial")
	sm.story_state["first_contract_handed_in"] = true
	gs.current_system_id = "home"
	_check(not guide.try_introduce(), "not at home")
	gs.current_system_id = "next"
	_check(guide.try_introduce() and bool(guide.current()["known"]), "first trip away from home: she passes on the hint")
	_check(not guide.try_introduce(), "only once")

	# --- Bearings (step 10) -------------------------------------------------------
	# Depths: 1-2 Class I, 3-4 Class II, 5-6 Class III, 7-9 Class IV.
	for id in ["d3", "d5", "d5b", "d5c", "d7", "d10", "d13"]:
		depths[id] = int(id.substr(1, 2))
	_check(guide.pending_bearing() == -1 and not guide.offer("receiver"), "no bearing in a Class I system")
	gs.current_system_id = "d3"
	_check(guide.pending_bearing() == 0, "Class II: the first bearing is waiting")
	_check(guide.offer("receiver") and Lodestar.bearings_found(guide.current()) == 1, "the receiver carries it")
	_check(not guide.offer("drone"), "one bearing per class: the next needs Class III")
	# Investigations finish as quests with investigation data.
	gs.current_system_id = "d5"
	guide._on_quest_completed({"title": "A delivery"})
	_check(Lodestar.bearings_found(guide.current()) == 1, "an ordinary job carries nothing")
	guide._on_quest_completed({"investigation": {"branch_id": "x"}})
	_check(Lodestar.bearings_found(guide.current()) == 2, "an investigation carries the Class III bearing")
	# Never missed: the second new system of the class with it still waiting.
	gs.current_system_id = "d7"
	guide.note_arrival()
	_check(Lodestar.bearings_found(guide.current()) == 2, "first Class IV system: still waiting for an activity")
	gs.current_system_id = "d7"
	guide.note_arrival()
	_check(Lodestar.bearings_found(guide.current()) == 2, "the same system again doesn't count")
	depths["d8"] = 8
	gs.current_system_id = "d8"
	guide.note_arrival()
	_check(Lodestar.bearings_found(guide.current()) == 3, "second new Class IV system: it arrives as a rumour")
	gs.current_system_id = "d10"
	_check(guide.offer("anomaly"), "Class V: an anomaly")
	gs.current_system_id = "d13"
	_check(guide.offer("kaelen") and Lodestar.bearings_found(guide.current()) == 5, "Class VI: Kaelen's lead, and that's all five")
	_check(Lodestar.wedge_degrees(Lodestar.bearings_found(guide.current())) == 0.0 and guide.pending_bearing() == -1, "the place is marked; nothing more to find")
	_check(guide.current()["bearings"] == [0, 1, 2, 3, 4], "found in order")

	# The shared entry point finds the guide on the running scene.
	_check(not GuideType.offer_from("drone"), "no game scene, no bearing (and no crash)")
	var scene_script := GDScript.new()
	scene_script.source_code = "extends Node\nvar lodestar_guide: Node = null\n"
	scene_script.reload()
	var fake_scene: Node = scene_script.new()
	root.add_child(fake_scene)
	fake_scene.lodestar_guide = guide
	current_scene = fake_scene
	sm.story_state.erase(Lodestar.STATE_KEY)
	guide.current()["known"] = true
	gs.current_system_id = "d3"
	_check(GuideType.offer_from("drone"), "an activity reaches the guide through offer_from")
	current_scene = null
	fake_scene.free()
	# Each activity is wired to it.
	for wiring in [["res://scripts/story/activities/SignalTuningActivity.gd", "receiver"], ["res://scripts/story/activities/DroneMazeActivity.gd", "drone"],
			["res://scripts/SpaceAnomaly.gd", "anomaly"], ["res://scripts/navigation/GateDiscoveryManager.gd", "kaelen"]]:
		var text := FileAccess.get_file_as_string(str(wiring[0]))
		_check(text.contains("offer_from(\"%s\")" % wiring[1]), "%s offers the %s bearing" % [str(wiring[0]).get_file(), wiring[1]])

	# The Lodestar log tab on the loose ends board.
	var board = load("res://scripts/ui/PinBoardPanel.gd").new()
	root.add_child(board)
	var card: Dictionary = Lodestar.card_of(guide.current())
	board.show_threads([], {}, {"title": card["title"], "first_hint": card["first_hint"], "bearings": [card["bearings"][0]["text"]], "found": 1, "total": 5, "next_class": "III"})
	var text: String = board.board_text()
	_check(text.contains(str(card["bearings"][0]["text"])) and text.contains("Bearings 1 of 5"), "the log shows what's been found: %s" % text.left(120))
	board.show_threads([{"id": "t1", "text": "Odd cargo"}], {}, {})
	_check(not board._tabs.visible, "no Lodestar yet, no tab")
	board.free()

	guide.free()
	gs.current_system_id = saved_system
	sm.story_state = saved_story
	if _failures.is_empty():
		print("[PASS] Lodestar")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
