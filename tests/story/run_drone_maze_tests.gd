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


## Steer along the shortest tunnel path to the nearest unextracted target,
## then extract it.
func _fly_to_next(state: Dictionary) -> Dictionary:
	var s := state
	var pos := Vector2i(int(floor(float(s["pos"][0]))), int(floor(float(s["pos"][1]))))
	var goal := Vector2i(-1, -1)
	var path: Array[Vector2i] = []
	for t in s["targets"]:
		if bool(t["extracted"]):
			continue
		var p := _path(s["grid"], pos, Vector2i(int(t["tile"][0]), int(t["tile"][1])))
		if goal.x < 0 or p.size() < path.size():
			goal = Vector2i(int(t["tile"][0]), int(t["tile"][1]))
			path = p
	for tile: Vector2i in path:
		var aim := Vector2(tile.x + 0.5, tile.y + 0.5)
		for i in range(400):
			var here := Vector2(float(s["pos"][0]), float(s["pos"][1]))
			var to := aim - here
			if to.length() < 0.08:
				break
			var diff := wrapf(to.angle() - float(s["heading"]), -PI, PI)
			var turn := clampf(diff * 4.0, -1.0, 1.0)
			var throttle := clampf(to.length() * 3.0, 0.0, 1.0) if absf(diff) < 0.15 else 0.0
			s = Maze.step(s, 0.02, throttle, turn)
	# Face the target and take it.
	return Maze.extract(s)


func _path(grid: Array, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not prev.has(n) and Maze.is_open(grid, n.x, n.y):
				prev[n] = c
				queue.append(n)
	var out: Array[Vector2i] = []
	var c := to
	while c != from:
		out.push_front(c)
		c = prev[c]
	return out


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
