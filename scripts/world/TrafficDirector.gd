extends Node

## Station traffic (next_level_plan P5): every so often a freighter comes in
## through the jump gate and docks at the main station, or undocks and leaves
## through the gate. Haulers only (they never pick fights), protected from NPC
## attacks, a few at a time. Leaving ends in a flash at the gate.
##
## Docking is on the station's tractor beam, like the player's (Abe, playtest
## 2026-10-03 finding 5): close in, the station takes the freighter, pulls it
## to the berth, holds it there, then it slides in and is gone. Departures
## are pushed out on the beam before their engines take over. Outposts get
## traffic too (about one arrival in three).

const MAX_TRAFFIC := 3
const INTERVAL_MIN := 25.0
const INTERVAL_MAX := 50.0
# NPCs stop and circle ~70 m from their patrol point, so arrive inside 110.
const DOCK_RADIUS := 110.0
const GATE_RADIUS := 110.0
## The beam takes an inbound freighter this close to its berth.
const TRACTOR_RANGE := 350.0
## Same feel as the player's dock (UIManager.DOCK_TRACTOR_PULL_SECONDS).
const TRACTOR_PULL_S := 4.0
const CLAMP_HOLD_S := 1.5
const SLIDE_IN_S := 1.2
const PUSH_OUT_S := 3.0
const PUSH_OUT_DIST := 150.0
## Arrivals that go to an outpost instead of the main station.
const OUTPOST_SHARE := 0.33
const BeamType := preload("res://scripts/effects/DockingTractorBeam.gd")
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
## Test hook: 1 = an outpost, 0 = the main station, -1 = random.
var forced_outpost := -1
var tractored_count := 0
var outpost_docked_count := 0
## Berths with a ship on the beam: station instance id -> true.
var _busy_berths := {}
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
	# Some arrivals head for an outpost.
	var outposts := _outposts(root)
	var to_outpost := (randf() < OUTPOST_SHARE) if forced_outpost < 0 else forced_outpost == 1
	if to_outpost and not outposts.is_empty():
		station = outposts[randi() % outposts.size()]
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
	# A berth of its own, never the player's (Abe, 2026-10-05): its lane entry
	# on the approach sphere is where the beam takes it. Stations without
	# berths keep their single docking point.
	var dock_node: Node3D = _pick_berth(station)
	var berth: Vector3
	if dock_node != null:
		berth = station.call("lane_entry_position", dock_node)
	else:
		berth = station.get_docking_position(gate.global_position) if station.has_method("get_docking_position") else station.global_position
	var from: Vector3 = gate.global_position if arriving else berth
	var to: Vector3 = berth if arriving else gate.global_position
	if not arriving and dock_node != null:
		# Departures start at the pier itself, then the beam carries them out.
		from = station.call("berth_position", dock_node)
	# Arrivals start just off the gate; departures at the berth, on the beam.
	var toward := (to - from).normalized()
	var side := Vector3(randf_range(-1, 1), randf_range(-0.2, 0.2), randf_range(-1, 1)).normalized()
	(ship as Node3D).global_position = from + side * 70.0 if arriving else from
	(ship as Node3D).look_at(to, Vector3.UP)
	ship.set("patrol_center", to)
	var route: Array[Vector3] = [to]
	ship.set("patrol_route", route)
	var entry := {"ship": ship, "dest": to, "kind": "dock" if arriving else "leave", "station": station, "base_speed": float(ship.get("speed")), "berth": dock_node}
	_ships.append(entry)
	if not arriving:
		if dock_node != null:
			# Out along its own lane, past the safety zone, then the engines.
			var entry_point: Vector3 = station.call("lane_entry_position", dock_node)
			var out_dir := (entry_point - from).normalized()
			_face(ship as Node3D, entry_point)
			_push_out(entry, station, entry_point + out_dir * PUSH_OUT_DIST)
		else:
			_push_out(entry, station, from + toward * PUSH_OUT_DIST + side * 20.0)
	print("[Traffic] %s %s (%s) %s" % [ship.name, "inbound from the gate" if arriving else "leaving for the gate", ship.get("faction"), ship.get("ship_role")])


