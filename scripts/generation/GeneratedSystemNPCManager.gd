class_name GeneratedSystemNPCManager
extends Node

var config: SystemConfig
var runtime_ship_sequence: int = 0
var _npc_ship_scene: PackedScene
var _roles := ["Gunner", "Interceptor", "Logistics", "MiningHauler"]


func initialize(system_config: SystemConfig) -> void:
	config = system_config


func _ready() -> void:
	_npc_ship_scene = load("res://scenes/npc_ship.tscn") as PackedScene
	if _npc_ship_scene == null:
		push_error("[NPCManager] Failed to load npc_ship.tscn")
		return
	call_deferred("_finish_ready")


func _finish_ready() -> void:
	_assign_outpost_npcs()
	_spawn_initial_patrol()
	_connect_pre_generator()

	var timer := Timer.new()
	timer.name = "RespawnTimer"
	timer.wait_time = 30.0
	timer.autostart = true
	timer.timeout.connect(_on_respawn_timeout)
	add_child(timer)


func _connect_pre_generator() -> void:
	var game_root := get_tree().current_scene if get_tree() else null
	if game_root == null:
		return
	var pre_gen = game_root.get("ship_pre_generator")
	if pre_gen and pre_gen.has_signal("ship_generated"):
		if not pre_gen.ship_generated.is_connected(_on_ship_generated):
			pre_gen.ship_generated.connect(_on_ship_generated)


func _on_ship_generated(model_seed: String) -> void:
	var system_root := get_parent() as Node3D
	if system_root == null:
		return
	for entity in GlobalState.active_system_entities:
		if not entity or not is_instance_valid(entity):
			continue
		if not entity.has_meta("model_seed"):
			continue
		if entity.get_meta("model_seed") != model_seed:
			continue
		if not entity.has_method("apply_generated_model"):
			continue
		var model := ShipGenerator.load_runtime(model_seed)
		if model:
			entity.apply_generated_model(model)


func _assign_outpost_npcs() -> void:
	var system_root := get_parent() as Node3D
	if system_root == null:
		return
	for child in system_root.get_children():
		if child.is_in_group("station"):
			var stype = child.get("station_type")
			var wid = child.get("world_id")
			if typeof(wid) != TYPE_STRING or wid == "":
				continue
			if stype == "outpost":
				GlobalState.assign_generated_outpost_npcs(
					wid,
					config.seed_value + wid.hash(),
					config.faction_weights
				)
			elif stype == "full_service":
				GlobalState.assign_generated_station_npcs(
					wid,
					config.seed_value + wid.hash(),
					config.faction_weights
				)


func _spawn_initial_patrol() -> void:
	var system_root := get_parent() as Node3D
	if system_root == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed_value + 9999
	var anchors := _collect_anchors(system_root)

	for i in range(config.npc_patrol_count):
		var faction_name := _pick_faction(rng)
		var role: String = _roles[rng.randi() % _roles.size()]
		var patrol_route := _pick_civilian_patrol_route(system_root, role)
		var route_anchors: Array[Vector3] = patrol_route if not patrol_route.is_empty() else anchors
		var pos := _pick_position_near_anchor(rng, route_anchors)
		_spawn_ship(faction_name, role, pos, "patrol", patrol_route)


func _on_respawn_timeout() -> void:
	if GlobalState.destroyed_ships_pool > 0:
		GlobalState.destroyed_ships_pool -= 1
		_spawn_replacement()

	var minor_count := _count_minor_faction_ships()
	if minor_count < config.npc_minor_max and randf() < config.npc_minor_chance:
		_spawn_minor_roamer()


func _spawn_replacement() -> void:
	var system_root := get_parent() as Node3D
	if system_root == null:
		return
	var anchors := _collect_anchors(system_root)

	var faction_name := _pick_faction_runtime()
	var patrol_route: Array[Vector3] = []
	if GlobalState.is_minor_faction(faction_name):
		patrol_route = _pick_hostile_patrol_route(system_root)
		anchors = patrol_route if not patrol_route.is_empty() else _collect_open_space_anchors(system_root)
	if anchors.is_empty():
		return
	var role: String = _roles[randi() % _roles.size()]
	var target_pos: Vector3 = anchors[randi() % anchors.size()]

	var angle := randf() * TAU
	var spawn_pos := target_pos + Vector3(cos(angle), 0.0, sin(angle)) * 1100.0

	var npc := _npc_ship_scene.instantiate() as Node3D
	npc.faction = faction_name
	npc.speed = 13.0
	npc.ship_role = role
	npc.difficulty_multiplier = config.difficulty_multiplier
	npc.persistent_id = _next_id("incoming")
	npc.name = faction_name.to_upper() + "_Incoming_" + str(randi() % 1000)
	system_root.add_child(npc)
	npc.global_position = spawn_pos
	npc.patrol_center = target_pos
	if not patrol_route.is_empty():
		npc.patrol_route = patrol_route
		npc.patrol_route_index = patrol_route.find(target_pos)
		if npc.patrol_route_index < 0:
			npc.patrol_route_index = 0
	_apply_npc_profile(npc, faction_name)


