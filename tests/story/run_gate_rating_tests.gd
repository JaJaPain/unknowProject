extends SceneTree

## The deeper gates need hardened shields, and N.O.V.A. walks the captain
## through getting them: free for the first systems, never blocks the way
## back, a first drone as an advance, the red rock, the mechanic, done.
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
	var guide = GuideType.new()
	guide.set_process(false)
	root.add_child(guide)

	guide.note_system("sys.start")
	guide.note_system("sys.one")
	_check(guide.block_reason("sys.two") == "", "the first jumps are free")
	guide.note_system("sys.two")
	_check(guide.block_reason("sys.three") == GuideType.BLOCK_REASON, "the third gate needs hardened shields")
	_check(guide.block_reason("sys.one") == "", "going back is always allowed")
	_check(guide.stage() == "", "asking is not trying: no walkthrough yet")

	guide.on_refused()
	_check(guide.stage() == "need_material", "trying the gate starts the walkthrough")
	_check(gs.inventory.get_quantity("survey_drone") == 1, "with a first drone as an advance")
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
	_check(guide.stage() == "need_fit", "with the rad-quartz aboard, off to the mechanic")

	var saved: Dictionary = guide.to_dict()
	var reloaded = GuideType.new()
	reloaded.load_from_dict(saved)
	_check(reloaded.stage() == "need_fit" and reloaded.to_dict() == saved, "the walkthrough survives a save")
	reloaded.free()

	gs.current_upgrades["shields"] = {"tier": 2, "path": "bulwark"}
	guide.advance()
	_check(guide.stage() == "done", "fitted: the gates open")
	_check(guide.block_reason("sys.far") == "", "and stay open")

	var fresh = GuideType.new()
	fresh.set_process(false)
	root.add_child(fresh)
	fresh.advance()
	_check(fresh.stage() == "done", "a captain who upgraded early never hears about it")

	gs.active_target = saved_target
	gs.current_upgrades = saved_upgrades
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
