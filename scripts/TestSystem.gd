extends Node3D

const SystemAmbience := preload("res://scripts/visuals/SystemAmbience.gd")

const SYSTEM_SEED := 4172026
const SYSTEM_ID := "test_system"
const SYSTEM_KEY := "system.test"
const STATION_SCENE := preload("res://scenes/station.tscn")
const ASTEROID_SCENE := preload("res://scenes/asteroid.tscn")
const ROCKY_TEXTURE := preload("res://assets/planet_rocky.png")
const GAS_TEXTURE := preload("res://assets/planet_gas.png")

var rng := RandomNumberGenerator.new()
var generated_planets: Array[Node3D] = []
var generated_stations: Array[Node3D] = []


func _ready() -> void:
	GlobalState.active_system_root = self
	GlobalState.current_system_id = SYSTEM_ID
	rng.seed = SYSTEM_SEED
	_generate_system()
	call_deferred("_refresh_overview")


func _generate_system() -> void:
	# Wide sectors keep the initial generator deterministic and navigable while
	# still exercising the same runtime construction used by future systems.
	var planet_specs := [
		{
			"key": "cinder",
			"display_name": "Cinder",
			"position": _jittered_position(Vector3(1250.0, 0.0, -850.0), 90.0),
			"radius": 280.0,
			"texture": ROCKY_TEXTURE,
			"tint": Color(0.92, 0.58, 0.38),
			"ring_radius": 470.0,
			"ring_width": 100.0,
			"asteroid_count": 28,
		},
		{
			"key": "vespera",
			"display_name": "Vespera",
			"position": _jittered_position(Vector3(-1750.0, 0.0, -1250.0), 110.0),
			"radius": 520.0,
			"texture": GAS_TEXTURE,
			"tint": Color(0.58, 0.72, 1.0),
			"ring_radius": 0.0,
			"ring_width": 0.0,
			"asteroid_count": 0,
		},
		{
			"key": "halcyon",
			"display_name": "Halcyon",
			"position": _jittered_position(Vector3(850.0, 0.0, 2050.0), 100.0),
			"radius": 390.0,
			"texture": ROCKY_TEXTURE,
			"tint": Color(0.62, 0.78, 0.68),
			"ring_radius": 650.0,
			"ring_width": 130.0,
			"asteroid_count": 36,
		},
	]

	for spec: Dictionary in planet_specs:
		var planet := _create_planet(spec)
		generated_planets.append(planet)
		if int(spec["asteroid_count"]) > 0:
			_spawn_asteroid_ring(
				planet,
				float(spec["ring_radius"]),
				float(spec["ring_width"]),
				int(spec["asteroid_count"]),
				str(spec["key"])
			)

	_create_orbital_station(
		"station.test.cinder_exchange",
		"CINDER EXCHANGE",
		generated_planets[0],
		760.0,
		deg_to_rad(38.0)
	)
	_create_orbital_station(
		"station.test.halcyon_watch",
		"HALCYON WATCH",
		generated_planets[2],
		930.0,
		deg_to_rad(218.0)
	)
	_create_station(
		"station.test.lantern",
		"LANTERN FREEPORT",
		_jittered_position(Vector3(-350.0, 0.0, 1050.0), 70.0),
		"full_service"
	)
	_validate_generated_layout()

	SystemAmbience.add_sun(self, {
		"color": Color(0.75, 0.85, 1.0),
		"energy": 3.0,
		"radius": 90.0,
	})
	SystemAmbience.add_starfield(self, {
		"seed": 137.0,
		"density": 0.58,
		"tint": Color(0.85, 0.88, 1.0),
	})


func _create_planet(spec: Dictionary) -> Node3D:
	var planet := StaticBody3D.new()
	planet.name = "Planet_%s" % str(spec["key"]).capitalize()
	planet.collision_layer = 1
	planet.collision_mask = 6
	planet.add_to_group("celestial")
	planet.set_meta("display_name", str(spec["display_name"]))
	planet.set_meta("generation_seed", SYSTEM_SEED)

	var radius := float(spec["radius"])
	var ring_radius := float(spec["ring_radius"])
	var ring_width := float(spec["ring_width"])
	var physical_clearance := radius + maxf(100.0, radius * 0.25)
	var ring_clearance := (
		ring_radius + ring_width * 0.5 + 90.0
		if ring_radius > 0.0
		else 0.0
	)
	planet.set_meta(
		"navigation_clearance_radius",
		maxf(physical_clearance, ring_clearance)
	)

	var material := StandardMaterial3D.new()
	material.albedo_texture = spec["texture"] as Texture2D
	material.albedo_color = spec["tint"] as Color
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

	add_child(planet)
	planet.global_position = spec["position"] as Vector3
	return planet


