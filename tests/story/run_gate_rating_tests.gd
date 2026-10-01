extends SceneTree

## The gate ladder in play: Class I free, Class II needs hardened shields and
## N.O.V.A. walks the captain through getting them (a first drone as an
## advance, the red rock, the mechanic, done); higher classes need a Ship
## Rating and she explains each once; back is always open, deeper always
## checks.
##   Godot --headless --path . --script res://tests/story/run_gate_rating_tests.gd --log-file <path> -- --baseline-offline

const GuideType := preload("res://scripts/story/GateRatingGuide.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GlobalState")
	var saved_upgrades: Dictionary = gs.current_upgrades.duplicate(true)
	var saved_target = gs.active_target
	gs.current_upgrades["shields"] = {"tier": 1, "path": "base"}
	gs.inventory.remove("survey_drone", gs.inventory.get_quantity("survey_drone"))
	gs.inventory.remove("rad_quartz", gs.inventory.get_quantity("rad_quartz"))
	var depths := {"sys.start": 0, "sys.one": 1, "sys.two": 2, "sys.three": 3, "sys.far": 5}
	var here := ["sys.one"]
	var guide = GuideType.new()
	guide.set_process(false)
	guide.depth_of = func(id: String) -> int: return int(depths.get(id, -1))
	guide.current_system_of = func() -> String: return here[0]
	root.add_child(guide)

	_check(guide.block_reason("sys.two") == "", "the first jumps are free")
	here[0] = "sys.two"
	_check(guide.block_reason("sys.three") == GuideType.BLOCK_REASON, "the third gate needs hardened shields")
	_check(guide.block_reason("sys.one") == "", "going back is always allowed")
	_check(guide.stage() == "", "asking is not trying: no walkthrough yet")

	var story: Node = root.get_node("StoryManager")
	var saved_goal = story.story_state.get("upgrade_goal", {})
	var saved_credits: int = gs.player_credits
	var saved_bank: float = gs.player_storage_ore
	gs.player_credits = 0
	gs.player_storage_ore = 0.0
	guide.on_refused()
	_check(guide.stage() == "need_material", "trying the gate starts the walkthrough")
	_check(gs.inventory.get_quantity("survey_drone") == 1, "with a first drone as an advance")
	var goal: Dictionary = story.story_state.get("upgrade_goal", {})
	_check(str(goal.get("sys", "")) == "shields" and int(goal.get("tier", 0)) == 2 and not bool(goal.get("auto", true)),
		"and Shields Mk II becomes the goal on the card: %s" % str(goal))
	var bill: String = guide._cost_line()
	_check(bill.contains("credits") and bill.contains("ore"), "she names the rest of the bill: %s" % bill)
	guide.on_refused()
	_check(gs.inventory.get_quantity("survey_drone") == 1, "only once")

	var red := Node3D.new()
	red.add_to_group("tech_seam_asteroid")
	root.add_child(red)
	gs.active_target = red
	guide.advance()
	_check(bool(guide.to_dict()["red_rock_told"]), "she points out the red rock")

	gs.inventory.add("rad_quartz", 1, 10)
	guide.advance()
	_check(guide.stage() == "need_material" and bool(guide.to_dict()["material_told"]),
		"rad-quartz alone isn't the whole bill: she says what's still short")
	var data: Dictionary = gs.UPGRADE_TREE["shields"]["branches"][str(goal.get("path", "bulwark"))][2]
	gs.player_credits = int(data["cost_cr"])
	gs.player_storage_ore = float(data["cost_ore"])
	guide.advance()
	_check(guide.stage() == "need_fit", "with the whole bill covered, off to the mechanic")

	var saved: Dictionary = guide.to_dict()
	var reloaded = GuideType.new()
	reloaded.load_from_dict(saved)
	_check(reloaded.stage() == "need_fit" and reloaded.to_dict() == saved, "the walkthrough survives a save")
	reloaded.free()

	gs.current_upgrades["shields"] = {"tier": 2, "path": "bulwark"}
	guide.advance()
	_check(guide.stage() == "done", "fitted: the gates open")
	_check(guide.block_reason("sys.three") == "", "Class II opens")
	# Class III (depth 5) needs Ship Rating 8; shields Mk II alone rates 6.
	for sys in ["weapons", "engine", "mining", "cargo"]:
		gs.current_upgrades[sys] = {"tier": 1, "path": "base"}
	here[0] = "sys.three"
	var refusal: String = guide.block_reason("sys.far")
	_check(refusal.begins_with("Class III") and guide.is_rating_block(refusal), "Class III wants a rating: %s" % refusal)
	guide.on_refused()
	_check((guide.to_dict()["classes_told"] as Array).has(3), "she explains Class III once")
	gs.current_upgrades["weapons"] = {"tier": 2, "path": "rapid"}
	gs.current_upgrades["mining"] = {"tier": 2, "path": "rapid"}
	_check(guide.block_reason("sys.far") == "", "rating 8 opens Class III")
	gs.current_upgrades["weapons"] = {"tier": 1, "path": "base"}
	here[0] = "sys.far"
	_check(guide.block_reason("sys.one") == "", "a refund still lets the ship go back")
	here[0] = "sys.three"
	_check(guide.block_reason("sys.far") != "", "but going deeper again checks, even somewhere visited")

	var fresh = GuideType.new()
	fresh.set_process(false)
	root.add_child(fresh)
	fresh.advance()
	_check(fresh.stage() == "done", "a captain who upgraded early never hears about it")

	gs.active_target = saved_target
	gs.current_upgrades = saved_upgrades
	gs.player_credits = saved_credits
	gs.player_storage_ore = saved_bank
	story.story_state["upgrade_goal"] = saved_goal
	gs.inventory.remove("survey_drone", gs.inventory.get_quantity("survey_drone"))
	gs.inventory.remove("rad_quartz", gs.inventory.get_quantity("rad_quartz"))
	red.free()
	guide.free()
	fresh.free()
	if _failures.is_empty():
		print("[PASS] Gate rating guide")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
