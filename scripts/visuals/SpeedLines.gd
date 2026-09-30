extends Node3D

## Motion cues on the player camera. Two layers:
## - dust: faint specks left behind in world space, so any movement shows
##   parallax (empty space otherwise gives no sense of speed);
## - streaks: long thin lines rushing past the camera, only while boosting.
## PlayerShip sets `boosting` each frame; the streak layer fades in and out.

var boosting := false

var _dust: GPUParticles3D
var _streaks: GPUParticles3D
var _streak_mat: StandardMaterial3D
var _streak_alpha := 0.0


func _ready() -> void:
	_dust = _make_dust()
	add_child(_dust)
	_streaks = _make_streaks()
	add_child(_streaks)


func _process(delta: float) -> void:
	var target := 1.0 if boosting else 0.0
	_streak_alpha = move_toward(_streak_alpha, target, delta * (4.0 if boosting else 2.0))
	_streaks.emitting = _streak_alpha > 0.02
	_streak_mat.albedo_color.a = 0.45 * _streak_alpha


func _make_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "SpaceDust"
	p.amount = 160
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.local_coords = false  # left behind in the world, so motion reads as parallax
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(30, 18, 30)
	proc.gravity = Vector3.ZERO
	proc.initial_velocity_min = 0.0
	proc.initial_velocity_max = 0.2
	proc.scale_min = 0.5
	proc.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(0.8, 0.85, 0.9, 0.0))
	fade.add_point(0.2, Color(0.8, 0.85, 0.9, 0.35))
	fade.add_point(0.8, Color(0.8, 0.85, 0.9, 0.35))
	fade.set_color(fade.get_point_count() - 1, Color(0.8, 0.85, 0.9, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	proc.color_ramp = ramp
	p.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	p.draw_pass_1 = quad
	p.emitting = true
	return p


func _make_streaks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "BoostStreaks"
	p.amount = 70
	p.lifetime = 0.45
	p.local_coords = true  # fixed to the camera: they rush past the view
	p.fixed_fps = 60
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-20, -20, -80), Vector3(40, 40, 100))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	proc.emission_ring_axis = Vector3(0, 0, 1)
	proc.emission_ring_height = 2.0
	proc.emission_ring_radius = 16.0
	proc.emission_ring_inner_radius = 6.0
	proc.direction = Vector3(0, 0, 1)  # from ahead of the camera toward it
	proc.spread = 0.0
	proc.gravity = Vector3.ZERO
	proc.initial_velocity_min = 140.0
	proc.initial_velocity_max = 200.0
	proc.particle_flag_align_y = true
	p.process_material = proc
	p.position = Vector3(0, 0, -60)
	# A thin rod aligned to its velocity (align_y). Rushing at the camera from
	# off-axis, perspective turns each rod into a line radiating from the centre.
	var rod := BoxMesh.new()
	rod.size = Vector3(0.07, 7.0, 0.07)
	_streak_mat = StandardMaterial3D.new()
	_streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_streak_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_streak_mat.albedo_color = Color(0.75, 0.88, 1.0, 0.0)
	rod.material = _streak_mat
	p.draw_pass_1 = rod
	return p
