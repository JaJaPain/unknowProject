class_name NavigationRoutePlanner
extends RefCounted

const DIRECTIONS: Array[Vector3] = [
	Vector3(1, 0, 0),
	Vector3(0.707, 0, 0.707),
	Vector3(0, 0, 1),
	Vector3(-0.707, 0, 0.707),
	Vector3(-1, 0, 0),
	Vector3(-0.707, 0, -0.707),
	Vector3(0, 0, -1),
	Vector3(0.707, 0, -0.707),
	Vector3(0.707, 0.707, 0),
	Vector3(0, 0.707, 0.707),
	Vector3(-0.707, 0.707, 0),
	Vector3(0, 0.707, -0.707),
	Vector3(0.707, -0.707, 0),
	Vector3(0, -0.707, 0.707),
	Vector3(-0.707, -0.707, 0),
	Vector3(0, -0.707, -0.707),
]


static func plan_route(
	start: Vector3,
	destination: Vector3,
	hazards: Array
) -> Dictionary:
	if start.distance_to(destination) < 1.0:
		return {"ok": true, "waypoints": [destination]}
	if _segment_is_clear(start, destination, hazards):
		return {"ok": true, "waypoints": [destination]}

	var nodes: Array[Vector3] = [start, destination]
	for hazard in hazards:
		if not hazard is Dictionary:
			continue
		var center: Vector3 = hazard.get("center", Vector3.ZERO)
		var radius := float(hazard.get("radius", 0.0))
		if radius <= 0.0:
			continue
		var node_radius := radius * 1.12 + 20.0
		for direction in DIRECTIONS:
			var candidate := center + direction.normalized() * node_radius
			if _point_is_clear(candidate, hazards, hazard):
				nodes.append(candidate)

	var adjacency: Array[Array] = []
	adjacency.resize(nodes.size())
	for index in range(nodes.size()):
		adjacency[index] = []
	for left in range(nodes.size()):
		for right in range(left + 1, nodes.size()):
			if not _segment_is_clear(nodes[left], nodes[right], hazards):
				continue
			var distance := nodes[left].distance_to(nodes[right])
			adjacency[left].append({"to": right, "cost": distance})
			adjacency[right].append({"to": left, "cost": distance})

	var path := _a_star(nodes, adjacency, 0, 1)
	if path.is_empty():
		return {
			"ok": false,
			"error": "No safe route is available.",
			"waypoints": [],
		}
	var waypoints: Array[Vector3] = []
	for path_index in path:
		if int(path_index) == 0:
			continue
		waypoints.append(nodes[int(path_index)])
	return {"ok": true, "waypoints": waypoints}


static func route_is_clear(
	start: Vector3,
	waypoints: Array,
	hazards: Array
) -> bool:
	var cursor := start
	for waypoint in waypoints:
		if not waypoint is Vector3 \
				or not _segment_is_clear(cursor, waypoint, hazards):
			return false
		cursor = waypoint
	return true


static func _a_star(
	nodes: Array[Vector3],
	adjacency: Array[Array],
	start_index: int,
	goal_index: int
) -> Array[int]:
	var open: Array[int] = [start_index]
	var came_from: Dictionary = {}
	var g_score := {start_index: 0.0}
	var f_score := {
		start_index: nodes[start_index].distance_to(nodes[goal_index]),
	}
	while not open.is_empty():
		var current := open[0]
		for candidate in open:
			if float(f_score.get(candidate, INF)) \
					< float(f_score.get(current, INF)):
				current = candidate
		if current == goal_index:
			return _reconstruct_path(came_from, current)
		open.erase(current)
		for edge in adjacency[current]:
			var neighbor := int(edge.get("to", -1))
			var tentative := float(g_score.get(current, INF)) \
				+ float(edge.get("cost", INF))
			if tentative >= float(g_score.get(neighbor, INF)):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			f_score[neighbor] = tentative \
				+ nodes[neighbor].distance_to(nodes[goal_index])
			if neighbor not in open:
				open.append(neighbor)
	return []


static func _reconstruct_path(
	came_from: Dictionary,
	current: int
) -> Array[int]:
	var path: Array[int] = [current]
	while came_from.has(current):
		current = int(came_from[current])
		path.push_front(current)
	return path


static func _point_is_clear(
	point: Vector3,
	hazards: Array,
	owner: Dictionary
) -> bool:
	for hazard in hazards:
		if not hazard is Dictionary or hazard == owner:
			continue
		if point.distance_to(hazard.get("center", Vector3.ZERO)) \
				< float(hazard.get("radius", 0.0)) + 5.0:
			return false
	return true


static func _segment_is_clear(
	start: Vector3,
	finish: Vector3,
	hazards: Array
) -> bool:
	for hazard in hazards:
		if not hazard is Dictionary:
			continue
		var center: Vector3 = hazard.get("center", Vector3.ZERO)
		var radius := float(hazard.get("radius", 0.0))
		if radius <= 0.0:
			continue
		if start.distance_to(center) < radius \
				or finish.distance_to(center) < radius:
			continue
		if _distance_to_segment(center, start, finish) < radius:
			return false
	return true


static func _distance_to_segment(
	point: Vector3,
	start: Vector3,
	finish: Vector3
) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared < 0.001:
		return point.distance_to(start)
	var along := clampf(
		(point - start).dot(segment) / length_squared,
		0.0,
		1.0
	)
	return point.distance_to(start + segment * along)
