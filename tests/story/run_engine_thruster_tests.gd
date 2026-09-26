extends SceneTree

## Kitbash engines: each engine in use has its nozzles split into a "Thruster"
## surface and one socket per nozzle at the exit, facing rear (+Z), sized to it.
##   Godot --headless --path . --script res://tests/story/run_engine_thruster_tests.gd --log-file <path>

const Assembler := preload("res://scripts/generation/ShipAssembler.gd")

const NOZZLES := {
	"Cube_Engine": 12,
	"Bracket_Engine": 7,
	"Trap-Engine": 2,
	"eng.body.split": 2,
	"5-Engine": 5,
	"Block_Engine_single": 1,
}

var _failures: Array[String] = []


func _initialize() -> void:
	for stem in Assembler.VANGUARD_ENGINES:
		_check(NOZZLES.has(stem), "%s has an expected nozzle count" % stem)
	for stem in NOZZLES:
		var part := Assembler._load_part("engines", stem)
		_check(part != null, "%s loads" % stem)
		if part == null:
			continue
		var root := Node3D.new()
		root.add_child(part)
		var count := Assembler._add_thruster_socket_markers(root, part, 0)
		_check(count == int(NOZZLES[stem]), "%s: %d sockets, expected %d" % [stem, count, NOZZLES[stem]])
		var box := Assembler._node_aabb(part)
		for child in root.get_children():
			if not str(child.name).begins_with("thruster_"):
				continue
			var m := child as Marker3D
			var r := float(m.get_meta("thruster_radius", 0.0))
			_check(r >= 0.1 and r <= 0.8, "%s %s: radius %.2f" % [stem, m.name, r])
			# Exits sit in the rear half of the engine.
			_check(m.position.z > box.get_center().z, "%s %s is at the rear (z %.2f)" % [stem, m.name, m.position.z])
		var thruster_surface := false
		var meshes: Array[MeshInstance3D] = []
		Assembler._collect_meshes(part, meshes)
		for mi in meshes:
			if mi.mesh == null or not mi.visible:
				continue
			for s in mi.mesh.get_surface_count():
				if Assembler._surface_is_thruster(mi, s):
					thruster_surface = true
		_check(thruster_surface, "%s has a Thruster surface" % stem)
		root.free()

	if _failures.is_empty():
		print("[PASS] Engine thrusters")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
