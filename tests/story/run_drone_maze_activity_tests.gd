extends SceneTree

## The drone maze in the game: which targets qualify, each worked once, the
## view pauses the game and gives it back, and the haul, a lost drone and a
## wreck's flight recorder pay out as they should.
##   Godot --headless --path . --script res://tests/story/run_drone_maze_activity_tests.gd --log-file <path> -- --baseline-offline

const ActivityType := preload("res://scripts/story/activities/DroneMazeActivity.gd")
const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const Maze := preload("res://scripts/story/activities/DroneMazeModel.gd")

var _failures: Array[String] = []
var _results: Array = []


class FakeShip extends CharacterBody3D:
	var is_docked := false
	var destroyed := false


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GlobalState")
	var saved_player = gs.player
	var ship := FakeShip.new()
	root.add_child(ship)
	gs.player = ship
	var rock := Node3D.new()
	rock.add_to_group("asteroid")
	root.add_child(rock)
	rock.global_position = Vector3(100, 0, 0)
	var wreck := StaticBody3D.new()
	wreck.set_script(load("res://scripts/Wreckage.gd"))
	root.add_child(wreck)
	wreck.global_position = Vector3(0, 0, 120)

	var director = DirectorType.new()
	root.add_child(director)
	director.state["arcs"] = {"arc.1": {"system_id": "sys.a", "cast": {"pilot": {"kind": "person", "entity_id": "npc.p", "display_name": "Ro Venn"}}}}
	director.state["main_story"] = {"stage": "gathering", "threads": [
		{"id": "th.0001", "arc_id": "arc.1", "surface": "wreck", "detail": "{role:pilot} logged a course nobody filed.", "seen": false, "pinned": false, "trace": true}]}
	var activity = ActivityType.new()
	activity.director = director
	activity.world_provider = func() -> Dictionary: return {"system_id": "sys.a"}
	root.add_child(activity)
	activity.set_process(false)

	_check(ActivityType.kind_of(rock) == "asteroid" and ActivityType.kind_of(wreck) == "wreck" and ActivityType.kind_of(ship) == "", "asteroids and wrecks qualify, ships do not")
	gs.active_target = rock
	_check(activity.eligible_target() == rock, "a close asteroid can be worked")
	rock.global_position = Vector3(1000, 0, 0)
	_check(activity.eligible_target() == null, "not from across the system")
	rock.global_position = Vector3(100, 0, 0)
	ship.is_docked = true
	_check(activity.eligible_target() == null, "not while docked")
	ship.is_docked = false

	# No drone, no flight; each flight uses one up.
	gs.inventory.clear()
	_check(not activity.launch(rock) and activity._view == null, "no survey drone, no launch")
	_check(activity.eligible_target() == rock, "a refused launch does not use up the asteroid")
	gs.inventory.add("survey_drone", 2)
	# The view pauses the game, and recalling gives it back.
	_check(activity.launch(rock), "a drone aboard launches")
	_check(gs.inventory.get_quantity("survey_drone") == 1, "the launch uses one drone")
	var view = activity._view
	_check(view != null and paused, "flying the drone pauses the game")
	view.finished.connect(func(o: String, s: Dictionary) -> void: _results.append([o, s]))
	view.state = Maze.recall(view.state)
	view._process(0.1)
	_check(not paused and _results.size() == 1 and _results[0][0] == "failed", "recalling empty-handed ends it and unpauses: %s" % str(_results))
	_check(activity.eligible_target() == null, "each asteroid is worked once")

	# The haul pays; a clean run pays a bonus.
	var credits: int = gs.player_credits
	var clean := Maze.start(3, "asteroid")
	for t in clean["targets"]:
		t["extracted"] = true
	clean["done"] = true
	clean["end"] = "complete"
	activity._on_finished("clean", clean)
	_check(gs.player_credits == credits + 3 * 70 + 60, "three seams and the bonus: %d" % (gs.player_credits - credits))

	# A lost drone pays nothing for its load (the drone itself was the cost).
	credits = gs.player_credits
	var lost := clean.duplicate(true)
	lost["end"] = "wrecked"
	activity._on_finished("failed", lost)
	_check(gs.player_credits == credits, "a lost drone's load is lost")

	# A wreck in a system with a wreck clue holds the recorder.
	gs.active_target = wreck
	activity.launch(wreck)
	_check(gs.inventory.get_quantity("survey_drone") == 0, "home or lost, every flight used one")
	var wreck_view = activity._view
	var recorders := (wreck_view.state["targets"] as Array).filter(func(t): return t["kind"] == "recorder")
	_check(recorders.size() == 1, "the wreck holds a flight recorder")
	for t in wreck_view.state["targets"]:
		t["extracted"] = t["kind"] == "recorder"
	wreck_view.state = Maze.recall(wreck_view.state)
	wreck_view._process(0.1)
	var threads: Array = director.main_story_threads()
	_check(threads.size() == 1 and str(threads[0]["text"]).contains("Ro Venn"), "the recorder's clue is on the Loose ends board: %s" % str(threads))
	_check(director.recorder_thread({"system_id": "sys.a"}).is_empty(), "and no second wreck carries it")

	paused = false
	activity.free()
	director.free()
	gs.active_target = null
	gs.player = saved_player
	ship.free()
	rock.free()
	wreck.free()
	if _failures.is_empty():
		print("[PASS] Drone maze activity")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
