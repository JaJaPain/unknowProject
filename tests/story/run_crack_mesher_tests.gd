extends SceneTree

## The crack mesh: it builds, it faces into the cave, it is fast enough to
## build while the drone goes in, and no rock sits inside the space the drone
## may fly through (so the camera never sees inside a wall).
##   Godot --headless --path . --script res://tests/story/run_crack_mesher_tests.gd --log-file <path>

const Maze := preload("res://scripts/story/activities/DroneMazeModel.gd")
const Mesher := preload("res://scripts/story/activities/CrackMesher.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	for seed_value in [1234, 77]:
		var state := Maze.start(seed_value, "asteroid")
		var started := Time.get_ticks_msec()
		var built := Mesher.build(state["cracks"], seed_value)
		var ms := Time.get_ticks_msec() - started
		var verts: PackedVector3Array = built["vertices"]
		var normals: PackedVector3Array = built["normals"]
		print("  seed %d: %d vertices, %d triangles, %d ms" % [seed_value, verts.size(), (built["indices"] as PackedInt32Array).size() / 3, ms])
		_check(verts.size() > 2000, "a real mesh (%d vertices)" % verts.size())
		_check(ms < 6000, "builds in a few seconds (%d ms)" % ms)
		var intrude := 0
		var facing_in := 0
		var checked := 0
		for v in verts.size():
			var p := verts[v]
			if absf(p.y) > 0.15:
				continue
			checked += 1
			var probe := Maze.crack_probe(state["cracks"], Vector2(p.x, p.z))
			# The rock must stay at least about a drone's radius beyond where
			# the drone's centre may go.
			if float(probe["excess"]) < Maze.RADIUS - Mesher.CELL:
				intrude += 1
			var q: Vector2 = probe["q"]
			if normals[v].dot(Vector3(q.x - p.x, 0.0, q.y - p.z)) > 0.0:
				facing_in += 1
		_check(checked > 200 and intrude == 0, "no rock inside the drone's space (%d of %d)" % [intrude, checked])
		_check(facing_in > checked * 0.9, "the walls face into the cave (%d of %d)" % [facing_in, checked])
		_check(Mesher.to_mesh(built).get_surface_count() == 1, "it becomes a mesh")
	if _failures.is_empty():
		print("[PASS] Crack mesher")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
