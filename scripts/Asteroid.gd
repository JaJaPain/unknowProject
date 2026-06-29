extends AnimatableBody3D

@export var max_resources: float = 25.0
@export var min_resources: float = 15.0
@export var persistent_id: String = ""
var resources: float = 300.0
var destroyed: bool = false
const FIRE_NOISE_PATH := "res://assets/T_Noise56ko.png"
const USE_MINING_HEAT_DECAL := false

# Orbiting variables
var orbit_center: Vector3 = Vector3.ZERO
var orbit_radius: float = 0.0
var orbit_speed: float = 0.0
var current_angle: float = 0.0
var orbit_y: float = 0.0
var is_orbiting: bool = false
var navigation_parent: Node3D = null
var _tumble_axis: Vector3 = Vector3.UP
var _tumble_speed: float = 0.0
var _tumble_base_speed: float = 0.0
var _mesh: MeshInstance3D = null
var _bob_amp1: float = 0.0
var _bob_freq1: float = 0.0
var _bob_phase1: float = 0.0
var _bob_amp2: float = 0.0
var _bob_freq2: float = 0.0
var _bob_phase2: float = 0.0
var _bob_time: float = 0.0
var _orbit_motion_factor: float = 1.0
var _orbit_hold_position: Vector3 = Vector3.ZERO
var _orbit_has_hold_position: bool = false
var _tractor_stable_until: float = 0.0
var _base_scale: Vector3 = Vector3.ONE
var _model_index: int = -1
var _mining_heat_decal: Decal = null
var _mining_heat_spot: MeshInstance3D = null
var _mining_heat_overlay: MeshInstance3D = null
var _mining_heat_material: ShaderMaterial = null
var _mining_heat_visible_until: float = 0.0
var _mining_heat_uv_offset := Vector2.ZERO

func _ready():
	add_to_group("asteroid")
	add_to_group(WorldIdentity.IDENTITY_GROUP)
	add_to_group("persistent_entity")
	if persistent_id == "":
		push_error("[Asteroid] Missing explicit persistent ID for '%s'." % name)
	var rng := RandomNumberGenerator.new()
	rng.seed = persistent_id.hash()
	max_resources = rng.randf_range(min_resources, max_resources)
	resources = max_resources
	var r_scale = randf_range(0.85, 1.4)
	scale = Vector3(r_scale, r_scale, r_scale)
	_base_scale = scale
	_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh:
		_model_index = AsteroidModels.model_index_for_seed(persistent_id.hash())
		AsteroidModels.apply_model_index(_mesh, _model_index)
	_tumble_axis = Vector3(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
	).normalized()
	_tumble_speed = rng.randf_range(0.05, 0.25)
	_tumble_base_speed = _tumble_speed
	_bob_amp1 = rng.randf_range(3.0, 6.0)
	_bob_freq1 = rng.randf_range(0.08, 0.2)
	_bob_phase1 = rng.randf_range(0.0, TAU)
	_bob_amp2 = rng.randf_range(1.5, 3.5)
	_bob_freq2 = rng.randf_range(0.15, 0.4)
	_bob_phase2 = rng.randf_range(0.0, TAU)

func _physics_process(delta: float):
	if destroyed or GlobalState.paused:
		return
	_bob_time += delta
	var now := Time.get_ticks_msec() / 1000.0
	var mining_held := now <= _mining_heat_visible_until
	_orbit_motion_factor = 0.0 if mining_held else lerpf(
		_orbit_motion_factor,
		1.0,
		min(1.0, delta * 2.0)
	)
	if is_orbiting:
		if mining_held and not _orbit_has_hold_position:
			_orbit_hold_position = global_position
			_orbit_has_hold_position = true
		if mining_held:
			global_position = _orbit_hold_position
		else:
			_orbit_has_hold_position = false
		current_angle += orbit_speed * delta * _orbit_motion_factor
		var x = orbit_center.x + cos(current_angle) * orbit_radius
		var z = orbit_center.z + sin(current_angle) * orbit_radius
		var y_offset = sin(_bob_time * _bob_freq1 + _bob_phase1) * _bob_amp1 \
			+ sin(_bob_time * _bob_freq2 + _bob_phase2) * _bob_amp2
		var target_orbit_pos := Vector3(
			x,
			orbit_y + y_offset * _orbit_motion_factor,
			z
		)
		if not mining_held:
			global_position = target_orbit_pos
	if _mesh and _tumble_base_speed > 0.0:
		if mining_held:
			_tumble_speed = 0.0
		else:
			_tumble_speed = lerpf(_tumble_speed, _tumble_base_speed, min(1.0, delta * 4.5))
		_mesh.rotate(_tumble_axis, _tumble_speed * delta)
	_update_mining_heat_spot(delta)


