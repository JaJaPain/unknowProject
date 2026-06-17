extends RefCounted

const STARFIELD_SHADER := preload("res://shaders/starfield.gdshader")

const SUN_DISTANCE := 6000.0
const SUN_RADIUS := 90.0
const STARFIELD_RADIUS := 8500.0


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
	mat.emission_energy_multiplier = energy * 2.0
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
	system_root.add_child(sun)
	sun.global_position = sun_pos

	var light := system_root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if light == null:
		light = DirectionalLight3D.new()
		light.name = "DirectionalLight3D"
		system_root.add_child(light)
	light.light_color = color
	light.light_energy = light_energy
	light.shadow_enabled = true
	light.look_at_from_position(sun_pos, Vector3.ZERO)

	return sun


static func add_starfield(system_root: Node3D, config: Dictionary = {}) -> MeshInstance3D:
	var seed_val: float = config.get("seed", 0.0)
	var density: float = config.get("density", 0.04)
	var twinkle: float = config.get("twinkle_speed", 0.4)
	var color_tint: Color = config.get("tint", Color(0.9, 0.92, 1.0))

	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = STARFIELD_SHADER
	shader_mat.set_shader_parameter("seed_offset", seed_val)
	shader_mat.set_shader_parameter("star_density", density)
	shader_mat.set_shader_parameter("twinkle_speed", twinkle)
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
	system_root.add_child(field)
	field.global_position = Vector3.ZERO
	return field