func _tick_ship(entry: Dictionary) -> void:
	var ship = entry["ship"]
	if not is_instance_valid(ship) or bool(ship.get("destroyed")):
		_release_berth(entry)
		_ships.erase(entry)
		return
	if bool(entry.get("on_beam", false)):
		return  # the beam's tweens own it now
	var d := (ship as Node3D).global_position.distance_to(entry["dest"])
	# Freighters cruise the long legs too (WorldScale; same as the player's
	# autopilot), back to normal speed for the last stretch.
	var k: float = preload("res://scripts/domain/WorldScale.gd").TRAVEL
	ship.set("speed", float(entry.get("base_speed", 16.0)) * lerpf(1.0, k, clampf((d - 1500.0) / 2500.0, 0.0, 1.0)))
	# NPC steering doesn't route around planets: a freighter that stops
	# closing on its destination for 12 s is quietly retired (fades out).
	var now := Time.get_ticks_msec()
	if d < float(entry.get("best_dist", INF)) - 5.0:
		entry["best_dist"] = d
		entry["stuck_since"] = now
	elif now - int(entry.get("stuck_since", now)) > 12000:
		_release_berth(entry)
		_ships.erase(entry)
		stuck_count += 1
		var fade := (ship as Node3D).create_tween()
		fade.tween_property(ship, "scale", Vector3.ONE * 0.05, 1.0)
		fade.tween_callback((ship as Node).queue_free)
		return
	if entry["kind"] == "dock" and d < TRACTOR_RANGE:
		var station = entry.get("station")
		if station == null or not is_instance_valid(station):
			_release_berth(entry)
			_ships.erase(entry)
			(ship as Node).queue_free()
			return
		# One ship on a berth's beam at a time; the next holds off until it's
		# clear (it keeps circling its approach point).
		if _busy_berths.has(_berth_key(station, entry.get("berth"))):
			return
		_tractor_in(entry, station)
	elif entry["kind"] == "leave" and d < GATE_RADIUS:
		_release_berth(entry)
		_ships.erase(entry)
		var parent := (ship as Node3D).get_parent() as Node3D
		if parent != null:
			ImpactEffect.spawn_hit(parent, (ship as Node3D).global_position, Color(0.55, 0.85, 1.0), 3.0)
		print("[Traffic] %s jumped out" % ship.name)
		left_count += 1
		(ship as Node).queue_free()


## The station takes an inbound freighter on its beam: pull to the berth,
## hold, slide in, gone.
func _tractor_in(entry: Dictionary, station: Node3D) -> void:
	var ship: Node3D = entry["ship"]
	entry["on_beam"] = true
	var key := _berth_key(station, entry.get("berth"))
	_busy_berths[key] = true
	tractored_count += 1
	_hold_engines(ship)
	var dock_node = entry.get("berth")
	if dock_node != null and not is_instance_valid(dock_node):
		dock_node = null
	var beam := _beam(dock_node if dock_node != null else station, ship)
	var berth: Vector3 = entry["dest"]
	if dock_node != null:
		_tractor_to_pier(entry, station, dock_node, beam, key)
		return
	# Nose along the way it's being moved, never at the station's centre while
	# being dragged somewhere else: that read as flying backwards (playtest
	# 2026-10-04 d finding 2; the new outposts' berths sit above or beside).
	_face(ship, berth)
	var tween := ship.create_tween()
	tween.tween_property(ship, "global_position", berth, TRACTOR_PULL_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(CLAMP_HOLD_S)
	tween.tween_callback(func() -> void:
		if is_instance_valid(beam):
			beam.queue_free()
		_face(ship, station.global_position))
	tween.tween_property(ship, "global_position", berth.lerp(station.global_position, 0.4), SLIDE_IN_S).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(ship, "scale", Vector3.ONE * 0.05, SLIDE_IN_S).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_busy_berths.erase(key)
		_release_berth(entry)
		_ships.erase(entry)
		docked_count += 1
		if str(station.get("station_type")) == "outpost":
			outpost_docked_count += 1
		print("[Traffic] %s docked at %s (tractor)" % [ship.name, str(station.get("display_name"))])
		ship.queue_free())


## Berths with traffic now: the player's is never among them, and two
## freighters don't share one while there's a free one.
var _berths_in_use := {}


