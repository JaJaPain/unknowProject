class_name SystemFactory
extends RefCounted

const SystemAmbience := preload("res://scripts/visuals/SystemAmbience.gd")

var _station_scene: PackedScene
var _asteroid_scene: PackedScene
var _gate_scene: PackedScene
var _rocky_texture: Texture2D
var _gas_texture: Texture2D


func _load_resources() -> void:
	_station_scene = load("res://scenes/station.tscn") as PackedScene
	_asteroid_scene = load("res://scenes/asteroid.tscn") as PackedScene
	_gate_scene = load("res://scenes/jump_gate.tscn") as PackedScene
	_rocky_texture = load("res://assets/planet_rocky.png") as Texture2D
	_gas_texture = load("res://assets/planet_gas.png") as Texture2D

const STATION_MODELS := [
	"res://assets/space_station1.glb",
	"res://assets/space_station2.glb",
]
const STATION_SCALES := [2.0, 20.0]

const MIN_PLANET_SPACING := 800.0
const MIN_STATION_CLEARANCE := 200.0
const MIN_GATE_CLEARANCE := 350.0
const SYSTEM_RADIUS := 2500.0

const PLANET_TINTS := [
	Color(0.92, 0.58, 0.38),
	Color(0.58, 0.72, 1.0),
	Color(0.62, 0.78, 0.68),
	Color(0.85, 0.75, 0.55),
	Color(0.7, 0.55, 0.8),
	Color(0.5, 0.7, 0.75),
	Color(0.9, 0.8, 0.6),
]

const STATION_NAMES := [
	"Exchange", "Outpost", "Depot", "Watch", "Relay",
	"Haven", "Beacon", "Anchorage", "Port", "Hub",
]

var rng := RandomNumberGenerator.new()
var _placed_positions: Array[Vector3] = []
var _placed_radii: Array[float] = []


static func generate(config: SystemConfig) -> Dictionary:
	var factory := SystemFactory.new()
	factory.rng.seed = config.seed_value
	factory._load_resources()
	return factory._build(config)


func _build(config: SystemConfig) -> Dictionary:
	var root := Node3D.new()
	root.name = config.legacy_id.to_pascal_case()

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = config.ambient_color
	env.ambient_light_energy = config.ambient_energy

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	root.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.shadow_enabled = true
	root.add_child(light)

	var planet_count := rng.randi_range(config.planet_count_min, config.planet_count_max)
	var planets: Array[Node3D] = []
	var ring_specs: Array[Dictionary] = []
	for i in range(planet_count):
		var result_pair := _create_planet(config, i)
		if result_pair.has("planet"):
			var planet: Node3D = result_pair["planet"]
			root.add_child(planet)
			planets.append(planet)
			if result_pair.has("ring"):
				var ring: Dictionary = result_pair["ring"]
				ring["parent"] = root
				ring["planet"] = planet
				ring_specs.append(ring)

	for ring in ring_specs:
		_spawn_asteroid_ring(
			ring["planet"] as Node3D,
			ring["parent"] as Node3D,
			float(ring["ring_radius"]),
			float(ring["ring_width"]),
			int(ring["count"]),
			str(ring["key"]),
			config.seed_value
		)

	var stations: Array[Dictionary] = []
	for i in range(config.station_count):
		var station_data := _create_station(config, i, planets)
		if station_data.has("node"):
			root.add_child(station_data["node"])
			stations.append(station_data)

	var sun_angle := rng.randf_range(0.0, TAU)
	var sun_dir := Vector3(cos(sun_angle), rng.randf_range(0.25, 0.5), sin(sun_angle)).normalized()
	SystemAmbience.add_sun(root, {
		"direction": sun_dir,
		"color": config.star_color,
		"energy": config.star_energy,
		"light_energy": config.star_light_energy,
	})
	SystemAmbience.add_starfield(root, {
		"seed": config.starfield_seed,
		"tint": config.starfield_tint,
	})

	var npc_mgr_script = load("res://scripts/generation/GeneratedSystemNPCManager.gd")
	if npc_mgr_script:
		var npc_mgr := Node.new()
		npc_mgr.name = "NPCManager"
		npc_mgr.set_script(npc_mgr_script)
		npc_mgr.call("initialize", config)
		root.add_child(npc_mgr)

	var station_ids: Array[String] = []
	for s in stations:
		station_ids.append(str(s.get("world_id", "")))

	return {
		"ok": true,
		"root": root,
		"station_ids": station_ids,
		"planet_count": planets.size(),
	}


