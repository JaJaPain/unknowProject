extends RefCounted

## The drone maze (Abe's micro-mining idea, rebuilt here): the captain flies a
## mining drone through tunnels in first person, against a countdown, finds the
## targets and extracts them. Hitting walls damages the drone. If the hull or
## the clock runs out, the drone is lost with its load; recalling it early
## keeps what it carries.
##
## Two kinds: "asteroid" (mineral seams) and "wreck" (salvage, and sometimes a
## recorder that carries a story thread).
##
## PURE and seeded. The maze is a tile grid: odd tiles are corridors, walls are
## whole tiles, one tile = one metre-ish unit. The view builds boxes from it.

const WALL := "#"
const OPEN := "."

const SPEED := 1.7            # tiles per second at full throttle
const TURN_SPEED := 2.4       # radians per second
const RADIUS := 0.22          # the drone, in tiles
const BUMP_SPEED := 0.6       # throttle needed for a knock to count
const BUMP_COOLDOWN := 0.8
const EXTRACT_RANGE := 0.95
const EXTRACT_FACING := 0.45  # cos of the widest angle it can grab at

const KINDS := {
	"asteroid": {"cells": Vector2i(7, 7), "targets": 3, "hull": 5, "loops": 0.15},
	"wreck": {"cells": Vector2i(6, 8), "targets": 3, "hull": 4, "loops": 0.08},
}
## The countdown comes from the maze itself: the shortest tour of every target
## at full speed, times this, plus a margin. Fair on a long maze, tense on a
## short one. The captain explores; the tour assumes they already know the way.
const TIME_PER_TOUR := 2.2
const TIME_MARGIN := 20.0


