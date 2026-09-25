extends SceneTree

## The drone maze: seeded, connected tunnels; targets far apart; a careful
## pilot gets everything without a scratch; walls hurt; the clock and the hull
## both lose the drone; recalling keeps the load.
##   Godot --headless --path . --script res://tests/story/run_drone_maze_tests.gd --log-file <path>

const Maze := preload("res://scripts/story/activities/DroneMazeModel.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var a := Maze.start(1234, "asteroid")
	_check(a["grid"] == Maze.start(1234, "asteroid")["grid"], "same seed, same tunnels")
	_check(a["grid"] != Maze.start(99, "asteroid")["grid"], "different seed, different tunnels")
	_check(_all_cells_reachable(a["grid"]), "every chamber can be reached")
	_check((a["targets"] as Array).size() == 3, "three seams")
	for t in a["targets"]:
		_check(Maze.is_open(a["grid"], int(t["tile"][0]), int(t["tile"][1])), "targets sit in open tunnel")
	var w := Maze.start(5, "wreck", true)
	var recorders := (w["targets"] as Array).filter(func(t): return t["kind"] == "recorder")
	_check(recorders.size() == 1 and (w["targets"][0] as Dictionary)["kind"] == "recorder", "a wreck with a story has one recorder, deepest in")
	_check((Maze.start(5, "wreck", false)["targets"] as Array).all(func(t): return t["kind"] == "salvage"), "otherwise salvage")

	# A careful pilot: follow the tunnels to each target and extract it.
	for seed_value in [1234, 77, 2026]:
		for kind in ["asteroid", "wreck"]:
			var s := Maze.start(seed_value, kind, kind == "wreck")
			var hull := int(s["hull"])
			for i in (s["targets"] as Array).size():
				s = _fly_to_next(s)
			_check(Maze.outcome(s) == "clean" and s["end"] == "complete", "%s %d: everything extracted (%s, %d/%d)" % [kind, seed_value, s["end"], Maze.extracted_count(s), (s["targets"] as Array).size()])
			var spare := float(s["time_left"]) / float(s["time_total"])
			_check(spare > 0.35 and spare < 0.75, "%s %d: the clock leaves a perfect pilot about half (%.0f of %.0f s)" % [kind, seed_value, float(s["time_left"]), float(s["time_total"])])
			_check(int(s["hull"]) == hull, "%s %d: no scratches on a careful run (hull %d)" % [kind, seed_value, int(s["hull"])])

	# The scanner points the way and goes quiet when everything is out.
	var fresh := Maze.start(1234, "asteroid")
	var ping := Maze.scanner(fresh)
	_check(ping.has("bearing") and float(ping["distance"]) > 1.0 and ping["kind"] == "mineral", "the scanner points at a seam: %s" % str(ping))
	var turned := fresh.duplicate(true)
	turned["heading"] = float(fresh["heading"]) + float(ping["bearing"])
	_check(absf(float(Maze.scanner(turned)["bearing"])) < 0.001, "turning by the bearing faces the seam")

	# Cracks: the pilot stays inside them, and a drone that is still moving
	# cannot pry fragile ore loose.
	var cr := Maze.start(2026, "asteroid")
	_check(cr.has("cracks") and not Maze.start(2026, "wreck").has("cracks"), "asteroids are cracks, wrecks are corridors")
	for key in cr["cracks"]["nodes"]:
		var n: Array = cr["cracks"]["nodes"][key]
		_check(float(Maze.crack_probe(cr["cracks"], Vector2(float(n[0]), float(n[1])))["excess"]) <= 0.0, "every chamber is open rock")
	var near := cr.duplicate(true)
	var t0: Dictionary = near["targets"][0]
	var pocket := Maze.target_at(t0)
	near["pos"] = [pocket.x - 0.4, pocket.y]
	near["heading"] = 0.0
	near = Maze.step(near, 0.02, 0.5, 0.0)
	_check(Maze.extracted_count(Maze.extract(near)) == 0, "a moving drone cannot pry the ore loose")
	near = Maze.step(near, 0.02, 0.0, 0.0)
	_check(Maze.extracted_count(Maze.extract(near)) == 1, "a still one can")
	var loaded := Maze.extract(near)
	loaded["heading"] = PI * 0.5
	for i in range(60):
		loaded = Maze.step(loaded, 0.05, 1.0, 0.0)
		if bool(loaded["bumped"]):
			break
	_check(bool(loaded["bumped"]) and is_equal_approx(float(loaded["ore_integrity"]), 1.0 - Maze.ORE_CRACK_PER_KNOCK), "a knock with ore aboard cracks some of it (%.2f)" % float(loaded["ore_integrity"]))

	# Walls hurt, but not every frame.
	var b := Maze.start(1234, "asteroid")
	b["heading"] = PI  # straight into the outer wall
	var hits := 0
	for i in range(15):
		b = Maze.step(b, 0.1, 1.0, 0.0)
		if bool(b["bumped"]):
			hits += 1
	_check(hits == 2 and int(b["hull"]) == int(b["hull_max"]) - 2, "one knock per cooldown (%d)" % hits)
	_check(int(Maze.step(Maze.start(1234), 0.1, 0.3, 0.0)["hull"]) == int(b["hull_max"]), "creeping into a wall does not hurt")
	for i in range(80):
		b = Maze.step(b, 0.1, 1.0, 0.0)
	_check(b["end"] == "wrecked" and Maze.outcome(b) == "failed", "too many knocks lose the drone")

	# The clock loses it too, load and all.
	var c := _fly_to_next(Maze.start(77, "asteroid"))
	_check(Maze.extracted_count(c) == 1, "one seam taken")
	var recalled := Maze.recall(c)
	_check(Maze.outcome(recalled) == "partial", "recalling keeps the load")
	c = Maze.step(c, 999.0, 0.0, 0.0)
	_check(c["end"] == "timed_out" and Maze.outcome(c) == "failed", "out of time, the drone and its load are lost")
	_check(Maze.extract(Maze.start(77))["targets"] == Maze.start(77)["targets"], "nothing in reach, nothing taken")

	if _failures.is_empty():
		print("[PASS] Drone maze model")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _all_cells_reachable(grid: Array) -> bool:
	var seen := {Vector2i(1, 1): true}
	var queue: Array[Vector2i] = [Vector2i(1, 1)]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and Maze.is_open(grid, n.x, n.y):
				seen[n] = true
				queue.append(n)
	for y in range(1, grid.size(), 2):
		for x in range(1, str(grid[y]).length(), 2):
			if not seen.has(Vector2i(x, y)):
				return false
	return true


## Steer along the tunnels to the nearest unextracted target, settle, and
## extract it.
func _fly_to_next(state: Dictionary) -> Dictionary:
	var s := state
	var route: Array = []
	for t in s["targets"]:
		if bool(t["extracted"]):
			continue
		var r := Maze.route_to(s, Maze.target_at(t))
		if route.is_empty() or r.size() < route.size():
			route = r
	for aim: Vector2 in route:
		for i in range(400):
			var here := Vector2(float(s["pos"][0]), float(s["pos"][1]))
			var to := aim - here
			if to.length() < 0.08:
				break
			var diff := wrapf(to.angle() - float(s["heading"]), -PI, PI)
			var turn := clampf(diff * 4.0, -1.0, 1.0)
			var throttle := clampf(to.length() * 3.0, 0.0, 1.0) if absf(diff) < 0.15 else 0.0
			s = Maze.step(s, 0.02, throttle, turn)
	# Hold still, then take it (fragile ore only comes loose for a still drone).
	s = Maze.step(s, 0.02, 0.0, 0.0)
	return Maze.extract(s)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
