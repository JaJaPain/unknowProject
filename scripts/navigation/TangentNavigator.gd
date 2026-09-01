class_name TangentNavigator
extends RefCounted

# Pure geometry for the keep-out-sphere autopilot, lifted out of PlayerShip so it
# can be tested without a scene.
#
# An obstacle is a plain dictionary, never a node:
#   {"center": Vector3, "radius": float, "physical": float}
# `radius` is the keep-out radius (body + safety margin); `physical` is the real
# body radius, used to tell "target is inside the actual planet" from "target is
# merely inside the comfortable margin around it".


## True if segment a->b stays at least `radius` away from sphere centre c.
static func segment_clears_sphere(a: Vector3, b: Vector3, c: Vector3, radius: float) -> bool:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1.0:
		return a.distance_to(c) >= radius
	var t := clampf((c - a).dot(ab) / len_sq, 0.0, 1.0)
	var closest := a + ab * t
	return closest.distance_to(c) >= radius


## The effective avoidance radius for one obstacle given where we are heading, or
## -1.0 when this obstacle should be ignored entirely.
##
## Ignored when the destination is inside the actual body (an enemy that has flown
## into the planet is unreachable any other way). Shrunk when the destination sits
## inside the margin but outside the body, so we still round the body instead of
## scraping it.
static func effective_radius(obstacle: Dictionary, destination: Vector3) -> float:
	var center: Vector3 = obstacle.get("center", Vector3.ZERO)
	var radius := float(obstacle.get("radius", 0.0))
	var physical := float(obstacle.get("physical", radius))
	var dest_from_center := center.distance_to(destination)
	if dest_from_center < physical + 30.0:
		return -1.0
	if dest_from_center < radius:
		return maxf(physical + 40.0, dest_from_center - 40.0)
	return radius


## The nearest obstacle whose keep-out sphere the segment from->destination
## pierces, as {"center", "radius", "distance"}, or {} when the shot is clear.
static func blocking_obstacle(
	from_pos: Vector3,
	destination: Vector3,
	obstacles: Array
) -> Dictionary:
	var best := {}
	var best_dist := INF
	for raw in obstacles:
		if not raw is Dictionary:
			continue
		var obstacle: Dictionary = raw
		var eff := effective_radius(obstacle, destination)
		if eff < 0.0:
			continue
		var center: Vector3 = obstacle.get("center", Vector3.ZERO)
		if segment_clears_sphere(from_pos, destination, center, eff):
			continue
		var d := from_pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			best = {
				"center": center,
				"radius": eff,
				"physical": float(obstacle.get("physical", eff)),
				"distance": d,
				# Opaque passenger: the navigator never looks at this, but callers
				# need to know WHICH thing blocked them, and threading it through
				# beats making them re-derive it from the position.
				"node": obstacle.get("node", null),
			}
	return best


## A sideways unit vector perpendicular to `axis`, biased toward `toward`.
## Falls back to a stable axis when the two are collinear.
static func sideways_from(axis: Vector3, toward: Vector3) -> Vector3:
	var side := toward - axis * toward.dot(axis)
	if side.length() < 0.01:
		side = axis.cross(Vector3.UP)
		if side.length() < 0.01:
			side = axis.cross(Vector3.RIGHT)
	return side.normalized()