func show_mining_heat_spot(laser_origin: Vector3) -> void:
	if destroyed or _mesh == null:
		return
	_mining_heat_visible_until = Time.get_ticks_msec() / 1000.0 + 0.18
	if USE_MINING_HEAT_DECAL:
		_show_mining_heat_decal(laser_origin)
		return
	_ensure_mining_heat_spot()
	if _mining_heat_spot == null:
		return

	var contact_local := _mining_contact_local(laser_origin)
	var local_dir := contact_local.normalized()
	if local_dir == Vector3.ZERO:
		local_dir = Vector3.FORWARD

	_mining_heat_spot.position = contact_local
	_mining_heat_spot.look_at(global_transform * (contact_local + local_dir), Vector3.UP)
	_mining_heat_spot.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	_mining_heat_spot.scale = Vector3(0.65, 0.0012, 0.425)
	_mining_heat_spot.visible = true
	if _mining_heat_overlay:
		_mining_heat_overlay.visible = true
	if _mining_heat_material:
		_mining_heat_material.set_shader_parameter("alpha", 0.68)


func hold_mining_tractor(_laser_origin: Vector3) -> void:
	if destroyed:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_mining_heat_visible_until = now + 0.35
	_tractor_stable_until = now + 0.35
	_orbit_hold_position = global_position
	_orbit_has_hold_position = true
	_orbit_motion_factor = 0.0
	_tumble_speed = 0.0


func is_mining_tractor_stable() -> bool:
	return Time.get_ticks_msec() / 1000.0 <= _tractor_stable_until


func pull_to_mining_tractor_position(desired_position: Vector3, delta: float) -> bool:
	if destroyed:
		return false
	hold_mining_tractor(global_position)
	global_position = global_position.lerp(desired_position, min(1.0, delta * 5.0))
	return global_position.distance_to(desired_position) <= 0.45


func get_mining_contact_point(laser_origin: Vector3) -> Vector3:
	return global_transform * _mining_contact_local(laser_origin)


func _mining_contact_local(laser_origin: Vector3) -> Vector3:
	var local_origin := global_transform.affine_inverse() * laser_origin
	var local_dir := local_origin.normalized()
	if local_dir == Vector3.ZERO:
		local_dir = Vector3.FORWARD
	return local_dir * 4.88


func _show_mining_heat_decal(laser_origin: Vector3) -> void:
	_ensure_mining_heat_decal()
	if _mining_heat_decal == null:
		return
	var contact_local := _mining_contact_local(laser_origin)
	var local_dir := contact_local.normalized()
	if local_dir == Vector3.ZERO:
		local_dir = Vector3.FORWARD
	_mining_heat_decal.position = contact_local
	_mining_heat_decal.basis = _basis_with_y_axis(local_dir)
	_mining_heat_decal.visible = true
	_mining_heat_decal.modulate = Color(1.0, 0.50, 0.20, 1.0)
	_mining_heat_decal.emission_energy = 3.8


