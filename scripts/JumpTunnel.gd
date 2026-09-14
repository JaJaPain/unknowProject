extends Node3D

@onready var tunnel_cylinder: MeshInstance3D = $TunnelCylinder
@onready var warp_particles: CPUParticles3D = $WarpParticles
@onready var engine_light: OmniLight3D = $EngineGlowLight

var _time_passed := 0.0
var _player_visual: Node3D = null
var _player_camera: Camera3D = null
var _camera_pivot: Node3D = null
var _original_fov := 70.0
var _original_visual_transform: Transform3D
var _original_pivot_rotation := Vector3.ZERO
var _fov_burst := 0.0  # extra FOV added during the final exit acceleration

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Give this tunnel instance its own material copy so the exit-burst speed ramp
	# doesn't bake into the shared scene sub-resource and bleed into the next jump.
	var mat := tunnel_cylinder.get_active_material(0)
	if mat:
		tunnel_cylinder.material_override = mat.duplicate()

	# TEMP: hide the blue tunnel cylinder to check whether it's the source of the
	# off-axis "flung out the side" look. Remove this line to bring the bore back.
	tunnel_cylinder.visible = false

func setup_real_ship(player: CharacterBody3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not player:
		return
	
	_player_visual = player.get_node_or_null("Visual")
	if _player_visual:
		_original_visual_transform = _player_visual.transform
		
	_player_camera = player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if _player_camera:
		_original_fov = _player_camera.fov

	# Aim the chase camera straight down the tunnel bore (no -15 gameplay pitch)
	# so the ship sits dead-center and we look toward the vanishing point.
	_camera_pivot = player.get_node_or_null("CameraPivot")
	if _camera_pivot:
		_original_pivot_rotation = _camera_pivot.rotation
		_camera_pivot.rotation = Vector3.ZERO

	# Position the engine light near the back of the ship (ship faces -Z, engines are at +Z)
	engine_light.position = Vector3(0, 0, 4.7)

func cleanup() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Stop _process immediately so it can no longer write the (widened) tunnel
	# FOV/offsets after this point — otherwise it races GameRoot's FOV reset and
	# leaves the camera stuck wide (fisheye) after the jump.
	set_process(false)
	# Restore the original visual transform
	if _player_visual and is_instance_valid(_player_visual):
		_player_visual.transform = _original_visual_transform
	# Restore camera offsets. NOTE: we deliberately do NOT restore fov here —
	# _original_fov was captured after the entry FOV-widen (~94, not the true
	# gameplay default), so GameRoot owns the authoritative fov reset.
	if _player_camera and is_instance_valid(_player_camera):
		_player_camera.h_offset = 0.0
		_player_camera.v_offset = 0.0
	# Restore the gameplay chase-cam pitch
	if _camera_pivot and is_instance_valid(_camera_pivot):
		_camera_pivot.rotation = _original_pivot_rotation

func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	_time_passed += delta

	# Rotate the tunnel mesh for a slow vortex swirl (the sense of speed comes from
	# the shader scroll + warp particles, not from moving the ship).
	tunnel_cylinder.rotate_y(delta * 0.18)

	# Keep the ship locked dead-center in the bore. Only a whisper of bank so it
	# reads as alive without any of the old turbulence/drift that flung it sideways.
	if _player_visual and is_instance_valid(_player_visual):
		var roll := sin(_time_passed * 0.8) * 0.02
		_player_visual.position = Vector3.ZERO
		_player_visual.rotation = Vector3(0.0, 0.0, roll)

	# Camera stays rock-steady aimed down the bore — no random jitter. A gentle,
	# smooth FOV breathe keeps it cinematic instead of static.
	if _camera_pivot and is_instance_valid(_camera_pivot):
		_camera_pivot.rotation = Vector3.ZERO
	if _player_camera and is_instance_valid(_player_camera):
		_player_camera.h_offset = 0.0
		_player_camera.v_offset = 0.0
		_player_camera.fov = _original_fov + sin(_time_passed * 1.6) * 1.2 + _fov_burst

	# Pulse engine light intensity
	engine_light.light_energy = 8.0 + sin(_time_passed * 25.0) * 2.5


# Final acceleration "punch" out the end of the tunnel, called just before the
# whiteout so the jump reads as exiting the bore rather than fading mid-flight.
func begin_exit_burst(duration: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mat := tunnel_cylinder.get_active_material(0) as ShaderMaterial
	if mat:
		var cur_speed: float = mat.get_shader_parameter("speed")
		var cur_ring: float = mat.get_shader_parameter("ring_speed")
		var burst := create_tween().set_parallel(true)
		burst.tween_method(
			func(v): mat.set_shader_parameter("speed", v),
			cur_speed, cur_speed * 3.5, duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		burst.tween_method(
			func(v): mat.set_shader_parameter("ring_speed", v),
			cur_ring, cur_ring * 2.5, duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# FOV widens as we accelerate, sold through the per-frame fov in _process
	create_tween().tween_method(
		func(v): _fov_burst = v,
		0.0, 18.0, duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