## A waypoint on the silhouette of the keep-out sphere, on the side the
## destination lies toward, that carries the ship around the outside.
static func sphere_tangent_waypoint(
	from_pos: Vector3,
	center: Vector3,
	radius: float,
	destination: Vector3
) -> Vector3:
	var to_center := center - from_pos
	var center_dist := to_center.length()
	if center_dist < 0.001:
		to_center = destination - from_pos
		center_dist = maxf(to_center.length(), 0.001)
	var center_dir := to_center / center_dist
	var dest_dir := destination - from_pos
	if dest_dir.length() < 0.001:
		dest_dir = center_dir
	dest_dir = dest_dir.normalized()
	var side := sideways_from(center_dir, dest_dir)

	# Aim at the TRUE tangent point: the spot where a straight line from here
	# grazes the sphere. The first implementation aimed at the sphere's widest
	# point relative to the ship instead, which chatters -- the ship steps
	# sideways until the shot is clear, turns straight at the target, that
	# heading immediately re-enters the sphere, and it steps sideways again.
	# The net motion is a circle around the keep-out boundary at a constant
	# distance from the goal, which is the "stalled and never arrived" half of
	# the report. A real tangent line clears the sphere by construction, so
	# following it makes monotone progress and there is nothing to chatter
	# between.
	var margin := radius * 0.15 + 20.0
	# Never pad the sphere out past the ship itself -- that is what forced the
	# degenerate boundary fallback, and the fallback is what slid the ship around
	# the edge forever.
	#
	# But the clamp may only eat the optional MARGIN, never the required radius.
	# Clamping straight to center_dist - 5 lets the allowed radius shrink by five
	# units every step as the ship closes on its own tangent point, so it spirals
	# inward and ends up inside the envelope it was told to respect.
	# Floor the grazing radius ABOVE the requirement, not at it. Aiming exactly at
	# the required radius leaves no headroom, and real bodies orbit -- the planet
	# drifts into the gap the ship never actually held.
	var safe_radius := minf(
		radius + margin, maxf(radius + BOUNDARY_STANDOFF, center_dist - 5.0)
	)
	if safe_radius <= 0.0 or center_dist <= safe_radius:
		# Numerically inside the padded sphere; the caller handles exits, but be
		# safe rather than feeding asin a value above 1. Aim clear of the boundary
		# for the same reason the exit does.
		return center + side * exit_distance(radius)
	var alpha := asin(clampf(safe_radius / center_dist, -1.0, 1.0))
	var dir := (center_dir * cos(alpha) + side * sin(alpha)).normalized()
	var tangent_length := sqrt(maxf(center_dist * center_dist - safe_radius * safe_radius, 1.0))
	return from_pos + dir * tangent_length


## Where to aim from `from_pos` on the way to `destination`: the destination
## itself when the shot is clear, otherwise a point that carries the ship around
## the nearest blocking sphere.
static func steer_from(
	from_pos: Vector3,
	destination: Vector3,
	obstacles: Array
) -> Vector3:
	if from_pos.distance_to(destination) < 1.0:
		return destination
	# A body the ship is ALREADY inside outranks the one merely in the way.
	# Steering only by the nearest blocker lets the ship be pushed deep into a
	# second envelope while dutifully rounding the first -- which is how a real
	# system with several bodies breaches a clearance the geometry says it holds.
	var violated := violated_obstacle(from_pos, destination, obstacles)
	if not violated.is_empty():
		return steer_clear_of(from_pos, destination, violated)
	var blocker := blocking_obstacle(from_pos, destination, obstacles)
	if blocker.is_empty():
		return destination
	return steer_clear_of(from_pos, destination, blocker)


## The obstacle whose keep-out volume the ship is currently INSIDE by the largest
## margin, or {} when it is inside none. Destination-containing bodies are
## skipped, as everywhere else -- you must enter those to arrive.
static func violated_obstacle(
	from_pos: Vector3,
	destination: Vector3,
	obstacles: Array
) -> Dictionary:
	var worst := {}
	var worst_depth := 0.0
	for raw in obstacles:
		if not raw is Dictionary:
			continue
		var obstacle: Dictionary = raw
		var eff := effective_radius(obstacle, destination)
		if eff < 0.0:
			continue
		var center: Vector3 = obstacle.get("center", Vector3.ZERO)
		var depth := eff - from_pos.distance_to(center)
		if depth > worst_depth:
			worst_depth = depth
			worst = {
				"center": center,
				"radius": eff,
				"physical": float(obstacle.get("physical", eff)),
				"node": obstacle.get("node", null),
			}
	return worst


