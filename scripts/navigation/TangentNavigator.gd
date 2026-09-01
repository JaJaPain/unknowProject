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
			best = {"center": center, "radius": eff, "distance": d}
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
	var margin := radius * 0.15 + 20.0
	return center + side * (radius + margin)


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
	var blocker := blocking_obstacle(from_pos, destination, obstacles)
	if blocker.is_empty():
		return destination
	var center: Vector3 = blocker["center"]
	var radius := float(blocker["radius"])
	if from_pos.distance_to(center) < radius:
		return exit_waypoint(from_pos, center, radius, destination)
	return sphere_tangent_waypoint(from_pos, center, radius, destination)


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
	var dir := (out_dir * EXIT_OUTWARD_BIAS + around * EXIT_AROUND_BIAS).normalized()
	return center + dir * (radius + radius * 0.15 + 20.0)


const EXIT_OUTWARD_BIAS := 0.45
const EXIT_AROUND_BIAS := 0.90


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