static func start(seed_value: int, kind: String = "asteroid", with_recorder: bool = false) -> Dictionary:
	var spec: Dictionary = KINDS.get(kind, KINDS["asteroid"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cells: Vector2i = spec["cells"]
	var grid := _carve(cells, rng, float(spec["loops"]))
	var start_tile := Vector2i(1, 1)
	var targets: Array = []
	var far := _far_cells(grid, start_tile)
	var count := int(spec["targets"])
	for i in mini(count, far.size()):
		var t: Vector2i = far[i]
		var target_kind := "mineral" if kind == "asteroid" else "salvage"
		# The farthest spot in a wreck holds the recorder, when there is one.
		if kind == "wreck" and with_recorder and i == 0:
			target_kind = "recorder"
		targets.append({"id": "target.%d" % i, "tile": [t.x, t.y], "kind": target_kind, "extracted": false})
	# Face down the first open corridor.
	var time_total := TIME_MARGIN + TIME_PER_TOUR * float(_tour_length(grid, start_tile, targets)) / SPEED
	var heading := 0.0
	if grid[1][2] == OPEN:
		heading = 0.0
	elif grid[2][1] == OPEN:
		heading = PI * 0.5
	return {
		"seed": seed_value, "kind": kind, "grid": grid,
		"pos": [start_tile.x + 0.5, start_tile.y + 0.5], "heading": heading,
		"targets": targets, "time_left": time_total, "time_total": time_total,
		"hull": int(spec["hull"]), "hull_max": int(spec["hull"]), "bump_cooldown": 0.0,
		"done": false, "end": "",
	}


## Recursive backtracker on a cells.x by cells.y cell grid, then a share of
## dead ends knocked through so the tunnels loop a little.
static func _carve(cells: Vector2i, rng: RandomNumberGenerator, loops: float) -> Array:
	var w := cells.x * 2 + 1
	var h := cells.y * 2 + 1
	var rows: Array = []
	for y in h:
		var row: Array = []
		row.resize(w)
		row.fill(WALL)
		rows.append(row)
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	var seen := {Vector2i(0, 0): true}
	rows[1][1] = OPEN
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for d: Vector2i in dirs:
			var n := c + d
			if n.x >= 0 and n.y >= 0 and n.x < cells.x and n.y < cells.y and not seen.has(n):
				options.append(n)
		if options.is_empty():
			stack.pop_back()
			continue
		var n := options[rng.randi() % options.size()]
		seen[n] = true
		rows[c.y * 2 + 1 + (n.y - c.y)][c.x * 2 + 1 + (n.x - c.x)] = OPEN
		rows[n.y * 2 + 1][n.x * 2 + 1] = OPEN
		stack.append(n)
	# Loops: open some interior walls between two corridors.
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if rows[y][x] != WALL or rng.randf() >= loops:
				continue
			var horizontal: bool = rows[y][x - 1] == OPEN and rows[y][x + 1] == OPEN and rows[y - 1][x] == WALL and rows[y + 1][x] == WALL
			var vertical: bool = rows[y - 1][x] == OPEN and rows[y + 1][x] == OPEN and rows[y][x - 1] == WALL and rows[y][x + 1] == WALL
			if horizontal or vertical:
				rows[y][x] = OPEN
	var out: Array = []
	for row in rows:
		out.append("".join(PackedStringArray(row)))
	return out


## Cell centres (odd tiles), farthest first by walking distance from `from`.
static func _far_cells(grid: Array, from: Vector2i) -> Array:
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not dist.has(n) and is_open(grid, n.x, n.y):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	var centres: Array = []
	for c: Vector2i in dist.keys():
		if c.x % 2 == 1 and c.y % 2 == 1 and c != from:
			centres.append(c)
	centres.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return int(dist[a]) > int(dist[b]) or (int(dist[a]) == int(dist[b]) and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	# Spread them out: no two targets in neighbouring cells.
	var picked: Array = []
	for c: Vector2i in centres:
		var close := false
		for p: Vector2i in picked:
			if absi(p.x - c.x) + absi(p.y - c.y) <= 2:
				close = true
		if not close:
			picked.append(c)
	return picked


## Tiles walked visiting every target, nearest first, from `from`.
static func _tour_length(grid: Array, from: Vector2i, targets: Array) -> int:
	var total := 0
	var here := from
	var left: Array = targets.duplicate()
	while not left.is_empty():
		var dist := _distances(grid, here)
		var best := 0
		for i in left.size():
			var t: Vector2i = Vector2i(int(left[i]["tile"][0]), int(left[i]["tile"][1]))
			var b: Vector2i = Vector2i(int(left[best]["tile"][0]), int(left[best]["tile"][1]))
			if int(dist.get(t, 9999)) < int(dist.get(b, 9999)):
				best = i
		var chosen := Vector2i(int(left[best]["tile"][0]), int(left[best]["tile"][1]))
		total += int(dist.get(chosen, 0))
		here = chosen
		left.remove_at(best)
	return total


static func _distances(grid: Array, from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not dist.has(n) and is_open(grid, n.x, n.y):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	return dist


## The drone's scanner: bearing (radians, relative to the nose; negative is
## left) and straight-line distance to the nearest target still in the rock.
## {} once everything is out.
static func scanner(state: Dictionary) -> Dictionary:
	var pos := Vector2(float(state["pos"][0]), float(state["pos"][1]))
	var best := {}
	for t in state["targets"]:
		if bool(t["extracted"]):
			continue
		var to := Vector2(float(t["tile"][0]) + 0.5, float(t["tile"][1]) + 0.5) - pos
		if best.is_empty() or to.length() < float(best["distance"]):
			best = {"distance": to.length(), "bearing": wrapf(to.angle() - float(state["heading"]), -PI, PI), "kind": str(t["kind"])}
	return best


static func is_open(grid: Array, x: int, y: int) -> bool:
	return y >= 0 and y < grid.size() and x >= 0 and x < str(grid[y]).length() and str(grid[y])[x] == OPEN


## Advance: `throttle` -1..1 (back/forward), `turn` -1..1 (left/right).
static func step(state: Dictionary, dt: float, throttle: float, turn: float) -> Dictionary:
	var s := state.duplicate(true)
	if bool(s["done"]):
		return s
	s["time_left"] = maxf(0.0, float(s["time_left"]) - dt)
	s["bump_cooldown"] = maxf(0.0, float(s["bump_cooldown"]) - dt)
	s["heading"] = fposmod(float(s["heading"]) + clampf(turn, -1.0, 1.0) * TURN_SPEED * dt, TAU)
	var h := float(s["heading"])
	var move := Vector2(cos(h), sin(h)) * clampf(throttle, -1.0, 1.0) * SPEED * dt
	var pos := Vector2(float(s["pos"][0]), float(s["pos"][1]))
	var blocked := false
	# Axis by axis, so the drone slides along a wall instead of sticking.
	var nx := Vector2(pos.x + move.x, pos.y)
	if _hits(s["grid"], nx):
		blocked = move.x != 0.0
	else:
		pos = nx
	var ny := Vector2(pos.x, pos.y + move.y)
	if _hits(s["grid"], ny):
		blocked = blocked or move.y != 0.0
	else:
		pos = ny
	s["pos"] = [pos.x, pos.y]
	if blocked and absf(throttle) >= BUMP_SPEED and float(s["bump_cooldown"]) <= 0.0:
		s["hull"] = int(s["hull"]) - 1
		s["bump_cooldown"] = BUMP_COOLDOWN
		s["bumped"] = true
	else:
		s["bumped"] = false
	if int(s["hull"]) <= 0:
		s["done"] = true
		s["end"] = "wrecked"
	elif float(s["time_left"]) <= 0.0:
		s["done"] = true
		s["end"] = "timed_out"
	return s


## True if a drone at `p` overlaps a wall tile.
static func _hits(grid: Array, p: Vector2) -> bool:
	for y in range(int(floor(p.y - RADIUS)), int(floor(p.y + RADIUS)) + 1):
		for x in range(int(floor(p.x - RADIUS)), int(floor(p.x + RADIUS)) + 1):
			if is_open(grid, x, y):
				continue
			var nearest := Vector2(clampf(p.x, x, x + 1.0), clampf(p.y, y, y + 1.0))
			if nearest.distance_to(p) < RADIUS:
				return true
	return false


## The unextracted target in reach and in front of the drone, or {}.
static func target_in_reach(state: Dictionary) -> Dictionary:
	var pos := Vector2(float(state["pos"][0]), float(state["pos"][1]))
	var facing := Vector2(cos(float(state["heading"])), sin(float(state["heading"])))
	for t in state["targets"]:
		if bool(t["extracted"]):
			continue
		var at := Vector2(float(t["tile"][0]) + 0.5, float(t["tile"][1]) + 0.5)
		var to := at - pos
		if to.length() <= EXTRACT_RANGE and (to.length() < 0.3 or facing.dot(to.normalized()) >= EXTRACT_FACING):
			return t
	return {}


static func extract(state: Dictionary) -> Dictionary:
	var s := state.duplicate(true)
	if bool(s["done"]):
		return s
	var t := target_in_reach(s)
	if t.is_empty():
		return s
	for target in s["targets"]:
		if str(target["id"]) == str(t["id"]):
			target["extracted"] = true
	if extracted_count(s) == (s["targets"] as Array).size():
		s["done"] = true
		s["end"] = "complete"
	return s


## The captain calls the drone back with what it has.
static func recall(state: Dictionary) -> Dictionary:
	var s := state.duplicate(true)
	if not bool(s["done"]):
		s["done"] = true
		s["end"] = "recalled"
	return s


static func extracted_count(state: Dictionary) -> int:
	var n := 0
	for t in state["targets"]:
		if bool(t["extracted"]):
			n += 1
	return n


static func has_extracted(state: Dictionary, target_kind: String) -> bool:
	for t in state["targets"]:
		if bool(t["extracted"]) and str(t["kind"]) == target_kind:
			return true
	return false


## "clean" (everything), "partial" (some, drone home) or "failed" (nothing
## home: nothing found, or the drone lost with its load).
static func outcome(state: Dictionary) -> String:
	if str(state["end"]) in ["wrecked", "timed_out"]:
		return "failed"
	var n := extracted_count(state)
	if n == 0:
		return "failed"
	return "clean" if n == (state["targets"] as Array).size() else "partial"