## Steering for one specific obstacle: tangent when comfortably outside, arc in
## the boundary band, escape when against the body.
static func steer_clear_of(
	from_pos: Vector3,
	destination: Vector3,
	blocker: Dictionary
) -> Vector3:
	var center: Vector3 = blocker["center"]
	var radius := float(blocker["radius"])
	var physical := float(blocker.get("physical", radius))
	var from_dist := from_pos.distance_to(center)
	# Tangent steering only when COMFORTABLY outside. Aiming a tangent at exactly
	# the required radius means the ship rides the boundary, and flying an arc in
	# straight steps dips below it on every chord. The band just outside the
	# envelope belongs to the arc, which carries an outward bias.
	if from_dist >= radius + BOUNDARY_STANDOFF:
		return sphere_tangent_waypoint(from_pos, center, radius, destination)

	# Already inside the keep-out sphere. That sphere is the body PLUS a comfort
	# margin for routing, so being inside it is not dangerous -- flying near a
	# planet or mining its belt puts you there routinely. Trying to get back out
	# first is what made the ship fly away from its target, and biasing that exit
	# sideways just made it circle inside instead.
	#
	# So stop treating the margin as a wall: once inside it, route around the
	# ACTUAL body. The tangent rule then works normally and the ship leaves on a
	# path that goes where it was asked to go.
	var floor_radius := physical + INSIDE_BODY_CLEARANCE
	if from_dist <= floor_radius:
		# Genuinely against the body: get out, biased toward the destination.
		return exit_waypoint(from_pos, center, floor_radius, destination)
	# Climb toward the full envelope, not merely toward the radius the ship
	# happens to hold. Capping the target at from_dist meant that once the ship
	# slipped inside the envelope it stayed there -- fine against a static body,
	# but real planets ORBIT, and the body then drifts into the gap.
	#
	# This is a gentle outward BIAS layered on an arc, not the radial exit that
	# caused the original bug: the ship keeps travelling around toward its target
	# the whole time it is climbing.
	# Climb toward a standoff ABOVE the envelope, not to the envelope itself.
	# Targeting the requirement exactly means hovering on it, and chord stepping
	# plus an orbiting body then nibble below.
	return arc_waypoint(
		from_pos, center, destination, radius + BOUNDARY_STANDOFF, radius
	)


## Steering while inside a body's comfort margin: arc AROUND at roughly the
## current radius, toward the side the destination lies on.
##
## Tangent-to-a-shrinking-sphere was tried here and oscillated. Flying a tangent
## in discrete steps cuts the chord, so each step loses a little altitude; the
## ship sinks until it trips whatever "too close" branch exists, gets pushed out,
## and sinks again. The player sees the ship shuddering in place beside a planet.
##
## An arc has no branch to flip across. The direction varies smoothly with
## position, and a small outward bias exactly counteracts the chord loss.
static func arc_waypoint(
	from_pos: Vector3,
	center: Vector3,
	destination: Vector3,
	floor_radius: float,
	keepout_radius: float
) -> Vector3:
	var out_dir := from_pos - center
	if out_dir.length() < 0.001:
		out_dir = Vector3.RIGHT
	var from_dist := out_dir.length()
	out_dir = out_dir / from_dist
	var to_dest := destination - center
	var around := Vector3.ZERO
	if to_dest.length() > 0.001:
		around = sideways_from(out_dir, to_dest.normalized())
	if around.length() < 0.001:
		around = sideways_from(out_dir, Vector3.FORWARD)
	# Climb when riding low, ease outward otherwise. The baseline outward term is
	# what pays back the chord loss of flying an arc in straight steps.
	var outward := ARC_OUTWARD_BASE
	var band := floor_radius * ARC_CLIMB_BAND
	if from_dist < band and band > 0.001:
		# Proportional, not a fixed kick. A constant boost near the body swamps
		# the "around" term and points the ship away from its target again --
		# the original bug, reintroduced by the cure for it.
		outward += ARC_CLIMB_BOOST * clampf(1.0 - from_dist / band, 0.0, 1.0)
	# Hard ceiling on the outward pull. When the target is on the far side, every
	# unit of "outward" is a unit of "backward" -- so the climb may never grow
	# strong enough to dominate the lateral term, however far inside the ship is.
	# Without this cap, holding clearance against a moving planet reintroduced the
	# original bug: a ship flying away from its own destination.
	outward = minf(outward, ARC_OUTWARD_MAX)
	var dir := (around + out_dir * outward).normalized()
	return from_pos + dir * ARC_LOOKAHEAD


const ARC_OUTWARD_BASE := 0.22
const ARC_CLIMB_BAND := 1.25
const ARC_CLIMB_BOOST := 0.55
const ARC_OUTWARD_MAX := 0.35
const ARC_LOOKAHEAD := 140.0
## How far outside the required radius the ship must be before a straight
## tangent is safe to fly given discrete stepping.
const BOUNDARY_STANDOFF := 18.0