func _create_planet(config: SystemConfig, index: int) -> Dictionary:
	var is_gas := rng.randf() < 0.35
	var radius := rng.randf_range(200.0, 550.0) if is_gas else rng.randf_range(150.0, 350.0)
	var pos := _find_placement(radius + MIN_PLANET_SPACING, 30)
	if pos == Vector3.INF:
		return {}

	var planet := StaticBody3D.new()
	planet.name = "Planet_%d" % index
	planet.collision_layer = 1
	planet.collision_mask = 6
	planet.add_to_group("celestial")

	var tint: Color = PLANET_TINTS[rng.randi() % PLANET_TINTS.size()]
	var texture: Texture2D = _gas_texture if is_gas else _rocky_texture
	planet.set_meta("display_name", "%s %s" % [config.system_name.get_slice(" ", 0), _roman_numeral(index + 1)])
	planet.set_meta("generation_seed", config.seed_value)

	var ring_radius := 0.0
	var ring_width := 0.0
	if not is_gas and rng.randf() < 0.4:
		ring_radius = radius + rng.randf_range(120.0, 250.0)
		ring_width = rng.randf_range(60.0, 140.0)

	var physical_clearance := radius + maxf(100.0, radius * 0.25)
	var ring_clearance := (ring_radius + ring_width * 0.5 + 90.0) if ring_radius > 0.0 else 0.0
	planet.set_meta("navigation_clearance_radius", maxf(physical_clearance, ring_clearance))

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.roughness = 0.88
	material.metallic = 0.08

	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	mesh.material = material

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	mesh_instance.mesh = mesh
	planet.add_child(mesh_instance)

	var shape := SphereShape3D.new()
	shape.radius = radius
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	planet.add_child(collision)

	planet.position = pos

	var out := {"planet": planet}
	if ring_radius > 0.0:
		out["ring"] = {
			"ring_radius": ring_radius,
			"ring_width": ring_width,
			"count": rng.randi_range(16, 36),
			"key": "planet%d" % index,
		}
	return out


func _create_station(config: SystemConfig, index: int, planets: Array[Node3D]) -> Dictionary:
	var is_orbital := not planets.is_empty() and rng.randf() < 0.5
	var world_id := "station.%s.s%d" % [config.legacy_id, index]
	var name_suffix: String = STATION_NAMES[rng.randi() % STATION_NAMES.size()]
	var display_name := "%s %s" % [config.system_name.get_slice(" ", 0).to_upper(), name_suffix.to_upper()]
	var station_type := "outpost" if index > 0 else "full_service"

	var position := Vector3.ZERO
	if is_orbital:
		var planet: Node3D = planets[rng.randi() % planets.size()]
		var clearance := float(planet.get_meta("navigation_clearance_radius", 500.0))
		var orbit_radius := clearance + rng.randf_range(150.0, 350.0)
		var angle := rng.randf_range(0.0, TAU)
		position = planet.position + Vector3(cos(angle) * orbit_radius, 0.0, sin(angle) * orbit_radius)
	else:
		var found := _find_placement(MIN_STATION_CLEARANCE, 20)
		if found == Vector3.INF:
			return {}
		position = found

	var model_idx := rng.randi() % STATION_MODELS.size()

	var station := _station_scene.instantiate() as Node3D
	station.name = "Station_%d" % index
	station.set("world_id", world_id)
	station.set("display_name", display_name)
	station.set("station_type", station_type)
	station.set("model_path", STATION_MODELS[model_idx])
	station.set("model_instance_scale", STATION_SCALES[model_idx])
	station.position = position

	_placed_positions.append(position)
	_placed_radii.append(MIN_STATION_CLEARANCE)

	return {"node": station, "world_id": world_id, "display_name": display_name}


func _find_placement(clearance: float, max_attempts: int) -> Vector3:
	for _attempt in range(max_attempts):
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(600.0, SYSTEM_RADIUS)
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if _is_clear(pos, clearance):
			_placed_positions.append(pos)
			_placed_radii.append(clearance)
			return pos
	return Vector3.INF


func _is_clear(pos: Vector3, clearance: float) -> bool:
	for i in range(_placed_positions.size()):
		var min_dist := clearance + _placed_radii[i]
		if pos.distance_to(_placed_positions[i]) < min_dist:
			return false
	return true


func _spawn_asteroid_ring(
	planet: Node3D,
	parent: Node3D,
	ring_radius: float,
	ring_width: float,
	count: int,
	ring_key: String,
	seed_value: int
) -> void:
	for index in range(count):
		var angle := TAU * (float(index) / float(count)) + rng.randf_range(-0.035, 0.035)
		var radius := ring_radius + rng.randf_range(-ring_width * 0.5, ring_width * 0.5)
		var asteroid := _asteroid_scene.instantiate()
		asteroid.name = "%s_Ring_%02d" % [ring_key.capitalize(), index]
		asteroid.persistent_id = "entity.gen.asteroid.%s.%03d" % [ring_key, index]
		asteroid.orbit_center = planet.position
		asteroid.orbit_radius = radius
		asteroid.orbit_speed = rng.randf_range(0.003, 0.009)
		asteroid.current_angle = angle
		asteroid.orbit_y = planet.position.y + rng.randf_range(-8.0, 8.0)
		asteroid.is_orbiting = true
		asteroid.navigation_parent = planet
		parent.add_child(asteroid)
		var scale_factor := rng.randf_range(0.75, 1.65)
		asteroid.scale = Vector3.ONE * scale_factor


func _roman_numeral(n: int) -> String:
	match n:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
		5: return "V"
	return str(n)


static func add_gate_to_system(
	system_root: Node3D,
	gate_id: String,
	world_id: String,
	display_name: String,
	dest_system_id: String,
	dest_gate_id: String,
	dest_display_name: String,
	position: Vector3,
	rotation_y: float = 0.0
) -> Node3D:
	var gate_scene := load("res://scenes/jump_gate.tscn") as PackedScene
	var gate := gate_scene.instantiate() as Node3D
	gate.name = gate_id.to_pascal_case()
	gate.set("gate_id", gate_id)
	gate.set("world_id", world_id)
	gate.set("display_name", display_name)
	gate.set("destination_system_id", dest_system_id)
	gate.set("destination_gate_id", dest_gate_id)
	gate.set("destination_display_name", dest_display_name)
	system_root.add_child(gate)
	gate.position = position
	gate.rotation.y = rotation_y
	return gate
