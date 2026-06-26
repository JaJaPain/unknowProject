extends Node3D

const SystemAmbience := preload("res://scripts/visuals/SystemAmbience.gd")
const PlanetRotation := preload("res://scripts/visuals/PlanetRotation.gd")
const AnomalyRegistryScript = preload("res://scripts/AnomalyRegistry.gd")

var ui_manager: Control
@onready var gas_giant: Node3D = $GasGiant
@onready var rocky_planet: Node3D = $RockyPlanet
@onready var station: StaticBody3D = $Station

var asteroid_scene = preload("res://scenes/asteroid.tscn")
var npc_ship_scene = preload("res://scenes/npc_ship.tscn")
var runtime_ship_sequence: int = 0

func _ready():
	GlobalState.active_system_root = self
	GlobalState.current_system_id = "start_system"
	ui_manager = GlobalState.get_ui_manager()
	var world_env := $WorldEnvironment as WorldEnvironment
	if world_env and world_env.environment:
		world_env.environment.glow_enabled = GlobalState.bloom_enabled
		GlobalState.bloom_changed.connect(func(enabled: bool) -> void:
			world_env.environment.glow_enabled = enabled
		)
	# Seed random number generator
	randomize()
	
	var rotation_rng := RandomNumberGenerator.new()
	rotation_rng.seed = 4172026
	PlanetRotation.apply(gas_giant, true, rotation_rng)
	PlanetRotation.apply(rocky_planet, false, rotation_rng)

	# Spawn Asteroid rings around Gas Giant (radius 600, ring at 850, width 150)
	_spawn_asteroid_ring(gas_giant, 850.0, 150.0, 75, "GasGiantBelt")
	
	# Spawn Asteroid rings around Rocky Planet (radius 250, ring at 370, width 80)
	_spawn_asteroid_ring(rocky_planet, 370.0, 80.0, 45, "RockyBelt")
	
	# Spawn NPC Ships
	_spawn_npc("zenith", Vector3(120, 0, 180), 12.0, "Logistics", "entity.start.patrol.zenith.logistics")
	_spawn_npc("zenith", Vector3(-120, 0, 190), 12.0, "MiningHauler", "entity.start.patrol.zenith.mining_hauler")
	
	# Close hostiles for easy testing near start area
	_spawn_npc("aurelia", Vector3(90, 0, 80), 14.0, "Interceptor", "entity.start.patrol.aurelia.inner")
	_spawn_npc("vanguard", Vector3(-90, 0, 80), 15.0, "Gunner", "entity.start.patrol.vanguard.inner")
	
	# Hostiles around Rocky Planet
	_spawn_npc("aurelia", rocky_planet.global_position + Vector3(40, 0, 40), 14.0, "Gunner", "entity.start.patrol.aurelia.rocky_01")
	_spawn_npc("aurelia", rocky_planet.global_position + Vector3(-50, 0, -40), 14.0, "Interceptor", "entity.start.patrol.aurelia.rocky_02")
	_spawn_npc("aurelia", rocky_planet.global_position + Vector3(0, 0, -80), 14.0, "MiningHauler", "entity.start.patrol.aurelia.rocky_03")
	
	# Hostiles around Gas Giant
	_spawn_npc("vanguard", gas_giant.global_position + Vector3(50, 0, 50), 15.0, "Gunner", "entity.start.patrol.vanguard.gas_01")
	_spawn_npc("vanguard", gas_giant.global_position + Vector3(-60, 0, -60), 15.0, "Interceptor", "entity.start.patrol.vanguard.gas_02")
	_spawn_npc("vanguard", gas_giant.global_position + Vector3(80, 0, 0), 15.0, "MiningHauler", "entity.start.patrol.vanguard.gas_03")

	
	SystemAmbience.add_sun(self, {
		"direction": Vector3(-0.7, 0.35, -0.7),
		"color": Color(1.0, 0.88, 0.6),
		"energy": 4.0,
		"light_energy": 1.2,
	})
	SystemAmbience.add_starfield(self, {"seed": 42.0})
	SystemAmbience.add_nebula(self, {
		"seed": 42,
		"colors": [Color(0.5, 0.2, 0.7), Color(0.2, 0.35, 0.85)],
		"brightness": 0.5,
	})

	# The persistent UI enters the tree after this system scene. Defer the first
	# overview refresh so UIManager has finished constructing its dynamic nodes.
	call_deferred("_populate_overview")
	
	# Spawn the salvager ship near space station
	_spawn_salvager()

	# Spawn anomaly nodes, then fire a delayed rumor hint if any spawned
	AnomalyRegistryScript.shared().generate_for_system(GlobalState.current_system_id, self)
	_schedule_anomaly_rumor()
	
	# Setup spawn check Timer for replacing destroyed ships
	var spawn_timer = Timer.new()
	spawn_timer.name = "NPCSpawnTimer"
	spawn_timer.wait_time = 30.0 # Check every 30 seconds
	spawn_timer.autostart = true
	spawn_timer.timeout.connect(_on_npc_spawn_timeout)
	add_child(spawn_timer)