func _spawn_asteroid_ring(
	planet: Node3D,
	ring_radius: float,
	ring_width: float,
	count: int,
	ring_key: String
) -> void:
	for index in range(count):
		var angle := TAU * (float(index) / float(count)) \
			+ rng.randf_range(-0.035, 0.035)
		var radius := ring_radius + rng.randf_range(
			-ring_width * 0.5,
			ring_width * 0.5
		)
		var asteroid := ASTEROID_SCENE.instantiate()
		asteroid.name = "%s_Ring_%02d" % [ring_key.capitalize(), index]
		asteroid.persistent_id = "entity.test.asteroid.%s.%03d" % [
			ring_key,
			index,
		]
		asteroid.orbit_center = planet.global_position
		asteroid.orbit_radius = radius
		asteroid.orbit_speed = rng.randf_range(0.003, 0.009)
		asteroid.current_angle = angle
		asteroid.orbit_y = planet.global_position.y + rng.randf_range(-8.0, 8.0)
		asteroid.is_orbiting = true
		asteroid.navigation_parent = planet
		add_child(asteroid)
		asteroid.global_position = Vector3(
			planet.global_position.x + cos(angle) * radius,
			asteroid.orbit_y,
			planet.global_position.z + sin(angle) * radius
		)
		var scale_factor := rng.randf_range(0.75, 1.65)
		asteroid.scale = Vector3.ONE * scale_factor


func _create_orbital_station(
	world_id: String,
	display_name: String,
	planet: Node3D,
	orbit_radius: float,
	angle: float
) -> Node3D:
	var position := planet.global_position + Vector3(
		cos(angle) * orbit_radius,
		0.0,
		sin(angle) * orbit_radius
	)
	return _create_station(world_id, display_name, position, "outpost")


func _create_station(
	world_id: String,
	display_name: String,
	position: Vector3,
	station_type: String
) -> Node3D:
	var station := STATION_SCENE.instantiate() as Node3D
	station.name = world_id.get_slice(".", 2).to_pascal_case()
	station.set("world_id", world_id)
	station.set("display_name", display_name)
	station.set("station_type", station_type)
	add_child(station)
	station.global_position = position
	generated_stations.append(station)
	return station


func _validate_generated_layout() -> void:
	var return_gate := get_node_or_null("ReturnGate") as Node3D
	for station in generated_stations:
		for planet in generated_planets:
			var physical_radius := _planet_radius(planet)
			if station.global_position.distance_to(planet.global_position) \
					<= physical_radius + 120.0:
				push_error(
					"[TestSystem] Generated station '%s' intersects '%s'." % [
						station.name,
						planet.name,
					]
				)
	for planet in generated_planets:
		if return_gate and return_gate.global_position.distance_to(
			planet.global_position
		) <= float(planet.get_meta("navigation_clearance_radius", 0.0)) + 250.0:
			push_error(
				"[TestSystem] Return gate generated inside '%s' navigation envelope."
				% planet.name
			)


func _planet_radius(planet: Node3D) -> float:
	var collision := planet.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	if collision and collision.shape is SphereShape3D:
		return (collision.shape as SphereShape3D).radius
	return 0.0


func _jittered_position(base: Vector3, amount: float) -> Vector3:
	return base + Vector3(
		rng.randf_range(-amount, amount),
		rng.randf_range(-amount * 0.08, amount * 0.08),
		rng.randf_range(-amount, amount)
	)


func get_generation_seed() -> int:
	return SYSTEM_SEED


func get_generated_planets() -> Array[Node3D]:
	return generated_planets.duplicate()


func get_generated_stations() -> Array[Node3D]:
	return generated_stations.duplicate()


func _refresh_overview() -> void:
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("refresh_overview"):
		ui.refresh_overview()