func _spawn_minor_roamer() -> void:
	var system_root := get_parent() as Node3D
	if system_root == null:
		return
	var anchors := _pick_hostile_patrol_route(system_root)
	if anchors.is_empty():
		anchors = _collect_open_space_anchors(system_root)
	if anchors.is_empty():
		return

	var faction_name: String = _pick_minor_faction_runtime()
	var target_pos: Vector3 = anchors[randi() % anchors.size()]

	var angle := randf() * TAU
	var spawn_pos := target_pos + Vector3(cos(angle), 0.0, sin(angle)) * 1100.0

	var npc := _npc_ship_scene.instantiate() as Node3D
	npc.faction = faction_name
	npc.speed = randf_range(10.0, 14.0)
	npc.difficulty_multiplier = config.difficulty_multiplier
	npc.persistent_id = _next_id("roaming")
	npc.name = faction_name.to_upper() + "_Roaming_" + str(randi() % 1000)
	system_root.add_child(npc)
	npc.global_position = spawn_pos
	npc.patrol_center = target_pos
	if anchors.size() >= 2:
		npc.patrol_route = anchors
		npc.patrol_route_index = anchors.find(target_pos)
		if npc.patrol_route_index < 0:
			npc.patrol_route_index = 0
	_apply_npc_profile(npc, faction_name)


func _spawn_ship(
	faction_name: String,
	role: String,
	pos: Vector3,
	category: String,
	patrol_route: Array[Vector3] = []
) -> void:
	var system_root := get_parent() as Node3D
	if system_root == null or _npc_ship_scene == null:
		return
	var npc := _npc_ship_scene.instantiate() as Node3D
	npc.faction = faction_name
	npc.ship_role = role
	npc.speed = randf_range(10.0, 15.0)
	npc.difficulty_multiplier = config.difficulty_multiplier
	npc.persistent_id = _next_id(category)
	npc.name = faction_name.to_upper() + "_Patrol_" + str(randi() % 1000)
	var model_seed: String = "ship_%d_%d" % [config.seed_value, runtime_ship_sequence]
	npc.set_meta("model_seed", model_seed)
	if ShipGenerator.has_cached(model_seed):
		npc.custom_model_scene = ShipGenerator.load_runtime(model_seed)
	system_root.add_child(npc)
	npc.global_position = pos
	if not patrol_route.is_empty():
		npc.patrol_route = patrol_route
		npc.patrol_route_index = 0
		npc.patrol_center = patrol_route[0]
	_apply_npc_profile(npc, faction_name)