func _spawn_asteroid_ring(
	planet: Node3D,
	radius: float,
	width: float,
	count: int,
	prefix: String
):
	var center := planet.global_position
	for i in range(count):
		var angle = randf() * TAU
		var offset_r = randf_range(-width / 2.0, width / 2.0)
		var r = radius + offset_r
		
		# Ring coordinates on horizontal XZ plane
		var x = center.x + cos(angle) * r
		var y = center.y + randf_range(-4.0, 4.0) # Slight vertical dispersion
		var z = center.z + sin(angle) * r
		
		var ast = asteroid_scene.instantiate()
		ast.name = prefix + "_Asteroid_" + str(i)
		# Keep the current key for save compatibility, but assign it explicitly.
		ast.persistent_id = ast.name
		
		# Setup orbiting variables on the asteroid
		ast.orbit_center = center
		ast.orbit_radius = r
		ast.orbit_speed = randf_range(0.005, 0.015) # Slow, majestic orbital speed
		ast.current_angle = angle
		ast.orbit_y = y
		ast.is_orbiting = true
		ast.navigation_parent = planet
		
		add_child(ast)
		ast.global_position = Vector3(x, y, z)

const _ROLE_PROFILE_KEY := {
	"Gunner":      "gunner",
	"Interceptor": "interceptor",
	"Logistics":   "logistics",
	"MiningHauler":"mining_hauler",
}

func _spawn_npc(
	faction_name: String,
	pos: Vector3,
	npc_speed: float,
	role: String = "",
	world_id: String = ""
):
	var npc = npc_ship_scene.instantiate()
	npc.faction = faction_name
	npc.speed = npc_speed
	npc.ship_role = role
	npc.persistent_id = world_id if not world_id.is_empty() else _next_runtime_ship_id("patrol")
	npc.name = faction_name.to_upper() + "_Patrol_" + str(randi() % 1000)
	add_child(npc)
	npc.global_position = pos
	# Apply faction combat profile for known major factions.
	var role_key: String = _ROLE_PROFILE_KEY.get(role, "gunner")
	var profile_key := faction_name + "_" + role_key
	var profile := FactionRegistry.get_profile(profile_key)
	if not profile.is_empty():
		npc.apply_faction_profile(profile)

func _populate_overview():
	if not ui_manager:
		ui_manager = GlobalState.get_ui_manager()
	if ui_manager and ui_manager.has_method("refresh_overview"):
		ui_manager.refresh_overview()

func _spawn_salvager():
	var salvager_script = load("res://scripts/NPCSalvager.gd")
	if salvager_script:
		var salvager = CharacterBody3D.new()
		salvager.set_script(salvager_script)
		salvager.name = "Scrapper_Flint"
		add_child(salvager)
		# Spawn near space station
		if station:
			salvager.global_position = station.global_position + Vector3(0, 0, 50.0)
			
		# Generate unique scrapper pilot name and backstory
		_generate_salvager_identity(salvager)

func _on_salvager_destroyed():
	# Respawn after 30 seconds
	var respawn_timer = get_tree().create_timer(30.0)
	respawn_timer.timeout.connect(_spawn_salvager)

func _generate_salvager_identity(salvager: Node3D):
	if not is_instance_valid(salvager):
		return

	LLMInterface.fetch_salvager_profile(
		_on_salvager_profile_generated.bind(salvager.get_instance_id())
	)


func _on_salvager_profile_generated(
	profile_data: Dictionary,
	salvager_instance_id: int
) -> void:
	var salvager := instance_from_id(salvager_instance_id) as Node3D
	if not is_instance_valid(salvager):
		return
	var p_name = profile_data.get("name", "Maeve Sterling")
	var p_backstory = profile_data.get(
		"backstory",
		"An independent scrapper looking for high-yield metals in the asteroid belts."
	)

	salvager.name = p_name

	var file = FileAccess.open("user://salvager_backstory.md", FileAccess.WRITE)
	if file:
		file.store_line("# PILOT PROFILE: " + p_name.to_upper())
		file.store_line("\n**Role:** Independent Salvager")
		file.store_line("\n**Backstory:**")
		file.store_line(p_backstory)
		file.close()
		print("[MainScene] Saved pilot backstory to user://salvager_backstory.md")

	GlobalState.emit_chatter(
		"SYSTEM",
		"Comms link established with independent scrapper: " + p_name,
		Color(0.0, 0.9, 0.9)
	)

