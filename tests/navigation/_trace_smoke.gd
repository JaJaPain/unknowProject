extends SceneTree
const Nav := preload("res://scripts/navigation/TangentNavigator.gd")

func _initialize() -> void:
	# Exactly the smoke-test fixture.
	var center := Vector3(10250.0, 0.0, 10000.0)
	var obstacles := [{"center": center, "radius": 430.0, "physical": 300.0}]
	var dest := Vector3(10800.0, 0.0, 10000.0)
	var pos := Vector3(9700.0, 0.0, 10000.0)
	var min_d := pos.distance_to(center)
	print("step   dist_center   dist_dest   branch")
	for i in range(500):
		var blocker: Dictionary = Nav.blocking_obstacle(pos, dest, obstacles)
		var branch := "clear"
		if not blocker.is_empty():
			branch = "inside" if pos.distance_to(center) < float(blocker["radius"]) else "tangent"
		if i % 10 == 0 or (pos.distance_to(center) < 432.0 and i % 2 == 0):
			print("%4d   %10.1f   %9.1f   %s" % [
				i, pos.distance_to(center), pos.distance_to(dest), branch])
		var steer: Vector3 = Nav.steer_from(pos, dest, obstacles)
		var dir := steer - pos
		if dir.length() < 0.01:
			break
		pos += dir.normalized() * minf(8.0, dir.length())
		min_d = minf(min_d, pos.distance_to(center))
		if pos.distance_to(dest) < 10.0:
			break
	print("MIN CLEARANCE %.1f (required 430)  final dist_dest %.1f" % [min_d, pos.distance_to(dest)])
	quit(0)
