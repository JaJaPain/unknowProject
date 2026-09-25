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
	rock.add_to_group("tech_seam_asteroid")
	var plain_rock := Node3D.new()
	plain_rock.add_to_group("asteroid")
	root.add_child(plain_rock)
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

	_check(ActivityType.kind_of(rock) == "asteroid" and ActivityType.kind_of(wreck) == "wreck" and ActivityType.kind_of(ship) == "", "red rocks and wrecks qualify, ships do not")
	_check(ActivityType.kind_of(plain_rock) == "", "ordinary asteroids do not")
	plain_rock.free()
	var AsteroidScript: GDScript = load("res://scripts/Asteroid.gd")
	var seams := 0
	for i in 5000:
		if AsteroidScript.is_tech_seam_id("asteroid.test.%d" % i):
			seams += 1
	_check(seams > 25 and seams < 80, "about one rock in a hundred has tech-grade seams (%d/5000)" % seams)
	_check(AsteroidScript.is_tech_seam_id("asteroid.test.1") == AsteroidScript.is_tech_seam_id("asteroid.test.1"), "fixed per rock")
	# A real red rock: tinted, drone-workable, and a laser shatters it.
	var red_id := ""
	for i in 5000:
		if AsteroidScript.is_tech_seam_id("asteroid.test.%d" % i):
			red_id = "asteroid.test.%d" % i
			break
	var real_rock: Node3D = (load("res://scenes/asteroid.tscn") as PackedScene).instantiate()
	real_rock.set("persistent_id", red_id)
	root.add_child(real_rock)
	var real_mesh := real_rock.get_node_or_null("MeshInstance3D") as MeshInstance3D
	_check(bool(real_rock.get("tech_seam")) and real_rock.is_in_group("tech_seam_asteroid"), "a red rock knows it")
	_check(real_mesh == null or real_mesh.material_overlay != null, "and is tinted red")
	_check(ActivityType.kind_of(real_rock) == "asteroid", "the drone can work it")
	var cargo_before: float = gs.cargo
	real_rock.call("mine")
	_check(bool(real_rock.get("destroyed")) and gs.cargo == cargo_before, "a mining laser shatters it and saves nothing")
	_check(ActivityType.kind_of(real_rock) == "", "and then there is nothing left to work")
	real_rock.free()
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
	_check(not view.is_ready_to_fly(), "the drone waits at the crack mouth while the rock is built")
	view.finish_loading()
	_check(view.is_ready_to_fly(), "then it can fly")
	view.state = Maze.recall(view.state)
	view._process(0.1)
	_check(not paused and _results.size() == 1 and _results[0][0] == "failed", "recalling empty-handed ends it and unpauses: %s" % str(_results))
	_check(activity.eligible_target() == null, "each asteroid is worked once")

	# Every rock carries one tech-grade material, fixed per rock.
	var mat := ActivityType.material_for(rock)
	_check(mat in ActivityType.TECH_MATERIALS and ActivityType.material_for(rock) == mat, "a rock's material is fixed: %s" % mat)

	# The haul: common ore pays a little, the material is the prize.
	var clean := Maze.start(3, "asteroid")
	for t in clean["targets"]:
		t["extracted"] = true
	clean["done"] = true
	clean["end"] = "complete"
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var h: Dictionary = ActivityType.haul("clean", clean, "rad_quartz", rng)
	_check(int(h["credits"]) == 3 * 120 + 100, "three seams and the bonus: %d" % int(h["credits"]))
	_check((h["materials"] as Array).has("rad_quartz"), "a clean run always brings home the rock's material: %s" % str(h["materials"]))
	var cracked := clean.duplicate(true)
	cracked["ore_integrity"] = 0.4
	var hc: Dictionary = ActivityType.haul("clean", cracked, "rad_quartz", rng)
	_check((hc["materials"] as Array).is_empty(), "badly cracked ore is only common ore: %s" % str(hc["materials"]))
	_check(int(hc["credits"]) == int(round(360 * 0.4)) + 100, "and sells for what survived: %d" % int(hc["credits"]))
	# Over many clean runs: about half bring a crystal; seams add more material.
	var crystals := 0
	var mats := 0
	for i in 400:
		var r: Dictionary = ActivityType.haul("clean", clean, "thermal_lattice", rng)
		crystals += (r["materials"] as Array).count("resonant_crystal")
		mats += (r["materials"] as Array).count("thermal_lattice")
	_check(crystals > 150 and crystals < 250, "a resonant crystal in about half of clean runs (%d/400)" % crystals)
	_check(mats > 600 and mats < 800, "about 1.75 of the rock's material per clean run (%d/400)" % mats)
	var credits: int = gs.player_credits
	activity._material = "cryo_ferrite"
	activity._on_finished("clean", clean, rng)
	_check(gs.player_credits == credits + 460 and gs.inventory.get_quantity("cryo_ferrite") >= 1, "the run pays out and the material is aboard")

	# A free drone from an enemy's debris, now and then.
	var drones_before: int = gs.inventory.get_quantity("survey_drone")
	activity._on_player_kill("reavers", 0.5)
	_check(gs.inventory.get_quantity("survey_drone") == drones_before, "most kills leave no drone")
	activity._on_player_kill("reavers", 0.01)
	_check(gs.inventory.get_quantity("survey_drone") == drones_before + 1, "a lucky one does")
	gs.inventory.remove("survey_drone", 1)

	# Tech-grade materials never restock (interval 0): restocking every store
	# across a long time jump must still finish (it once looped forever and
	# froze the game on the first clock tick after arriving at Iron Reach).
	var stores = load("res://scripts/economy/StoreRegistry.gd").shared()
	stores.restock_all(100)
	stores.restock_all(100000)
	_check(true, "store restock finishes")

	# Upgrades: tech-grade material at every tier, doubling; crystals at the top.
	_check(gs.upgrade_material_cost("weapons", 2) == {"thermal_lattice": 1}, "the first upgrade is cheap-ish")
	_check(gs.upgrade_material_cost("weapons", 3) == {"thermal_lattice": 2}, "the next costs more")
	_check(gs.upgrade_material_cost("shields", 4) == {"rad_quartz": 4, "resonant_crystal": 1}, "and more")
	_check(gs.upgrade_material_cost("cargo", 5) == {"cryo_ferrite": 8, "resonant_crystal": 2}, "and keeps going up")
	gs.player = null  # the fake ship has no health for the stat refresh
	var saved_upgrades: Dictionary = gs.current_upgrades.duplicate(true)
	var saved_credits: int = gs.player_credits
	var saved_ore: float = gs.player_storage_ore
	gs.current_upgrades["weapons"] = {"tier": 2, "path": "rapid"}
	gs.player_credits = 100000
	gs.player_storage_ore = 10000.0
	gs.power_capacity = 100000
	gs.inventory.remove("thermal_lattice", gs.inventory.get_quantity("thermal_lattice"))
	gs.inventory.add("thermal_lattice", 1, 10)
	_check(not gs.purchase_upgrade("weapons", "rapid"), "one short, no tier 3")
	gs.inventory.add("thermal_lattice", 1, 10)
	_check(gs.purchase_upgrade("weapons", "rapid") and gs.inventory.get_quantity("thermal_lattice") == 0, "the material is used")
	gs.current_upgrades = saved_upgrades
	gs.player_credits = saved_credits
	gs.player_storage_ore = saved_ore
	gs.apply_upgrade_stats()
	gs.player = ship

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
	var lev: Array = director.leverage_items()
	_check(lev.size() == 1 and lev[0]["kind"] == "recorder" and lev[0]["subject"] == "Ro Venn", "the recorder is leverage on the person it is about: %s" % str(lev))

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
