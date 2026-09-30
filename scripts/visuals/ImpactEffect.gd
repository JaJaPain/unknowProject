class_name ImpactEffect
extends RefCounted


static func spawn_hit(parent: Node3D, pos: Vector3, col: Color, size: float = 1.0) -> void:
	var container := Node3D.new()
	container.name = "HitFX"
	parent.add_child(container)
	container.global_position = pos

	# Billboard flash with radial gradient
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.5, 2.5) * size
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.albedo_color = col
	flash_mat.emission_enabled = true
	flash_mat.emission = col
	flash_mat.emission_energy_multiplier = 6.0
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_mat.no_depth_test = true
	var grad := Gradient.new()
	grad.set_color(0, Color.WHITE)
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.set_offset(0, 0.0)
	grad.set_offset(1, 1.0)
	var flash_tex := GradientTexture2D.new()
	flash_tex.gradient = grad
	flash_tex.fill = GradientTexture2D.FILL_RADIAL
	flash_tex.fill_from = Vector2(0.5, 0.5)
	flash_tex.fill_to = Vector2(0.5, 0.0)
	flash_tex.width = 64
	flash_tex.height = 64
	flash_mat.albedo_texture = flash_tex
	quad.material = flash_mat
	flash.mesh = quad
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	container.add_child(flash)

	var tween := container.create_tween()
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.15).from(Vector3.ONE)
	tween.parallel().tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.15)

	# Spark particles
	var sparks := GPUParticles3D.new()
	sparks.one_shot = true
	sparks.amount = int(8 * size)
	sparks.lifetime = 0.25
	sparks.explosiveness = 0.9
	sparks.fixed_fps = 30
	sparks.emitting = true
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.ZERO
	proc.spread = 180.0
	proc.initial_velocity_min = 15.0 * size
	proc.initial_velocity_max = 30.0 * size
	proc.gravity = Vector3.ZERO
	proc.scale_min = 0.05
	proc.scale_max = 0.12
	proc.damping_min = 10.0
	proc.damping_max = 20.0

	var gradient := Gradient.new()
	gradient.set_color(0, col)
	gradient.set_color(1, Color(col, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	proc.color_ramp = grad_tex

	sparks.process_material = proc

	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.06
	spark_mesh.height = 0.12
	spark_mesh.radial_segments = 4
	spark_mesh.rings = 2
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.emission_enabled = true
	spark_mat.emission = col
	spark_mat.emission_energy_multiplier = 4.0
	spark_mesh.material = spark_mat
	sparks.draw_pass_1 = spark_mesh

	container.add_child(sparks)

	# Self-cleanup
	var timer := container.get_tree().create_timer(0.5)
	timer.timeout.connect(container.queue_free)


## A shield taking a hit: a brief glowing shell around the ship that fades
## as it swells, plus a small flash where the shot met it.
static func spawn_shield_ripple(parent: Node3D, center: Vector3, radius: float, contact: Vector3, col: Color = Color(0.35, 0.85, 1.0)) -> void:
	var shell := MeshInstance3D.new()
	shell.name = "ShieldRippleFX"
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/shield_ripple.gdshader")
	mat.set_shader_parameter("tint", col)
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("contact_dir", (contact - center).normalized() if contact.distance_to(center) > 0.01 else Vector3.FORWARD)
	sphere.material = mat
	shell.mesh = sphere
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shell)
	shell.global_position = center
	var tween := shell.create_tween()
	tween.tween_property(shell, "scale", Vector3.ONE * 1.08, 0.35).from(Vector3.ONE * 0.94)
	tween.parallel().tween_method(func(v: float) -> void: mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.35)
	tween.tween_callback(shell.queue_free)
	spawn_hit(parent, contact, col, 0.7)


static func spawn_explosion(parent: Node3D, pos: Vector3, col: Color, size: float = 1.0) -> void:
	var container := Node3D.new()
	container.name = "ExplosionFX"
	parent.add_child(container)
	container.global_position = pos

	# Large billboard flash with radial gradient
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(8.0, 8.0) * size
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.albedo_color = Color(1.0, 0.95, 0.8)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.95, 0.8)
	flash_mat.emission_energy_multiplier = 10.0
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_mat.no_depth_test = true
	var grad := Gradient.new()
	grad.set_color(0, Color.WHITE)
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.set_offset(0, 0.0)
	grad.set_offset(1, 1.0)
	var flash_tex := GradientTexture2D.new()
	flash_tex.gradient = grad
	flash_tex.fill = GradientTexture2D.FILL_RADIAL
	flash_tex.fill_from = Vector2(0.5, 0.5)
	flash_tex.fill_to = Vector2(0.5, 0.0)
	flash_tex.width = 64
	flash_tex.height = 64
	flash_mat.albedo_texture = flash_tex
	quad.material = flash_mat
	flash.mesh = quad
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	container.add_child(flash)

	var tween := container.create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE * 1.5 * size, 0.3)
	tween.parallel().tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.3)
	tween.parallel().tween_property(flash_mat, "albedo_color:a", 0.0, 0.35)
	tween.tween_callback(flash.hide)

	# Debris particles
	var debris := GPUParticles3D.new()
	debris.one_shot = true
	debris.amount = 22
	debris.lifetime = 0.8
	debris.explosiveness = 0.85
	debris.fixed_fps = 30
	debris.emitting = true
	debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.ZERO
	proc.spread = 180.0
	proc.initial_velocity_min = 10.0 * size
	proc.initial_velocity_max = 25.0 * size
	proc.gravity = Vector3.ZERO
	proc.scale_min = 0.08 * size
	proc.scale_max = 0.25 * size
	proc.damping_min = 3.0
	proc.damping_max = 8.0

	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color.WHITE)
	gradient.add_point(0.25, col)
	gradient.add_point(0.6, Color(1.0, 0.4, 0.1))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(0.3, 0.15, 0.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	proc.color_ramp = grad_tex

	debris.process_material = proc

	var debris_mesh := SphereMesh.new()
	debris_mesh.radius = 0.08
	debris_mesh.height = 0.16
	debris_mesh.radial_segments = 4
	debris_mesh.rings = 2
	var debris_mat := StandardMaterial3D.new()
	debris_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debris_mat.emission_enabled = true
	debris_mat.emission = col
	debris_mat.emission_energy_multiplier = 5.0
	debris_mesh.material = debris_mat
	debris.draw_pass_1 = debris_mesh

	container.add_child(debris)

	# Secondary glow particles (fireball)
	var glow := GPUParticles3D.new()
	glow.one_shot = true
	glow.amount = 5
	glow.lifetime = 0.5
	glow.explosiveness = 0.8
	glow.fixed_fps = 30
	glow.emitting = true
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var glow_proc := ParticleProcessMaterial.new()
	glow_proc.direction = Vector3.ZERO
	glow_proc.spread = 180.0
	glow_proc.initial_velocity_min = 3.0 * size
	glow_proc.initial_velocity_max = 8.0 * size
	glow_proc.gravity = Vector3.ZERO
	glow_proc.scale_min = 0.5 * size
	glow_proc.scale_max = 1.5 * size
	glow_proc.damping_min = 8.0
	glow_proc.damping_max = 15.0

	var glow_gradient := Gradient.new()
	glow_gradient.set_color(0, Color(1.0, 0.7, 0.3, 0.6))
	glow_gradient.set_color(1, Color(1.0, 0.3, 0.0, 0.0))
	var glow_grad_tex := GradientTexture1D.new()
	glow_grad_tex.gradient = glow_gradient
	glow_proc.color_ramp = glow_grad_tex

	glow.process_material = glow_proc

	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.15
	glow_mesh.height = 0.3
	glow_mesh.radial_segments = 6
	glow_mesh.rings = 3
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.5)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.5, 0.1)
	glow_mat.emission_energy_multiplier = 6.0
	glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_mesh.material = glow_mat
	glow.draw_pass_1 = glow_mesh

	container.add_child(glow)

	# Ship-sized blasts get the full beat: a light that lights nearby hulls, a
	# shockwave ring, tumbling hull chunks and smoke that lingers.
	var cleanup := 1.5
	if size >= 0.8:
		_add_blast_light(container, col, size)
		_add_shockwave(container, size)
		_add_hull_chunks(container, col, size)
		_add_smoke(container, size)
		cleanup = 3.2

	# Self-cleanup
	var timer := container.get_tree().create_timer(cleanup)
	timer.timeout.connect(container.queue_free)