func _collect_anchors(system_root: Node3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for node in system_root.get_children():
		if node is Node3D:
			if node.is_in_group("celestial") or node.is_in_group("station"):
				result.append((node as Node3D).global_position)
	if result.is_empty():
		result.append(Vector3.ZERO)
	return result


func _collect_open_space_anchors(system_root: Node3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for node in system_root.get_children():
		if node is Node3D and node.is_in_group("celestial"):
			result.append((node as Node3D).global_position)
	if result.is_empty():
		for node in system_root.get_children():
			if node is Node3D and node.is_in_group("asteroid"):
				result.append((node as Node3D).global_position)
	if result.is_empty():
		result.append(Vector3.ZERO)
	return result


func _pick_hostile_patrol_route(system_root: Node3D) -> Array[Vector3]:
	var belt_route := _pick_asteroid_belt_route(system_root)
	if not belt_route.is_empty():
		return belt_route
	return _pick_shipping_lane_route(system_root)


func _pick_civilian_patrol_route(system_root: Node3D, role: String) -> Array[Vector3]:
	if role != "Logistics":
		return []
	return _pick_shipping_lane_route(system_root)


func _pick_asteroid_belt_route(system_root: Node3D) -> Array[Vector3]:
	var belts: Dictionary = {}
	for node in system_root.get_children():
		if not (node is Node3D) or not node.is_in_group("asteroid"):
			continue
		var belt_id := str(node.get_meta("belt_id", "")).strip_edges()
		if belt_id == "":
			belt_id = "unmarked"
		if not belts.has(belt_id):
			belts[belt_id] = []
		belts[belt_id].append(_node_route_position(node as Node3D))
	if belts.is_empty():
		return []
	var best_points: Array = []
	for belt_id in belts.keys():
		var points: Array = belts[belt_id]
		if points.size() > best_points.size():
			best_points = points
	if best_points.is_empty():
		return []
	var center := Vector3.ZERO
	for point: Vector3 in best_points:
		center += point
	center /= float(best_points.size())
	var route: Array[Vector3] = []
	for point: Vector3 in best_points:
		if point.distance_to(center) >= 40.0:
			route.append(point)
	if route.size() >= 2:
		route.sort_custom(func(a: Vector3, b: Vector3) -> bool:
			return atan2(a.z - center.z, a.x - center.x) < atan2(b.z - center.z, b.x - center.x)
		)
		if route.size() > 6:
			var sampled: Array[Vector3] = []
			for i in range(6):
				sampled.append(route[int(round(float(i) * float(route.size() - 1) / 5.0))])
			return sampled
		return route
	return [center]


func _pick_shipping_lane_route(system_root: Node3D) -> Array[Vector3]:
	var lanes := _collect_shipping_lane_routes(system_root)
	if lanes.is_empty():
		return []
	var selected: Array = lanes[randi() % lanes.size()]
	var route: Array[Vector3] = []
	for point: Vector3 in selected:
		route.append(point)
	return route


func _collect_shipping_lane_routes(system_root: Node3D) -> Array:
	var stations: Array[Node3D] = []
	for node in system_root.get_children():
		if node is Node3D and node.is_in_group("station"):
			stations.append(node)
	if stations.size() < 2:
		return []
	var lanes: Array = []
	for i in range(stations.size()):
		for j in range(i + 1, stations.size()):
			lanes.append([
				_node_route_position(stations[i]),
				_node_route_position(stations[j]),
			])
	return lanes


func _node_route_position(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


func _pick_position_near_anchor(rng: RandomNumberGenerator, anchors: Array[Vector3]) -> Vector3:
	var anchor: Vector3 = anchors[rng.randi() % anchors.size()]
	var angle := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(40.0, 120.0)
	return anchor + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _pick_faction(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	var cumulative := 0.0
	for faction_name: String in config.faction_weights:
		cumulative += float(config.faction_weights[faction_name])
		if roll <= cumulative:
			return faction_name
	return config.faction_weights.keys()[0] as String


func _pick_faction_runtime() -> String:
	var roll := randf()
	var cumulative := 0.0
	for faction_name: String in config.faction_weights:
		cumulative += float(config.faction_weights[faction_name])
		if roll <= cumulative:
			return faction_name
	return config.faction_weights.keys()[0] as String


func _pick_minor_faction_runtime() -> String:
	var minor_factions: Array[String] = []
	for faction_name: String in config.faction_weights:
		if GlobalState.is_minor_faction(faction_name):
			minor_factions.append(faction_name)
	if minor_factions.is_empty():
		minor_factions.assign(GlobalState.MINOR_FACTIONS.keys())

	var total := 0.0
	for faction_name: String in minor_factions:
		total += maxf(0.0, float(config.faction_weights.get(faction_name, 0.0)))
	if total <= 0.0:
		return minor_factions[randi() % minor_factions.size()]

	var roll := randf() * total
	var cumulative := 0.0
	for faction_name: String in minor_factions:
		cumulative += maxf(0.0, float(config.faction_weights.get(faction_name, 0.0)))
		if roll <= cumulative:
			return faction_name
	return minor_factions.back()


func _count_minor_faction_ships() -> int:
	var count := 0
	for entity in GlobalState.active_system_entities:
		if entity and is_instance_valid(entity) and not entity.get("destroyed"):
			var fac = entity.get("faction")
			if fac and GlobalState.is_minor_faction(fac):
				count += 1
	return count


func _next_id(category: String) -> String:
	runtime_ship_sequence += 1
	return "entity.%s.%s.%04d" % [config.legacy_id, category, runtime_ship_sequence]


const _KNOWN_FACTIONS := ["aurelia", "vanguard", "zenith"]
const _ROLE_KEY := {
	"Gunner": "gunner", "Interceptor": "interceptor",
	"Logistics": "logistics", "MiningHauler": "mining_hauler",
}

func _apply_npc_profile(npc: Node, faction_name: String) -> void:
	if not npc.has_method("apply_faction_profile"):
		return
	var profile: Dictionary
	if faction_name in _KNOWN_FACTIONS:
		var role: String = str(npc.get("ship_role") if npc.get("ship_role") else "Gunner")
		var role_key: String = _ROLE_KEY.get(role, "gunner")
		profile = FactionRegistry.get_profile(faction_name + "_" + role_key)
	else:
		# Unknown faction — pick from the band matching this system's difficulty tier.
		var tier: int = config.difficulty_tier if config else 1
		var faction_keys: Array = config.faction_weights.keys() if config else []
		var faction_idx: int = faction_keys.find(faction_name)
		if faction_idx < 0:
			faction_idx = 0
		profile = FactionRegistry.get_faction_for_danger_level(tier, faction_idx)
	if not profile.is_empty():
		npc.apply_faction_profile(profile)