func _on_npc_spawn_timeout():
	if GlobalState.destroyed_ships_pool > 0:
		GlobalState.destroyed_ships_pool -= 1
		_spawn_npc_flying_in()

	# Second salvager when the system has more than 5 wrecks
	var wreck_count = get_tree().get_nodes_in_group("wreckage").size()
	var salvager_count = get_tree().get_nodes_in_group("salvager").size()
	if wreck_count > 5 and salvager_count < 2:
		_spawn_salvager()

	# Occasional ambient minor faction troublemaker (~15% chance, max 2 alive)
	var minor_count = _count_minor_faction_ships()
	if minor_count < 2 and randf() < 0.15:
		_spawn_minor_faction_ship()

func _count_minor_faction_ships() -> int:
	var count = 0
	for entity in GlobalState.active_system_entities:
		if entity and is_instance_valid(entity) and not entity.get("destroyed"):
			var fac = entity.get("faction")
			if fac and GlobalState.is_minor_faction(fac):
				count += 1
	return count

func _spawn_minor_faction_ship():
	var minor_keys = GlobalState.MINOR_FACTIONS.keys()
	var faction_name = minor_keys[randi() % minor_keys.size()]
	
	# Patrol toward planets/belts — NOT the station (they're outlaws)
	var targets = [gas_giant.global_position, rocky_planet.global_position]
	var patrol_dest = targets[randi() % targets.size()]
	
	# Spawn from deep space
	var angle = randf() * TAU
	var spawn_dist = 1100.0
	var spawn_pos = patrol_dest + Vector3(cos(angle), 0, sin(angle)) * spawn_dist
	
	var npc = npc_ship_scene.instantiate()
	npc.faction = faction_name
	npc.speed = randf_range(10.0, 14.0)
	npc.name = faction_name.to_upper() + "_Roaming_" + str(randi() % 1000)
	npc.persistent_id = _next_runtime_ship_id("roaming")
	add_child(npc)
	npc.global_position = spawn_pos
	npc.patrol_center = patrol_dest
	
	print("[MainScene] Ambient minor faction spawned: ", npc.name)

func _spawn_npc_flying_in():
	var factions = ["zenith", "aurelia", "vanguard"]
	var faction_name: String
	var pressure: Dictionary = GlobalState.story_world_pressure
	var p_faction: String = str(pressure.get("faction", ""))
	var p_intensity: float = float(pressure.get("intensity", 0.0))
	if p_faction in factions and p_intensity > 0.0 and randf() < p_intensity:
		faction_name = p_faction
	else:
		faction_name = factions[randi() % factions.size()]
	
	# Choose a random direction on XZ plane
	var angle = randf() * TAU
	var spawn_dist = 1100.0 # Spawn far in deep space
	
	# Choose a target patrol center in the inner system
	var targets = [station.global_position, gas_giant.global_position, rocky_planet.global_position]
	var patrol_dest = targets[randi() % targets.size()]
	
	# Calculate spawn position
	var spawn_pos = patrol_dest + Vector3(cos(angle), 0, sin(angle)) * spawn_dist
	
	# Spawn NPC
	var npc = npc_ship_scene.instantiate()
	npc.faction = faction_name
	npc.speed = 13.0 # Slightly faster speed for flying in
	npc.ship_role = ["Gunner", "Interceptor", "Logistics", "MiningHauler"].pick_random()
	npc.name = faction_name.to_upper() + "_Incoming_" + str(randi() % 1000)
	npc.persistent_id = _next_runtime_ship_id("incoming")
	add_child(npc)
	npc.global_position = spawn_pos
	
	# Set its patrol center to the destination so it flies in
	npc.patrol_center = patrol_dest

func _next_runtime_ship_id(category: String) -> String:
	runtime_ship_sequence += 1
	return "entity.start.%s.%06d" % [category, runtime_ship_sequence]


func _schedule_anomaly_rumor() -> void:
	var delay := randf_range(8.0, 18.0)
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(self):
		return
	var rumor: Dictionary = AnomalyRegistryScript.shared().get_arrival_rumor()
	if rumor.is_empty():
		return
	GlobalState.emit_chatter(rumor["sender"], rumor["line"], Color(0.75, 0.75, 0.75))