func _basis_with_y_axis(y_axis: Vector3) -> Basis:
	var y := y_axis.normalized()
	if y == Vector3.ZERO:
		y = Vector3.UP
	var helper := Vector3.UP
	if abs(y.dot(helper)) > 0.92:
		helper = Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _ensure_mining_heat_decal() -> void:
	if _mining_heat_decal and is_instance_valid(_mining_heat_decal):
		return
	var noise_texture := load(FIRE_NOISE_PATH) as Texture2D
	if noise_texture == null:
		return
	_mining_heat_decal = Decal.new()
	_mining_heat_decal.name = "AsteroidMiningHeatDecal"
	_mining_heat_decal.size = Vector3(1.6, 1.6, 1.6)
	var heat_texture := _create_mining_heat_decal_texture(noise_texture)
	_mining_heat_decal.texture_albedo = heat_texture
	_mining_heat_decal.texture_emission = heat_texture
	_mining_heat_decal.albedo_mix = 0.9
	_mining_heat_decal.modulate = Color(1.0, 0.46, 0.16, 0.0)
	_mining_heat_decal.emission_energy = 0.0
	_mining_heat_decal.upper_fade = 0.35
	_mining_heat_decal.lower_fade = 0.35
	_mining_heat_decal.normal_fade = 0.0
	_mining_heat_decal.visible = false
	add_child(_mining_heat_decal)


func _create_mining_heat_decal_texture(noise_texture: Texture2D) -> Texture2D:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise_image := noise_texture.get_image()
	for y in range(size):
		for x in range(size):
			var uv := Vector2(float(x) / float(size - 1), float(y) / float(size - 1))
			var from_center := (uv - Vector2(0.5, 0.5)).length()
			var radial := smoothstep(0.50, 0.12, from_center)
			var n := 0.7
			if noise_image:
				var nx := int(uv.x * float(noise_image.get_width() - 1))
				var ny := int(uv.y * float(noise_image.get_height() - 1))
				n = noise_image.get_pixel(nx, ny).r
			var ember: float = max(0.45, smoothstep(0.22, 0.95, n)) * radial
			var hot: float = smoothstep(0.70, 1.0, n) * radial
			var color := Color(1.0, 0.18 + hot * 0.50, 0.02, ember * 0.95)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _ensure_mining_heat_spot() -> void:
	if _mining_heat_spot and is_instance_valid(_mining_heat_spot):
		return
	var noise_texture := load(FIRE_NOISE_PATH) as Texture2D
	if noise_texture == null:
		return
	_mining_heat_spot = MeshInstance3D.new()
	_mining_heat_spot.name = "AsteroidMiningHeatSpot"
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 8
	_mining_heat_spot.mesh = mesh
	_mining_heat_spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mining_heat_spot.material_override = _create_mining_heat_rock_material()
	_mining_heat_spot.visible = false
	add_child(_mining_heat_spot)

	_mining_heat_overlay = MeshInstance3D.new()
	_mining_heat_overlay.name = "AsteroidMiningHeatFireOverlay"
	_mining_heat_overlay.mesh = mesh
	_mining_heat_overlay.scale = Vector3.ONE * 1.025
	_mining_heat_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = persistent_id.hash() ^ 0x5EED
	_mining_heat_material = _create_fragment_fire_material(noise_texture, rng)
	_mining_heat_material.set_shader_parameter("alpha", 0.68)
	_mining_heat_material.set_shader_parameter("uv_scale", 1.85)
	_mining_heat_material.set_shader_parameter("cutoff", 0.26)
	_mining_heat_overlay.material_override = _mining_heat_material
	_mining_heat_overlay.visible = false
	_mining_heat_spot.add_child(_mining_heat_overlay)