## A free traffic berth at `station` (null at a station without berths).
func _pick_berth(station: Node3D) -> Node3D:
	if not station.has_method("traffic_berths") or not bool(station.call("is_berthed")):
		return null
	var all: Array = station.call("traffic_berths")
	if all.is_empty():
		return null
	var free: Array = all.filter(func(b): return not _berths_in_use.has(b.get_instance_id()))
	var pick: Node3D = (free if not free.is_empty() else all)[randi() % (free if not free.is_empty() else all).size()]
	_berths_in_use[pick.get_instance_id()] = true
	return pick


func _release_berth(entry: Dictionary) -> void:
	var b = entry.get("berth")
	if b != null and is_instance_valid(b):
		_berths_in_use.erase(b.get_instance_id())


static func _berth_key(station: Node3D, berth) -> int:
	if berth != null and is_instance_valid(berth):
		return (berth as Node).get_instance_id()
	return station.get_instance_id()


## A big station or outpost pier: the berth's own beam pulls the freighter
## from its lane entry onto the pier, nose along the pull, then it settles
## facing out like the player's ship, sits there a while (the piers look
## busy), and is gone.
const PIER_STAY_S := 8.0


func _tractor_to_pier(entry: Dictionary, station: Node3D, dock_node: Node3D, beam: Node3D, key: int) -> void:
	var ship: Node3D = entry["ship"]
	var pier: Vector3 = station.call("berth_position", dock_node)
	_face(ship, pier)
	var settle: Basis = station.call("berth_basis", dock_node)
	var tween := ship.create_tween()
	tween.tween_property(ship, "global_position", pier, TRACTOR_PULL_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(ship, "quaternion", settle.get_rotation_quaternion(), TRACTOR_PULL_S)
	tween.tween_interval(CLAMP_HOLD_S)
	tween.tween_callback(func() -> void:
		if is_instance_valid(beam):
			beam.queue_free()
		_busy_berths.erase(key)
		docked_count += 1
		if str(station.get("station_type")) == "outpost":
			outpost_docked_count += 1
		print("[Traffic] %s docked at %s, %s" % [ship.name, str(station.get("display_name")), dock_node.name]))
	tween.tween_interval(PIER_STAY_S)
	tween.tween_property(ship, "scale", Vector3.ONE * 0.05, SLIDE_IN_S).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_release_berth(entry)
		_ships.erase(entry)
		ship.queue_free())


## A departure starts on the beam at the berth and is pushed clear before its
## own engines take over.
func _push_out(entry: Dictionary, station: Node3D, clear_point: Vector3) -> void:
	var ship: Node3D = entry["ship"]
	entry["on_beam"] = true
	_hold_engines(ship)
	var dock_node = entry.get("berth")
	var beam := _beam(dock_node if dock_node != null and is_instance_valid(dock_node) else station, ship)
	var tween := ship.create_tween()
	tween.tween_property(ship, "global_position", clear_point, PUSH_OUT_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		if is_instance_valid(beam):
			beam.queue_free()
		_release_berth(entry)
		entry["on_beam"] = false
		entry.erase("best_dist")
		ship.set_physics_process(true))


## Turn `ship` to face `point` (another up when the line is vertical).
static func _face(ship: Node3D, point: Vector3) -> void:
	if not is_instance_valid(ship):
		return
	var dir := point - ship.global_position
	if dir.length() < 1.0:
		return
	var up := Vector3.FORWARD if absf(dir.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	ship.look_at(point, up)


## Engines off while the beam has it (its steering would fight the tween).
func _hold_engines(ship: Node3D) -> void:
	ship.set_physics_process(false)
	if "velocity" in ship:
		ship.set("velocity", Vector3.ZERO)


## The same beam the player gets, added at the scene root (stations are
## scaled, which once stretched the player's beam).
func _beam(station: Node3D, ship: Node3D) -> Node3D:
	var root := get_tree().current_scene if is_inside_tree() else null
	if root == null:
		return null
	var beam := BeamType.new()
	root.add_child(beam)
	beam.configure(station, ship)
	return beam


## This system's outposts.
func _outposts(root: Node) -> Array:
	var out := []
	for node in get_tree().get_nodes_in_group("station"):
		if node is Node3D and root.is_ancestor_of(node) and str(node.get("station_type")) == "outpost":
			out.append(node)
	return out


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
	_busy_berths.clear()
	_berths_in_use.clear()
	_timer = 8.0
