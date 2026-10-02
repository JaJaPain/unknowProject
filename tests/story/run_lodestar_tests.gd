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
	await process_frame
	# --- The deck ---------------------------------------------------------------
	var cards: Array = Lodestar.deck()
	_check(cards.size() == 6, "six Lodestars (%d)" % cards.size())
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
