extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_test_hostiles_use_shipping_lane_without_belt()
	_test_hostiles_prefer_belt_over_shipping_lane()
	_test_mission_targets_use_shipping_lane_without_belt()
	_test_mission_targets_prefer_belt_over_shipping_lane()

	if _failures.is_empty():
		print("[PASS] Generated NPC route tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_hostiles_use_shipping_lane_without_belt() -> void:
	var root := Node3D.new()
	root.name = "NoBeltSystem"
	get_root().add_child(root)
	var a := _make_station("A", Vector3(100.0, 0.0, 0.0))
	var b := _make_station("B", Vector3(900.0, 0.0, 0.0))
	root.add_child(a)
	root.add_child(b)

	var manager := _make_manager()
	if manager == null:
		root.queue_free()
		return
	var route: Array[Vector3] = manager._pick_hostile_patrol_route(root)
	_expect(route.size() == 2, "No-belt hostile fallback should be a two-station route.")
	_expect(route.has(a.position), "No-belt route missing first station endpoint.")
	_expect(route.has(b.position), "No-belt route missing second station endpoint.")
	root.queue_free()


func _test_hostiles_prefer_belt_over_shipping_lane() -> void:
	var root := Node3D.new()
	root.name = "BeltSystem"
	get_root().add_child(root)
	var station_a := _make_station("A", Vector3(-600.0, 0.0, 0.0))
	var station_b := _make_station("B", Vector3(600.0, 0.0, 0.0))
	root.add_child(station_a)
	root.add_child(station_b)
	for i in range(4):
		var angle := TAU * float(i) / 4.0
		root.add_child(_make_asteroid("belt.outer", Vector3(cos(angle) * 300.0, 0.0, sin(angle) * 300.0)))

	var manager := _make_manager()
	if manager == null:
		root.queue_free()
		return
	var route: Array[Vector3] = manager._pick_hostile_patrol_route(root)
	_expect(route.size() >= 2, "Belt hostile route should contain belt patrol points.")
	_expect(not route.has(station_a.position), "Belt route should not fall back to first station.")
	_expect(not route.has(station_b.position), "Belt route should not fall back to second station.")
	root.queue_free()


func _test_mission_targets_use_shipping_lane_without_belt() -> void:
	var root := Node3D.new()
	root.name = "MissionNoBeltSystem"
	get_root().add_child(root)
	var a := _make_station("A", Vector3(100.0, 0.0, 0.0))
	var b := _make_station("B", Vector3(900.0, 0.0, 0.0))
	root.add_child(a)
	root.add_child(b)

	var gs = get_root().get_node("GlobalState")
	var route: Array[Vector3] = gs._pick_mission_target_route(root)
	_expect(route.size() == 2, "Mission no-belt fallback should be a two-station route.")
	_expect(route.has(a.position), "Mission no-belt route missing first station endpoint.")
	_expect(route.has(b.position), "Mission no-belt route missing second station endpoint.")
	root.queue_free()


func _test_mission_targets_prefer_belt_over_shipping_lane() -> void:
	var root := Node3D.new()
	root.name = "MissionBeltSystem"
	get_root().add_child(root)
	var station_a := _make_station("A", Vector3(-600.0, 0.0, 0.0))
	var station_b := _make_station("B", Vector3(600.0, 0.0, 0.0))
	root.add_child(station_a)
	root.add_child(station_b)
	for i in range(4):
		var angle := TAU * float(i) / 4.0
		root.add_child(_make_asteroid("belt.outer", Vector3(cos(angle) * 300.0, 0.0, sin(angle) * 300.0)))

	var gs = get_root().get_node("GlobalState")
	var route: Array[Vector3] = gs._pick_mission_target_route(root)
	_expect(route.size() >= 2, "Mission belt route should contain belt patrol points.")
	_expect(not route.has(station_a.position), "Mission belt route should not fall back to first station.")
	_expect(not route.has(station_b.position), "Mission belt route should not fall back to second station.")
	root.queue_free()


func _make_station(label: String, pos: Vector3) -> Node3D:
	var station := Node3D.new()
	station.name = "Station_%s" % label
	station.add_to_group("station")
	station.position = pos
	return station


func _make_asteroid(belt_id: String, pos: Vector3) -> Node3D:
	var asteroid := Node3D.new()
	asteroid.name = "Asteroid"
	asteroid.add_to_group("asteroid")
	asteroid.set_meta("belt_id", belt_id)
	asteroid.position = pos
	return asteroid


func _make_manager() -> Node:
	var script := load("res://scripts/generation/GeneratedSystemNPCManager.gd")
	if script == null:
		_failures.append("Could not load GeneratedSystemNPCManager script.")
		return null
	var manager = script.new()
	if manager == null:
		_failures.append("Could not instantiate GeneratedSystemNPCManager.")
		return null
	return manager


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
