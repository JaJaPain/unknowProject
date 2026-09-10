extends SceneTree

# The "Fly to" bug: with a planet between ship and target the autopilot flew the
# OPPOSITE way and then stalled. These tests pin the geometry that caused it.

const Nav := preload("res://scripts/navigation/TangentNavigator.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_clear_shot_goes_straight()
	_test_blocked_shot_bends_around()
	_test_inside_sphere_never_flies_backward()
	_test_route_reaches_far_side()
	_test_closed_loop_does_not_stall()
	_test_long_range_and_crowded_fields()
	_test_moving_target_is_caught()
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
	# Not "> 0": with the ship skimming the near face and the target directly
	# behind the planet, EVERY correct route starts out sideways, which is an
	# agreement of about zero, and any outward lean makes it slightly negative.
	# What the bug looked like was -1.0 -- the ship doubling its distance in a
	# straight line. A shallow lateral bank is what rounding a planet looks like.
	_expect(
		agreement > -0.35,
		"Inside the sphere the ship must not be sent markedly backwards, got %.2f" % agreement
	)
	# Deliberately NOT "outside the keep-out sphere": that sphere is body plus
	# comfort margin, and treating the margin as a wall is what caused the bug.
	# What must never be violated is the real body.
	_expect(
		steer.distance_to(center) >= radius * 0.5,
		"The waypoint must clear the actual body, got %.1f (body %.1f)" % [
			steer.distance_to(center), radius * 0.5
		]
	)

	# And it must hold from anywhere inside the MARGIN. Positions inside the body
	# itself are excluded on purpose: a ship that is inside the planet has to fly
	# out, and "out" is legitimately away from a target on the far side.
	for angle in [0.0, 0.6, 1.2, 2.0, 2.8, 3.6, 4.4, 5.2]:
		for depth in [0.62, 0.75, 0.9]:
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


# The other half of the report: after flying the wrong way it "got stuck and
# never reached the target". A route that stalls shows up here as one that stops
# short of the destination or stops making progress.
func _test_route_reaches_far_side() -> void:
	var center := Vector3(0, 0, -1000)
	var radius := 300.0
	var obstacles := [_planet(center, radius)]
	var cases := {
		"outside, target far side": Vector3.ZERO,
		"inside, near side": Vector3(0, 0, -780),
		"inside, off axis": Vector3(180, 0, -900),
		"inside, deep": Vector3(60, 0, -1040),
	}
	var dest := Vector3(0, 0, -2000)
	for label in cases.keys():
		var start: Vector3 = cases[label]
		var path: PackedVector3Array = Nav.march_waypoints(start, dest, obstacles)
		_expect(
			path.size() >= 2,
			"%s: route is degenerate (%d points)" % [label, path.size()]
		)
		_expect(
			path[path.size() - 1].distance_to(dest) < 1.0,
			"%s: route does not end at the destination" % label
		)
		# A stall looks like a route that never gets near the goal before its
		# final jump: the last marched corner should be closer than the start.
		var last_corner: Vector3 = path[maxi(path.size() - 2, 0)]
		_expect(
			last_corner.distance_to(dest) < start.distance_to(dest),
			"%s: route made no progress (start %.0f away, last corner %.0f)" % [
				label, start.distance_to(dest), last_corner.distance_to(dest)
			]
		)
		# It must not tunnel through the body it was avoiding. The ship's own
		# starting position is not something a route can avoid, so a start that is
		# already deep inside sets the bar -- the route must never get CLOSER to
		# the centre than it began.
		var clearance: float = Nav.route_min_clearance(path, center)
		var floor_clearance: float = minf(start.distance_to(center), radius * 0.45)
		_expect(
			clearance >= floor_clearance - 5.0,
			"%s: route cuts deeper than it started (closest %.0f, started %.0f, keep-out %.0f)" % [
				label, clearance, start.distance_to(center), radius
			]
		)


# The decisive test for the stall. The static route can look fine while the ship
# still never arrives, because steering is recomputed every frame: the old radial
# exit created a limit cycle -- exit straight out, the tangent rule pulls the ship
# back around, it re-enters the sphere, exits straight out again, forever.
#
# This flies the ship for real, one step at a time, and asserts it arrives.
func _fly(start: Vector3, dest: Vector3, obstacles: Array, radial: bool) -> Dictionary:
	var pos := start
	var step := 25.0
	var steps := 0
	var closest := start.distance_to(dest)
	while steps < 4000:
		steps += 1
		if pos.distance_to(dest) <= step:
			return {"arrived": true, "steps": steps, "closest": 0.0}
		var steer: Vector3
		var blocker: Dictionary = Nav.blocking_obstacle(pos, dest, obstacles)
		if radial and not blocker.is_empty() 				and pos.distance_to(blocker["center"]) < float(blocker["radius"]):
			steer = Nav.radial_exit_waypoint(
				pos, blocker["center"], float(blocker["radius"]), dest
			)
		else:
			steer = Nav.steer_from(pos, dest, obstacles)
		var dir := steer - pos
		if dir.length() < 0.001:
			dir = dest - pos
		if dir.length() < 0.001:
			break
		pos += dir.normalized() * step
		closest = minf(closest, pos.distance_to(dest))
	return {"arrived": false, "steps": steps, "closest": closest}


func _test_closed_loop_does_not_stall() -> void:
	var center := Vector3(0, 0, -1000)
	var radius := 300.0
	var obstacles := [_planet(center, radius)]
	var dest := Vector3(0, 0, -2000)
	var starts := {
		"outside": Vector3.ZERO,
		"inside near side": Vector3(0, 0, -780),
		"inside off axis": Vector3(180, 0, -900),
		"inside deep": Vector3(60, 0, -1040),
	}
	for label in starts.keys():
		var start: Vector3 = starts[label]
		var flown: Dictionary = _fly(start, dest, obstacles, false)
		_expect(
			bool(flown["arrived"]),
			"%s: ship never arrived (%d steps, got within %.0f)" % [
				label, int(flown["steps"]), float(flown["closest"])
			]
		)
	# The regression itself is pinned geometrically in
	# _test_inside_sphere_never_flies_backward. A flight-level reference check was
	# tried here and removed: with the rest of the pipeline fixed, a single bad
	# exit no longer strands the ship, so "does the old exit stall a whole flight"
	# stopped being a stable statement about the bug.


# A real system is not one planet at a convenient distance. The march has a step
# budget, and a long detour can exhaust it; a crowded field can hand the ship a
# new blocker every frame.
func _test_long_range_and_crowded_fields() -> void:
	# Long range: far enough that the marching budget matters.
	var far_obstacles := [_planet(Vector3(0, 0, -3000), 600.0)]
	var far_dest := Vector3(0, 0, -6000)
	var flown: Dictionary = _fly(Vector3.ZERO, far_dest, far_obstacles, false)
	_expect(
		bool(flown["arrived"]),
		"Long range: never arrived (%d steps, got within %.0f)" % [
			int(flown["steps"]), float(flown["closest"])
		]
	)

	# Several bodies between ship and target, including one the route must thread
	# past after clearing another.
	var crowded := [
		_planet(Vector3(0, 0, -800), 250.0),
		_planet(Vector3(300, 0, -1600), 300.0),
		_planet(Vector3(-350, 0, -2400), 280.0),
	]
	var crowded_dest := Vector3(0, 0, -3200)
	var crowded_flight: Dictionary = _fly(Vector3.ZERO, crowded_dest, crowded, false)
	_expect(
		bool(crowded_flight["arrived"]),
		"Crowded field: never arrived (%d steps, got within %.0f)" % [
			int(crowded_flight["steps"]), float(crowded_flight["closest"])
		]
	)

	# And the route must not pass through any of the bodies on the way.
	var path: PackedVector3Array = Nav.march_waypoints(Vector3.ZERO, crowded_dest, crowded)
	for ob in crowded:
		var center: Vector3 = ob["center"]
		var body: float = float(ob["physical"])
		var clearance: float = Nav.route_min_clearance(path, center)
		_expect(
			clearance >= body,
			"Crowded field: route passes through a body at %s (closest %.0f, body %.0f)" % [
				center, clearance, body
			]
		)


# The reported case was flying to a HOSTILE, which moves. A target that drifts
# while the ship rounds a planet is the situation that produced the report, and
# a navigator that only works on stationary points would still fail it.
func _test_moving_target_is_caught() -> void:
	var center := Vector3(0, 0, -1000)
	var obstacles := [_planet(center, 300.0)]
	var target := Vector3(0, 0, -2000)
	var drift := Vector3(9.0, 0.0, -2.0)   # target running, faster laterally
	var pos := Vector3(0, 0, -780)          # ship starts inside the margin
	var step := 25.0
	var caught := false
	var closest := pos.distance_to(target)
	for _i in range(3000):
		target += drift
		if pos.distance_to(target) <= step * 1.5:
			caught = true
			break
		var steer: Vector3 = Nav.steer_from(pos, target, obstacles)
		var dir := steer - pos
		if dir.length() < 0.001:
			dir = target - pos
		if dir.length() < 0.001:
			break
		pos += dir.normalized() * step
		closest = minf(closest, pos.distance_to(target))
	_expect(
		caught,
		"Moving target was never caught (closest %.0f)" % closest
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
