extends SceneTree

# The "Fly to" bug: with a planet between ship and target the autopilot flew the
# OPPOSITE way and then stalled. These tests pin the geometry that caused it.

const Nav := preload("res://scripts/navigation/TangentNavigator.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_clear_shot_goes_straight()
	_test_blocked_shot_bends_around()
	_test_inside_sphere_never_flies_backward()
	if _failures.is_empty():
		print("[PASS] Tangent navigator tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _planet(center: Vector3, radius: float) -> Dictionary:
	return {"center": center, "radius": radius, "physical": radius * 0.5}


func _test_clear_shot_goes_straight() -> void:
	var obstacles := [_planet(Vector3(2000, 0, 0), 300.0)]
	var steer := Nav.steer_from(Vector3.ZERO, Vector3(0, 0, -2000), obstacles)
	_expect(
		steer == Vector3(0, 0, -2000),
		"An unobstructed shot must aim at the destination, got %s" % steer
	)


func _test_blocked_shot_bends_around() -> void:
	# Planet squarely between ship and target.
	var obstacles := [_planet(Vector3(0, 0, -1000), 300.0)]
	var ship := Vector3.ZERO
	var dest := Vector3(0, 0, -2000)
	var steer := Nav.steer_from(ship, dest, obstacles)
	_expect(steer != dest, "A blocked shot must not aim straight at the target.")
	_expect(
		Vector3(0, 0, -1000).distance_to(steer) >= 300.0,
		"The waypoint must sit outside the keep-out sphere, got %.1f" % \
			Vector3(0, 0, -1000).distance_to(steer)
	)
	_expect(
		Nav.heading_agreement(ship, steer, dest) > 0.0,
		"Even when detouring, the ship must not be sent backwards."
	)


# THE REPORTED BUG. The keep-out radius is body + safety margin, so a player
# flying anywhere near a planet -- mining its belt, passing by -- is already
# INSIDE the sphere. Ask to fly to something on the far side and the old radial
# exit aimed at the nearest surface point, which is directly behind the ship.
func _test_inside_sphere_never_flies_backward() -> void:
	var center := Vector3(0, 0, -1000)
	var radius := 300.0
	var dest := Vector3(0, 0, -2000)          # far side of the planet
	var ship := Vector3(0, 0, -800)           # inside the sphere, near side
	_expect(
		ship.distance_to(center) < radius,
		"Fixture is wrong: the ship should start inside the keep-out sphere."
	)

	# Demonstrate the regression: the old behaviour points away from the goal.
	var old_point := Nav.radial_exit_waypoint(ship, center, radius, dest)
	var old_agreement := Nav.heading_agreement(ship, old_point, dest)
	_expect(
		old_agreement < 0.0,
		"Reference check: radial exit should point AWAY (got %.2f); if this now" \
			% old_agreement + " passes, the fixture no longer reproduces the bug."
	)

	# The fix: still leaves the sphere, but never points away from the target.
	var steer := Nav.steer_from(ship, dest, [_planet(center, radius)])
	var agreement := Nav.heading_agreement(ship, steer, dest)
	_expect(
		agreement > 0.0,
		"Inside the sphere the ship must still make progress toward the target, got %.2f" % agreement
	)
	_expect(
		steer.distance_to(center) >= radius,
		"The exit waypoint must be outside the keep-out sphere, got %.1f" % steer.distance_to(center)
	)

	# And it must hold from anywhere inside, not just this one spot.
	for angle in [0.0, 0.6, 1.2, 2.0, 2.8, 3.6, 4.4, 5.2]:
		for depth in [0.2, 0.55, 0.9]:
			var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * (radius * float(depth))
			var pos: Vector3 = center + offset
			var point: Vector3 = Nav.steer_from(pos, dest, [_planet(center, radius)])
			var agree: float = Nav.heading_agreement(pos, point, dest)
			_expect(
				agree > -0.35,
				"From inside at angle %.1f depth %.2f the ship is sent backwards (%.2f)" % [
					angle, depth, agree
				]
			)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