static func _add_blast_light(container: Node3D, col: Color, size: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = col.lerp(Color.WHITE, 0.3)
	light.light_energy = 10.0
	light.omni_range = 45.0 * size
	light.shadow_enabled = false
	container.add_child(light)
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.5).set_ease(Tween.EASE_OUT)


static func _add_shockwave(container: Node3D, size: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.75, 0.9, 1.0, 0.8)
	torus.material = mat
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A random tilt so every blast's ring reads differently.
	ring.rotation = Vector3(randf_range(-0.6, 0.6), randf_range(0.0, TAU), randf_range(-0.6, 0.6))
	container.add_child(ring)
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3(14.0, 1.0, 14.0) * size, 0.55).from(Vector3(0.5, 1.0, 0.5)).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.55)


static func _add_hull_chunks(container: Node3D, col: Color, size: float) -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.23, 0.25)
	metal.metallic = 0.7
	metal.roughness = 0.5
	metal.emission_enabled = true
	metal.emission = col
	metal.emission_energy_multiplier = 1.2  # hot edges that cool as they fly
	for i in 8:
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(randf_range(0.3, 1.2), randf_range(0.15, 0.5), randf_range(0.3, 1.0)) * size
		box.material = metal
		chunk.mesh = box
		container.add_child(chunk)
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)).normalized()
		var travel := dir * randf_range(8.0, 18.0) * size
		var spin := Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		var tween := chunk.create_tween()
		tween.tween_property(chunk, "position", travel, 2.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.parallel().tween_property(chunk, "rotation", spin, 2.8)
		tween.parallel().tween_property(chunk, "scale", Vector3.ZERO, 0.6).set_delay(2.2)
	var cool := container.create_tween()
	cool.tween_property(metal, "emission_energy_multiplier", 0.0, 1.5)


static func _add_smoke(container: Node3D, size: float) -> void:
	var smoke := GPUParticles3D.new()
	smoke.one_shot = true
	smoke.amount = 14
	smoke.lifetime = 2.6
	smoke.explosiveness = 0.85
	smoke.fixed_fps = 30
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.ZERO
	proc.spread = 180.0
	proc.initial_velocity_min = 1.5 * size
	proc.initial_velocity_max = 4.0 * size
	proc.gravity = Vector3.ZERO
	proc.damping_min = 0.5
	proc.damping_max = 1.2
	proc.scale_min = 1.5 * size
	proc.scale_max = 3.0 * size
	var fade := Gradient.new()
	fade.set_color(0, Color(0.35, 0.33, 0.32, 0.55))
	fade.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	proc.color_ramp = ramp
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	proc.scale_curve = grow_tex
	smoke.process_material = proc
	var puff := QuadMesh.new()
	puff.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var soft := Gradient.new()
	soft.set_color(0, Color.WHITE)
	soft.set_color(1, Color(1, 1, 1, 0))
	var soft_tex := GradientTexture2D.new()
	soft_tex.gradient = soft
	soft_tex.fill = GradientTexture2D.FILL_RADIAL
	soft_tex.fill_from = Vector2(0.5, 0.5)
	soft_tex.fill_to = Vector2(0.5, 0.0)
	mat.albedo_texture = soft_tex
	puff.material = mat
	smoke.draw_pass_1 = puff
	smoke.emitting = true
	container.add_child(smoke)
