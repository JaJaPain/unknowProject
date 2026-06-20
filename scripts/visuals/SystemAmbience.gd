extends RefCounted

const STARFIELD_SHADER := preload("res://shaders/starfield.gdshader")
const NEBULA_SHADER := preload("res://shaders/nebula.gdshader")

const SUN_DISTANCE := 6000.0
const SUN_RADIUS := 90.0
const STARFIELD_RADIUS := 18000.0
const NEBULA_DISTANCE := 17000.0
const NEBULA_QUAD_WIDTH := 22000.0
const NEBULA_QUAD_HEIGHT := 11000.0

const NEBULA_TEXTURES := [
	preload("res://assets/nebula_cloud_1.png"),
	preload("res://assets/nebula_cloud_2.png"),
	preload("res://assets/nebula_cloud_3.png"),
	preload("res://assets/nebula_cloud_4.png"),
	preload("res://assets/nebula_cloud_5.png"),
]


static func add_sun(system_root: Node3D, config: Dictionary = {}) -> MeshInstance3D:
	var sun_direction: Vector3 = config.get("direction", Vector3(0.35, 0.7, 0.6)).normalized()
	var sun_pos: Vector3 = sun_direction * SUN_DISTANCE

	var radius: float = config.get("radius", SUN_RADIUS)
	var color: Color = config.get("color", Color(1.0, 0.98, 0.94))
	var energy: float = config.get("energy", 3.0)
	var light_energy: float = config.get("light_energy", 1.2)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy * 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	mesh.material = mat

	var sun := MeshInstance3D.new()
	sun.name = "Sun"
	sun.mesh = mesh
	sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sun.position = sun_pos
	system_root.add_child(sun)

	var light := system_root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light == null:
		light = DirectionalLight3D.new()
		light.name = "DirectionalLight3D"
		system_root.add_child(light)
	light.light_color = color
	light.light_energy = light_energy
	light.shadow_enabled = true
	light.position = sun_pos
	light.basis = Basis.looking_at((Vector3.ZERO - sun_pos).normalized(), Vector3.UP)

	return sun


static func add_starfield(system_root: Node3D, config: Dictionary = {}) -> MeshInstance3D:
	var seed_val: float = config.get("seed", 0.0)
	var density: float = config.get("density", 0.04)
	var color_tint: Color = config.get("tint", Color(0.9, 0.92, 1.0))

	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = STARFIELD_SHADER
	shader_mat.set_shader_parameter("seed_offset", seed_val)
	shader_mat.set_shader_parameter("star_density", density)
	shader_mat.set_shader_parameter("tint", Vector3(color_tint.r, color_tint.g, color_tint.b))

	var mesh := SphereMesh.new()
	mesh.radius = STARFIELD_RADIUS
	mesh.height = STARFIELD_RADIUS * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	mesh.material = shader_mat

	var field := MeshInstance3D.new()
	field.name = "Starfield"
	field.mesh = mesh
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.position = Vector3.ZERO
	system_root.add_child(field)
	return field


static func add_nebula(system_root: Node3D, config: Dictionary = {}) -> Node3D:
	var seed_val: int = int(config.get("seed", 0.0))
	var colors: Array = config.get("colors", [
		Color(0.45, 0.2, 0.7),
		Color(0.15, 0.35, 0.85),
	])
	var nebula_brightness: float = config.get("brightness", 0.5)
	var layer_count: int = config.get("layer_count", 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var container := Node3D.new()
	container.name = "Nebula"
	system_root.add_child(container)

	# Pick one direction in the sky for the nebula cluster
	var base_theta := rng.randf_range(0.0, TAU)
	var base_phi := rng.randf_range(0.4, 2.0)
	var base_dir := Vector3(
		sin(base_phi) * cos(base_theta),
		cos(base_phi),
		sin(base_phi) * sin(base_theta)
	).normalized()

	for i in range(layer_count):
		var tex_idx := rng.randi() % NEBULA_TEXTURES.size()
		var color: Color = colors[rng.randi() % colors.size()]

		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = NEBULA_SHADER
		shader_mat.set_shader_parameter("nebula_texture", NEBULA_TEXTURES[tex_idx])
		shader_mat.set_shader_parameter("tint_color", Vector3(color.r, color.g, color.b))
		shader_mat.set_shader_parameter("brightness", nebula_brightness * rng.randf_range(0.7, 1.0))
		shader_mat.render_priority = -1

		var quad := QuadMesh.new()
		quad.size = Vector2(NEBULA_QUAD_WIDTH, NEBULA_QUAD_HEIGHT)
		quad.material = shader_mat

		var billboard := MeshInstance3D.new()
		billboard.name = "NebulaLayer_%d" % i
		billboard.mesh = quad
		billboard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# Offset slightly from the base direction so layers overlap but aren't identical
		var offset_dir := base_dir
		if i > 0:
			var right := base_dir.cross(Vector3.UP).normalized()
			var up := right.cross(base_dir).normalized()
			offset_dir = (base_dir + right * rng.randf_range(-0.15, 0.15)
				+ up * rng.randf_range(-0.15, 0.15)).normalized()

		billboard.look_at_from_position(offset_dir * NEBULA_DISTANCE, Vector3.ZERO, Vector3.UP)
		billboard.rotate_object_local(Vector3.FORWARD, rng.randf_range(0.0, TAU))

		container.add_child(billboard)

	return container


static func apply_glow(env: Environment, connect_toggle: bool = true) -> void:
	if connect_toggle:
		GlobalState.bloom_changed.connect(func(enabled: bool) -> void:
			env.glow_enabled = enabled
		)
	if not GlobalState.bloom_enabled:
		return
	env.glow_enabled = true
	env.glow_intensity = 1.2
	env.glow_strength = 1.2
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.5
	env.set_glow_level(0, false)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, false)
	env.set_glow_level(4, true)
	env.set_glow_level(5, false)
	env.set_glow_level(6, false)
