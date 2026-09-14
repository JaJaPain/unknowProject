extends SceneTree

const Nav := preload("res://scripts/navigation/TangentNavigator.gd")


func _initialize() -> void:
	var center := Vector3(0, 0, -1000)
	var radius := 300.0
	var obstacles := [{"center": center, "radius": radius, "physical": radius * 0.5}]
	var dest := Vector3(0, 0, -2000)
	var pos := Vector3(0, 0, -780)
	print("step  pos                       dist_center  dist_dest  branch")
	for i in range(60):
		var blocker: Dictionary = Nav.blocking_obstacle(pos, dest, obstacles)
		var branch := "clear"
		if not blocker.is_empty():
			branch = "inside" if pos.distance_to(center) < float(blocker["radius"]) else "tangent"
		if i % 2 == 0:
			print("%4d  (%7.1f,%5.1f,%8.1f)  %8.1f  %9.1f  %s" % [
				i, pos.x, pos.y, pos.z, pos.distance_to(center), pos.distance_to(dest), branch
			])
		var steer: Vector3 = Nav.steer_from(pos, dest, obstacles)
		var dir := steer - pos
		if dir.length() < 0.001:
			break
		pos += dir.normalized() * 25.0
	quit(0)