## Where to aim when the ship is already INSIDE a keep-out sphere.
##
## Straight radial exit is what the first implementation did, and it is the bug
## Abe reported as "flew the OPPOSITE direction": with the destination on the far
## side of the body, the nearest surface point is directly behind the ship, so the
## autopilot confidently flies away from the target before it will consider going
## around. The player reads that as the ship refusing to obey.
##
## Exiting on a slant fixes it. The waypoint is still on the surface, so the ship
## still leaves the keep-out volume, but it is swung around toward the side the
## destination lies on, so every metre flown also makes angular progress.
static func exit_waypoint(
	from_pos: Vector3,
	center: Vector3,
	radius: float,
	destination: Vector3
) -> Vector3:
	var out_dir := from_pos - center
	if out_dir.length() < 0.001:
		out_dir = destination - center
	if out_dir.length() < 0.001:
		out_dir = Vector3.RIGHT
	out_dir = out_dir.normalized()
	var to_dest := destination - center
	var around := Vector3.ZERO
	if to_dest.length() > 0.001:
		around = sideways_from(out_dir, to_dest.normalized())
	if around.length() < 0.001:
		around = sideways_from(out_dir, Vector3.FORWARD)
	# Mostly sideways, partly outward: leaves the sphere without ever pointing
	# back down the line to the destination.
	#
	# The target sits comfortably OUTSIDE the padded sphere, not on it. Aiming at
	# the boundary exactly leaves the ship riding the edge, where the tangent rule
	# cannot get a grip and just slides around forever -- the same stall in a
	# different costume.
	var dir := (out_dir * EXIT_OUTWARD_BIAS + around * EXIT_AROUND_BIAS).normalized()
	return center + dir * exit_distance(radius)


# Escaping the actual body is the rare case, and there the priority is OUT --
# a mostly-sideways escape orbits inside the body instead of leaving it.
const EXIT_OUTWARD_BIAS := 1.0
const EXIT_AROUND_BIAS := 0.55
## Hard clearance around the real body. Deliberately small: everything inside
## this radius takes the escape branch, and escaping necessarily points away from
## a target on the far side. Keep the escape zone tight so it stays the rare
## genuinely-inside-the-planet case rather than the everyday one.
const INSIDE_BODY_CLEARANCE := 25.0


## How far from the centre an exit waypoint is placed: past the keep-out radius
## AND past its margin, with headroom so the tangent rule has something to work
## with the moment the ship gets there.
static func exit_distance(radius: float) -> float:
	var safe_radius := radius + radius * 0.15 + 20.0
	return safe_radius * 1.25 + 40.0


## The original radial exit, kept only so tests can demonstrate the regression it
## caused. Not used by the navigator.
static func radial_exit_waypoint(
	from_pos: Vector3,
	center: Vector3,
	radius: float,
	destination: Vector3
) -> Vector3:
	var out_dir := from_pos - center
	if out_dir.length() < 0.001:
		out_dir = destination - center
	if out_dir.length() < 0.001:
		out_dir = Vector3.RIGHT
	out_dir = out_dir.normalized()
	return center + out_dir * (radius + radius * 0.15 + 20.0)


## Signed progress a steer point makes toward the destination, as the cosine
## between "where we are told to fly" and "where the destination is". Negative
## means the autopilot is pointing the ship away from its own goal.
static func heading_agreement(
	from_pos: Vector3,
	steer_point: Vector3,
	destination: Vector3
) -> float:
	var steer_dir := steer_point - from_pos
	var dest_dir := destination - from_pos
	if steer_dir.length() < 0.001 or dest_dir.length() < 0.001:
		return 1.0
	return steer_dir.normalized().dot(dest_dir.normalized())


const MARCH_STEP := 50.0
const MARCH_MAX_STEPS := 60


## Traces the steer rule forward from `start`, recording the corner points, to
## produce a raw route. A clear shot yields [start, destination]; a blocked one
## bends around. Returns the points including both endpoints.
static func march_waypoints(
	start: Vector3,
	destination: Vector3,
	obstacles: Array,
	step: float = MARCH_STEP,
	max_steps: int = MARCH_MAX_STEPS
) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.append(start)
	var cur := start
	for _i in max_steps:
		if cur.distance_to(destination) <= step:
			break
		var steer := steer_from(cur, destination, obstacles)
		if steer.distance_to(destination) < 1.0:
			break  # clear line from here on
		var dir := steer - cur
		if dir.length() < 0.001:
			dir = destination - cur
		if dir.length() < 0.001:
			break
		cur += dir.normalized() * step
		pts.append(cur)
	pts.append(destination)
	return pts


## How close a route comes to a sphere at its worst point, sampling the segments
## rather than only the corners. Endpoints are excluded, since the ship or the
## target may legitimately sit inside a keep-out volume.
static func route_min_clearance(path: PackedVector3Array, center: Vector3) -> float:
	if path.size() < 2:
		return INF
	var worst := INF
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := 0.0
		if len_sq > 0.0001:
			t = clampf((center - a).dot(ab) / len_sq, 0.0, 1.0)
		worst = minf(worst, (a + ab * t).distance_to(center))
	return worst
