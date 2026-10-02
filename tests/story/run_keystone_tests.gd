extends SceneTree

## Core loop step 8: the keystone. One requirement per campaign for the deep
## gates (Class IV on), drawn from a deck of five; N.O.V.A. hints at it early
## (a rumour at depth 4-5, the reveal at depth 6), explains it at the first
## refusal, makes it the goal, and says when it's fitted. Back stays open.
##   Godot --headless --path . --script res://tests/story/run_keystone_tests.gd --log-file <path> -- --baseline-offline

const Keystone := preload("res://scripts/domain/Keystone.gd")
const GateClass := preload("res://scripts/domain/GateClass.gd")
const GuideType := preload("res://scripts/story/GateRatingGuide.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	# --- The deck and the draw ------------------------------------------------
	_check(Keystone.DECK.size() == 5, "five keystones")
	var systems := {}
	for card in Keystone.DECK:
		for field in ["id", "name", "sys", "reason", "rumour", "reveal", "refusal"]:
			_check(not str(card.get(field, "")).is_empty(), "%s has a %s" % [card.get("id", "?"), field])
		_check(str(card["sys"]) in GateClass.RATED_SYSTEMS, "%s asks for a rated system" % card["id"])
		systems[str(card["sys"])] = true
	_check(systems.size() == 5, "each keystone asks for a different system")
	_check(Keystone.draw(42) == Keystone.draw(42), "the same campaign always draws the same keystone")
	var drawn := {}
	for s in 200:
		drawn[str(Keystone.draw(s)["id"])] = true
	_check(drawn.size() == 5, "over many campaigns every keystone comes up (%d)" % drawn.size())

	# --- The gate rule, for every card ---------------------------------------
	for card in Keystone.DECK:
		var id := str(card["id"])
		var sys := str(card["sys"])
		# Rating 11 with the keystone system kept at Mk II: 3+2+2+2+2.
		var tiers := {"weapons": 3, "engine": 3, "shields": 3, "mining": 3, "cargo": 3}
		tiers[sys] = 2
		_check(GateClass.ship_rating(tiers) >= 11, "%s: the test ship rates 11+" % id)
		_check(bool(GateClass.check(5, 6, tiers, card)["ok"]), "%s: Class III doesn't ask for it" % id)
		var deep: Dictionary = GateClass.check(6, 7, tiers, card)
		_check(not bool(deep["ok"]) and bool(deep["needs_keystone"]), "%s: Class IV refuses without %s Mk III" % [id, sys])
		_check(not bool(GateClass.check(9, 10, tiers, card)["ok"]), "%s: and so does every class past it" % id)
		_check(bool(GateClass.check(7, 6, tiers, card)["ok"]), "%s: back is always open" % id)
		tiers[sys] = 3
		_check(bool(GateClass.check(6, 7, tiers, card)["ok"]), "%s: with %s Mk III and the rating, Class IV opens" % [id, sys])
		_check(not bool(GateClass.check(6, 7, {"weapons": 1, "engine": 1, "shields": 3, "mining": 1, "cargo": 1}, card)["ok"]), "%s: the keystone alone isn't the rating" % id)
	_check(bool(GateClass.check(6, 7, {"weapons": 3, "engine": 3, "shields": 3, "mining": 2, "cargo": 2}, {})["ok"]), "no card, no keystone rule")

	# --- N.O.V.A. and the guide ------------------------------------------------
	var gs: Node = root.get_node("GlobalState")
	var story: Node = root.get_node("StoryManager")
	var saved_upgrades: Dictionary = gs.current_upgrades.duplicate(true)
	var saved_goal = story.story_state.get("upgrade_goal", {})
	var card: Dictionary = Keystone.by_id("gravity_shear")
	var depths := {"sys.a": 3, "sys.b": 4, "sys.c": 5, "sys.d": 6, "sys.deep": 7}
	var here := ["sys.d"]
	var guide = GuideType.new()
	guide.set_process(false)
	guide.depth_of = func(id: String) -> int: return int(depths.get(id, -1))
	guide.current_system_of = func() -> String: return here[0]
	guide.keystone_of = func() -> Dictionary: return card
	root.add_child(guide)
	# What she has said shows in to_dict()["keystone_told"].
	for sys in ["weapons", "shields", "mining", "cargo"]:
		gs.current_upgrades[sys] = {"tier": 3, "path": _path(gs, sys)}
	gs.current_upgrades["engine"] = {"tier": 2, "path": _path(gs, "engine")}

	guide.note_system("sys.a")
	_check(not (guide.to_dict()["keystone_told"] as Array).has("rumour"), "nothing at depth 3")
	guide.note_system("sys.b")
	_check((guide.to_dict()["keystone_told"] as Array).has("rumour"), "a rumour on first reaching depth 4")
	guide.note_system("sys.c")
	_check((guide.to_dict()["keystone_told"] as Array).count("rumour") == 1, "only once")
	guide.note_system("sys.d")
	_check((guide.to_dict()["keystone_told"] as Array).has("reveal"), "the reveal at depth 6")
	_check(guide.known_keystone() == card, "the captain now knows it")

	var label: String = guide.access_to("sys.deep")["label"]
	_check(label.contains("Engine Mk III") and label.begins_with("Class IV"), "the gate label names it: %s" % label)
	var reason: String = guide.block_reason("sys.deep")
	_check(reason.begins_with("Class IV") and reason.contains("Engine Mk III") and guide.is_rating_block(reason), "the refusal names it: %s" % reason)
	var rung: Dictionary = guide.next_rung()
	_check(int(rung["next_class"]) == 4 and bool(rung["needs_keystone"]), "the HUD's next rung is Class IV + the keystone: %s" % str(rung))
	guide.on_refused()
	_check((guide.to_dict()["keystone_told"] as Array).has("refusal"), "she explains it at the first refusal")
	var goal: Dictionary = story.story_state.get("upgrade_goal", {})
	_check(str(goal.get("sys", "")) == "engine" and int(goal.get("tier", 0)) == 3, "and Engine Mk III becomes the goal: %s" % str(goal))
	here[0] = "sys.deep"
	_check(guide.block_reason("sys.d") == "", "the way back is open")
	here[0] = "sys.d"

	gs.current_upgrades["engine"] = {"tier": 3, "path": _path(gs, "engine")}
	_check(guide.block_reason("sys.deep") == "", "with Engine Mk III the deep gate opens")
	guide._keystone_met_check()
	_check((guide.to_dict()["keystone_told"] as Array).has("met"), "she says when it's fitted")
	var saved: Dictionary = guide.to_dict()
	var reloaded = GuideType.new()
	reloaded.load_from_dict(saved)
	_check(reloaded.to_dict() == saved, "what she's said survives a save")
	reloaded.free()

	# A ship that already has it hears no rumour.
	var ready = GuideType.new()
	ready.set_process(false)
	ready.depth_of = guide.depth_of
	ready.keystone_of = guide.keystone_of
	root.add_child(ready)
	ready.note_system("sys.b")
	_check((ready.to_dict()["keystone_told"] as Array).is_empty(), "a ship that already has it hears nothing")

	gs.current_upgrades = saved_upgrades
	gs.apply_upgrade_stats()
	story.story_state["upgrade_goal"] = saved_goal
	guide.free()
	ready.free()
	if _failures.is_empty():
		print("[PASS] Keystone")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


## Any real branch of `sys` (tests only need the tier).
func _path(gs: Node, sys: String) -> String:
	return str((gs.UPGRADE_TREE[sys]["branches"] as Dictionary).keys()[0])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
