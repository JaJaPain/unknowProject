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

	_assign_outpost_npcs()
	_spawn_initial_patrol()

	var timer := Timer.new()
	timer.name = "RespawnTimer"
	timer.wait_time = 30.0
	timer.autostart = true
	timer.timeout.connect(_on_respawn_timeout)
	add_child(timer)


func _assign_outpost_npcs() -> void:
	var system_root := get_parent() as Node3D
	if system_root == null:
		return
	for child in system_root.get_children():
		if child.is_in_group("station"):
			var stype = child.get("station_type")
			var wid = child.get("world_id")
			if stype == "outpost" and typeof(wid) == TYPE_STRING and wid != "":
				GlobalState.assign_generated_outpost_npcs(wid, config.seed_value + wid.hash())


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
		var pos := _pick_position_near_anchor(rng, anchors)
		_spawn_ship(faction_name, role, pos, "patrol")


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
	if anchors.is_empty():
		return

	var faction_name := _pick_faction_runtime()
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


func _spawn_minor_roamer() -> void:
	var system_root := get_parent() as Node3D
	if system_root == null:
		return
	var anchors := _collect_anchors(system_root)
	if anchors.is_empty():
		return

	var minor_keys: Array = GlobalState.MINOR_FACTIONS.keys()
	var faction_name: String = minor_keys[randi() % minor_keys.size()]
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


func _spawn_ship(faction_name: String, role: String, pos: Vector3, category: String) -> void:
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
	var cached_path: String = "res://assets/ships/generated/%s.glb" % model_seed
	if ResourceLoader.exists(cached_path):
		npc.custom_model_path = cached_path
	system_root.add_child(npc)
	npc.global_position = pos


func _collect_anchors(system_root: Node3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for node in system_root.get_children():
		if node is Node3D:
			if node.is_in_group("celestial") or node.is_in_group("station"):
				result.append((node as Node3D).global_position)
	if result.is_empty():
		result.append(Vector3.ZERO)
	return result


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
