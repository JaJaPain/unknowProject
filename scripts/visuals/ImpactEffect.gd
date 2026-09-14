class_name ImpactEffect
extends RefCounted


static func spawn_hit(parent: Node3D, pos: Vector3, col: Color) -> void:
	var container := Node3D.new()
	container.name = "HitFX"
	parent.add_child(container)
	container.global_position = pos

	# Billboard flash with radial gradient
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.5, 2.5)
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
	sparks.amount = 8
	sparks.lifetime = 0.25
	sparks.explosiveness = 0.9
	sparks.fixed_fps = 30
	sparks.emitting = true
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.ZERO
	proc.spread = 180.0
	proc.initial_velocity_min = 15.0
	proc.initial_velocity_max = 30.0
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

	# Self-cleanup
	var timer := container.get_tree().create_timer(1.5)
	timer.timeout.connect(container.queue_free)