func _create_mining_heat_rock_material() -> StandardMaterial3D:
	var source := AsteroidModels.material_for_index(_model_index) as StandardMaterial3D
	if source == null and _mesh:
		source = _mesh.get_surface_override_material(0) as StandardMaterial3D
	if source == null and _mesh and _mesh.mesh:
		source = _mesh.mesh.surface_get_material(0) as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	if source:
		mat.albedo_texture = source.albedo_texture
		mat.uv1_scale = source.uv1_scale
		mat.uv1_offset = source.uv1_offset
		mat.roughness = source.roughness
		mat.metallic = source.metallic
	else:
		mat.roughness = 0.95
		mat.metallic = 0.1
	mat.albedo_color = Color(0.78, 0.72, 0.62, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return mat


func _update_mining_heat_spot(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _mining_heat_decal and is_instance_valid(_mining_heat_decal):
		if now > _mining_heat_visible_until:
			var decal_alpha: float = max(0.0, _mining_heat_decal.modulate.a - delta * 3.0)
			_mining_heat_decal.modulate.a = decal_alpha
			_mining_heat_decal.emission_energy = lerpf(_mining_heat_decal.emission_energy, 0.0, min(1.0, delta * 5.0))
			if decal_alpha <= 0.02:
				_mining_heat_decal.visible = false
	if _mining_heat_spot == null or not is_instance_valid(_mining_heat_spot):
		return
	if _mining_heat_material:
		_mining_heat_uv_offset += Vector2(0.025, -0.22) * delta
		_mining_heat_material.set_shader_parameter("uv_offset", _mining_heat_uv_offset)
	if now > _mining_heat_visible_until:
		var alpha := 0.0
		if _mining_heat_material:
			alpha = max(0.0, float(_mining_heat_material.get_shader_parameter("alpha")) - delta * 3.2)
			_mining_heat_material.set_shader_parameter("alpha", alpha)
		if alpha <= 0.02:
			_mining_heat_spot.visible = false
			if _mining_heat_overlay:
				_mining_heat_overlay.visible = false

func mine():
	if destroyed: return

	# Refuse to mine if the hold is carrying a special cargo item (e.g. a
	# part the mechanic gave us). The hold is mutually exclusive — ore
	# and special cargo cannot coexist.
	if not GlobalState.can_accept_ore():
		return

	# Calculate how much space is left in player's cargo
	var space_left = GlobalState.cargo_max - GlobalState.cargo
	if space_left <= 0.0:
		return

	# Mined amount is the minimum of:
	# 1. Player's mining yield
	# 2. Remaining asteroid resources
	# 3. Space left in cargo (Top-off logic!)
	var amount_to_mine = min(GlobalState.mining_yield, resources)
	amount_to_mine = min(amount_to_mine, space_left)

	if amount_to_mine > 0.0:
		var added = GlobalState.add_ore(amount_to_mine)
		resources -= added
		if added > 0.0 and GlobalState.has_method("report_player_mined_asteroid"):
			GlobalState.report_player_mined_asteroid(self)
		
		# Visual/text popups could be spawned here
		
		if resources <= 0.0:
			deplete()

func deplete():
	destroyed = true
	_record_persistent_state()
	AudioManager.play_explosion(global_position)
	_spawn_breakup_fx()
	# Remove from entities list if it was targeted
	if GlobalState.active_target == self:
		GlobalState.active_target = null
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	remove_from_group("asteroid")
	remove_from_group("persistent_entity")


func _spawn_breakup_fx() -> void:
	var parent := get_parent() as Node3D
	if parent == null:
		queue_free()
		return

	var fx_root := Node3D.new()
	fx_root.name = "AsteroidBreakupFX"
	parent.add_child(fx_root)
	fx_root.global_position = global_position

	var spawned_model_fragments := _spawn_model_fragments(fx_root)
	if not spawned_model_fragments:
		ImpactEffect.spawn_explosion(parent, global_position, Color(0.6, 0.5, 0.4), 0.6)
		_spawn_rock_chunks(fx_root)
	_spawn_ash_particles(fx_root)
	if spawned_model_fragments:
		_hide_and_free_asteroid()
	else:
		_fade_and_free_asteroid()


func _spawn_model_fragments(parent: Node3D) -> bool:
	if _model_index < 0 or _mesh == null:
		return false
	var fragment_path := AsteroidModels.fragment_scene_path_for_index(_model_index)
	if fragment_path == "" or not ResourceLoader.exists(fragment_path):
		return false
	var fragment_scene := load(fragment_path) as PackedScene
	if fragment_scene == null:
		return false
	var fragments_root := fragment_scene.instantiate() as Node3D
	if fragments_root == null:
		return false
	fragments_root.name = "AsteroidFracturedModel"
	parent.add_child(fragments_root)
	fragments_root.global_transform = _mesh.global_transform

	var material := _create_fragment_material(_model_index)
	var shards: Array[MeshInstance3D] = []
	_collect_fragment_meshes(fragments_root, shards)
	if shards.is_empty():
		fragments_root.queue_free()
		return false

	var rng := RandomNumberGenerator.new()
	rng.seed = persistent_id.hash() ^ int(Time.get_ticks_msec())
	for shard in shards:
		_prepare_fragment_shard(shard, material, rng)
	return true


func _collect_fragment_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_fragment_meshes(child, meshes)


func _create_fragment_material(model_index: int) -> StandardMaterial3D:
	var base := AsteroidModels.material_for_index(model_index) as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	if base:
		mat.albedo_texture = base.albedo_texture
		mat.uv1_scale = base.uv1_scale
		mat.uv1_offset = base.uv1_offset
		mat.roughness = base.roughness
		mat.metallic = base.metallic
	else:
		mat.roughness = 0.95
		mat.metallic = 0.1
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.72, 0.66, 0.56, 1.0)
	mat.emission_enabled = false
	mat.emission_energy_multiplier = 0.0
	return mat


func _prepare_fragment_shard(
		shard: MeshInstance3D,
		source_material: StandardMaterial3D,
		rng: RandomNumberGenerator
) -> void:
	var mat := source_material.duplicate() as StandardMaterial3D
	shard.set_surface_override_material(0, mat)
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fire_overlay := _add_fragment_fire_overlay(shard, rng)
	if rng.randf() < 0.75:
		_add_fragment_dust_trail(shard, rng)

	var start_pos := shard.position
	var dir := start_pos.normalized()
	if dir == Vector3.ZERO:
		dir = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-0.45, 0.85),
			rng.randf_range(-1.0, 1.0)
		).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.UP

	var separation_duration := rng.randf_range(1.15, 1.55)
	var shrink_duration := rng.randf_range(1.1, 1.6)
	var end_pos := start_pos + dir * rng.randf_range(3.0, 7.0)
	var tumble := Vector3(
		rng.randf_range(-PI, PI),
		rng.randf_range(-PI, PI),
		rng.randf_range(-PI, PI)
	)
	var tween := shard.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shard, "position", end_pos, separation_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(shard, "rotation", shard.rotation + tumble, separation_duration)
	tween.tween_property(shard, "scale", Vector3.ZERO, shrink_duration).set_delay(separation_duration)
	if fire_overlay:
		var fire_mat := fire_overlay.material_override as ShaderMaterial
		if fire_mat:
			var fire_start_alpha := float(fire_mat.get_shader_parameter("alpha"))
			var fire_lifetime := separation_duration + 0.45
			var fire_end_offset := Vector2(
				rng.randf_range(-0.16, 0.16),
				rng.randf_range(-0.75, -0.45)
			)
			tween.tween_method(
				func(value: Vector2) -> void:
					fire_mat.set_shader_parameter("uv_offset", value),
				Vector2.ZERO,
				fire_end_offset,
				fire_lifetime
			)
			tween.tween_method(
				func(value: float) -> void:
					fire_mat.set_shader_parameter("alpha", value),
				fire_start_alpha,
				0.0,
				fire_lifetime
			)
	tween.tween_property(
		mat,
		"albedo_color",
		Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, 0.0),
		shrink_duration
	).set_delay(separation_duration + 0.15)
	tween.chain().tween_callback(shard.queue_free)


