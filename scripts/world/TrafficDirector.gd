extends Node

## Station traffic (next_level_plan P5): every so often a freighter comes in
## through the jump gate and docks at the main station, or undocks and leaves
## through the gate. Haulers only (they never pick fights), protected from NPC
## attacks, a few at a time. Docking fades the ship out at the berth; leaving
## ends in a flash at the gate.

const MAX_TRAFFIC := 3
const INTERVAL_MIN := 25.0
const INTERVAL_MAX := 50.0
# NPCs stop and circle ~70 m from their patrol point, so arrive inside 110.
const DOCK_RADIUS := 110.0
const GATE_RADIUS := 110.0
# Logistics only: mining haulers go off to the belts on their own.
const ROLES := ["Logistics"]

var _timer := 8.0
var _ships: Array = []  # [{ship, dest, kind}]
var _serial := 0


func _process(delta: float) -> void:
	if not GlobalState.player or not is_instance_valid(GlobalState.player):
		return
	for entry in _ships.duplicate():
		_tick_ship(entry)
	_timer -= delta
	if _timer <= 0.0:
		_timer = randf_range(INTERVAL_MIN, INTERVAL_MAX)
		if _ships.size() < MAX_TRAFFIC:
			_spawn()


## Test hook: `forced_arriving` / `forced_speed` pick the trip (-1 = random).
var forced_arriving := -1
var forced_speed := 0.0
var docked_count := 0
var stuck_count := 0
var left_count := 0


func spawn_now() -> void:
	_spawn()


func _spawn() -> void:
	var root := GlobalState.get_system_root()
	var station := GlobalState.get_primary_station()
	if root == null or station == null:
		return
	var gates: Array = []
	for gate in get_tree().get_nodes_in_group("jumpgate"):
		if gate is Node3D and root.is_ancestor_of(gate):
			gates.append(gate)
	if gates.is_empty():
		return
	var gate: Node3D = gates[randi() % gates.size()]
	var scene := load("res://scenes/npc_ship.tscn") as PackedScene
	if scene == null:
		return
	var arriving := randf() < 0.5 if forced_arriving < 0 else forced_arriving == 1
	var ship := scene.instantiate()
	ship.set("faction", _local_faction())
	ship.set("ship_role", ROLES[randi() % ROLES.size()])
	_serial += 1
	ship.name = "Traffic_%d" % _serial
	ship.set("persistent_id", "traffic.%d.%d" % [Time.get_ticks_msec(), _serial])
	ship.set_meta("npc_attack_protected", true)
	ship.set_meta("civilian_traffic", true)
	root.add_child(ship)
	# After _ready: the role setup there sets its own speed.
	ship.set("speed", forced_speed if forced_speed > 0.0 else 16.0)
	# The berth, not the station's centre (inside its model).
	var berth: Vector3 = station.get_docking_position(gate.global_position) if station.has_method("get_docking_position") else station.global_position
	var from: Vector3 = gate.global_position if arriving else berth
	var to: Vector3 = berth if arriving else gate.global_position
	# Start clear of the anchor: arrivals just off the gate, departures on the
	# gate-facing side of the berth so the way out isn't through the station.
	var toward := (to - from).normalized()
	var side := Vector3(randf_range(-1, 1), randf_range(-0.2, 0.2), randf_range(-1, 1)).normalized()
	(ship as Node3D).global_position = from + side * 70.0 if arriving else from + toward * 150.0 + side * 20.0
	(ship as Node3D).look_at(to, Vector3.UP)
	ship.set("patrol_center", to)
	var route: Array[Vector3] = [to]
	ship.set("patrol_route", route)
	_ships.append({"ship": ship, "dest": to, "kind": "dock" if arriving else "leave"})
	print("[Traffic] %s %s (%s) %s" % [ship.name, "inbound from the gate" if arriving else "leaving for the gate", ship.get("faction"), ship.get("ship_role")])


func _tick_ship(entry: Dictionary) -> void:
	var ship = entry["ship"]
	if not is_instance_valid(ship) or bool(ship.get("destroyed")):
		_ships.erase(entry)
		return
	var d := (ship as Node3D).global_position.distance_to(entry["dest"])
	# NPC steering doesn't route around planets: a freighter that stops
	# closing on its destination for 12 s is quietly retired (fades out).
	var now := Time.get_ticks_msec()
	if d < float(entry.get("best_dist", INF)) - 5.0:
		entry["best_dist"] = d
		entry["stuck_since"] = now
	elif now - int(entry.get("stuck_since", now)) > 12000:
		_ships.erase(entry)
		stuck_count += 1
		var fade := (ship as Node3D).create_tween()
		fade.tween_property(ship, "scale", Vector3.ONE * 0.05, 1.0)
		fade.tween_callback((ship as Node).queue_free)
		return
	if entry["kind"] == "dock" and d < DOCK_RADIUS:
		_ships.erase(entry)
		var tween := (ship as Node3D).create_tween()
		tween.tween_property(ship, "scale", Vector3.ONE * 0.05, 1.4).set_ease(Tween.EASE_IN)
		tween.tween_callback((ship as Node).queue_free)
		print("[Traffic] %s docked" % ship.name)
		docked_count += 1
	elif entry["kind"] == "leave" and d < GATE_RADIUS:
		_ships.erase(entry)
		var parent := (ship as Node3D).get_parent() as Node3D
		if parent != null:
			ImpactEffect.spawn_hit(parent, (ship as Node3D).global_position, Color(0.55, 0.85, 1.0), 3.0)
		print("[Traffic] %s jumped out" % ship.name)
		left_count += 1
		(ship as Node).queue_free()


## The system's own factions when known, else the three majors.
func _local_faction() -> String:
	var ui = GlobalState.get_ui_manager()
	if ui != null and ui.has_method("_get_current_system_faction_ids"):
		var ids: Array = ui._get_current_system_faction_ids()
		var majors := []
		for id in ids:
			if not GlobalState.is_minor_faction(str(id)):
				majors.append(str(id))
		if not majors.is_empty():
			return majors[randi() % majors.size()]
	return ["zenith", "aurelia", "vanguard"][randi() % 3]


## Jumps and restarts clear the old system's traffic.
func clear() -> void:
	for entry in _ships:
		if is_instance_valid(entry["ship"]):
			(entry["ship"] as Node).queue_free()
	_ships.clear()
	_timer = 8.0