func _add_fragment_fire_overlay(
		shard: MeshInstance3D,
		rng: RandomNumberGenerator
) -> MeshInstance3D:
	var noise_texture := load(FIRE_NOISE_PATH) as Texture2D
	if noise_texture == null or shard.mesh == null:
		return null

	var overlay := MeshInstance3D.new()
	overlay.name = "AsteroidFireOverlay"
	overlay.mesh = shard.mesh
	overlay.scale = Vector3.ONE * rng.randf_range(1.045, 1.075)
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.material_override = _create_fragment_fire_material(noise_texture, rng)
	shard.add_child(overlay)
	return overlay


func _create_fragment_fire_material(
		noise_texture: Texture2D,
		rng: RandomNumberGenerator
) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D noise_tex : source_color, repeat_enable;
uniform vec4 ember_color : source_color = vec4(1.0, 0.22, 0.035, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.78, 0.22, 1.0);
uniform float alpha = 0.62;
uniform float cutoff = 0.30;
uniform float uv_scale = 1.65;
uniform vec2 uv_offset = vec2(0.0, 0.0);

void fragment() {
	float n = texture(noise_tex, UV * uv_scale + uv_offset).r;
	float flame = smoothstep(cutoff, 1.0, n);
	float hot = smoothstep(0.78, 1.0, n);
	vec3 color = mix(ember_color.rgb, hot_color.rgb, hot);
	ALBEDO = color;
	EMISSION = color * (1.7 + hot * 2.4);
	ALPHA = flame * alpha;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("noise_tex", noise_texture)
	mat.set_shader_parameter("alpha", rng.randf_range(0.55, 0.72))
	mat.set_shader_parameter("uv_scale", rng.randf_range(0.85, 1.35))
	mat.set_shader_parameter("cutoff", rng.randf_range(0.24, 0.36))
	return mat


func _add_fragment_dust_trail(
		shard: MeshInstance3D,
		rng: RandomNumberGenerator
) -> void:
	var dust_parent := shard.get_parent() as Node3D
	if dust_parent == null:
		return
	var dust := GPUParticles3D.new()
	dust.name = "AsteroidDustTrail"
	dust.one_shot = true
	dust.amount = rng.randi_range(24, 40)
	dust.lifetime = rng.randf_range(2.0, 2.45)
	dust.explosiveness = 0.45
	dust.randomness = 0.55
	dust.fixed_fps = 30
	dust.emitting = true
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.position = shard.position

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(
		rng.randf_range(-0.25, 0.25),
		rng.randf_range(-0.15, 0.2),
		rng.randf_range(-0.25, 0.25)
	).normalized()
	if proc.direction == Vector3.ZERO:
		proc.direction = Vector3.UP
	proc.spread = 120.0
	proc.initial_velocity_min = 0.35
	proc.initial_velocity_max = 1.8
	proc.gravity = Vector3.ZERO
	proc.damping_min = 0.6
	proc.damping_max = 2.2
	proc.scale_min = 0.05
	proc.scale_max = 0.18

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.46, 0.40, 0.33, 0.38))
	gradient.add_point(0.35, Color(0.32, 0.29, 0.24, 0.22))
	gradient.set_color(1, Color(0.12, 0.11, 0.10, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	proc.color_ramp = grad_tex
	dust.process_material = proc

	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.08
	dust_mesh.height = 0.16
	dust_mesh.radial_segments = 4
	dust_mesh.rings = 2
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.albedo_color = Color(0.36, 0.31, 0.25, 0.32)
	dust_mesh.material = dust_mat
	dust.draw_pass_1 = dust_mesh

	dust_parent.add_child(dust)
	if dust_parent.is_inside_tree():
		var timer := dust_parent.get_tree().create_timer(dust.lifetime + 0.35)
		timer.timeout.connect(dust.queue_free)


func _spawn_rock_chunks(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = persistent_id.hash() ^ int(Time.get_ticks_msec())
	var chunk_count := rng.randi_range(9, 14)
	for index in range(chunk_count):
		var chunk := MeshInstance3D.new()
		chunk.name = "AsteroidChunk"
		var mesh := SphereMesh.new()
		var chunk_radius := rng.randf_range(0.18, 0.55)
		mesh.radius = chunk_radius
		mesh.height = chunk_radius * rng.randf_range(1.4, 2.3)
		mesh.radial_segments = 6
		mesh.rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(
			rng.randf_range(0.25, 0.42),
			rng.randf_range(0.22, 0.34),
			rng.randf_range(0.18, 0.28),
			1.0
		)
		mat.roughness = 0.95
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.35, 0.08)
		mat.emission_energy_multiplier = rng.randf_range(0.15, 0.65)
		mesh.material = mat
		chunk.mesh = mesh
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(chunk)

		var dir := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-0.5, 0.8),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		if dir == Vector3.ZERO:
			dir = Vector3.UP
		chunk.position = dir * rng.randf_range(0.4, 1.2)
		chunk.rotation = Vector3(
			rng.randf_range(0.0, TAU),
			rng.randf_range(0.0, TAU),
			rng.randf_range(0.0, TAU)
		)
		var end_pos := chunk.position + dir * rng.randf_range(5.0, 12.0)
		var tumble := Vector3(
			rng.randf_range(-TAU, TAU),
			rng.randf_range(-TAU, TAU),
			rng.randf_range(-TAU, TAU)
		)
		var tween := chunk.create_tween()
		tween.set_parallel(true)
		tween.tween_property(chunk, "position", end_pos, rng.randf_range(0.75, 1.25)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(chunk, "rotation", chunk.rotation + tumble, rng.randf_range(0.75, 1.25))
		tween.tween_property(chunk, "scale", Vector3.ZERO, rng.randf_range(0.85, 1.35)).set_delay(0.18)
		tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.8)
		tween.chain().tween_callback(chunk.queue_free)


func _spawn_ash_particles(parent: Node3D) -> void:
	var ash := GPUParticles3D.new()
	ash.name = "AsteroidAsh"
	ash.one_shot = true
	ash.amount = 70
	ash.lifetime = 1.4
	ash.explosiveness = 0.92
	ash.fixed_fps = 30
	ash.emitting = true
	ash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.ZERO
	proc.spread = 180.0
	proc.initial_velocity_min = 2.5
	proc.initial_velocity_max = 12.0
	proc.gravity = Vector3.ZERO
	proc.scale_min = 0.08
	proc.scale_max = 0.32
	proc.damping_min = 2.0
	proc.damping_max = 7.0
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.95, 0.7, 0.38, 0.65))
	gradient.add_point(0.22, Color(0.45, 0.38, 0.32, 0.48))
	gradient.set_color(1, Color(0.08, 0.08, 0.08, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	proc.color_ramp = grad_tex
	ash.process_material = proc

	var ash_mesh := SphereMesh.new()
	ash_mesh.radius = 0.08
	ash_mesh.height = 0.16
	ash_mesh.radial_segments = 4
	ash_mesh.rings = 2
	var ash_mat := StandardMaterial3D.new()
	ash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ash_mat.albedo_color = Color(0.45, 0.38, 0.32, 0.42)
	ash_mesh.material = ash_mat
	ash.draw_pass_1 = ash_mesh
	parent.add_child(ash)

	var timer := parent.get_tree().create_timer(4.0)
	timer.timeout.connect(parent.queue_free)


func _hide_and_free_asteroid() -> void:
	if _mesh:
		_mesh.visible = false
	visible = false
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(queue_free)


func _fade_and_free_asteroid() -> void:
	if _mesh == null:
		queue_free()
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", _base_scale * 0.18, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_mesh, "transparency", 1.0, 0.45)
	tween.chain().tween_callback(queue_free)

func get_persistent_id() -> String:
	return get_world_id()

func get_world_id() -> String:
	return persistent_id

func get_world_type_id() -> String:
	return "entity_type.asteroid"

func get_state_schema_version() -> int:
	return 1

func capture_state() -> Dictionary:
	return {
		"type": "asteroid",
		"resources": resources,
		"destroyed": destroyed,
	}

func restore_state(state: Dictionary) -> void:
	resources = clampf(float(state.get("resources", max_resources)), 0.0, max_resources)
	destroyed = false
	if bool(state.get("destroyed", false)) or resources <= 0.0:
		resources = max_resources

func _record_persistent_state() -> void:
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("record_persistent_entity_state"):
		game_root.record_persistent_entity_state(self)
