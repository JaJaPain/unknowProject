extends Node3D

@onready var tunnel_cylinder: MeshInstance3D = $TunnelCylinder
@onready var warp_particles: CPUParticles3D = $WarpParticles
@onready var engine_light: OmniLight3D = $EngineGlowLight

var _time_passed := 0.0
var _camera_shake_strength := 0.18
var _player_visual: Node3D = null
var _player_camera: Camera3D = null
var _original_fov := 70.0
var _original_visual_transform: Transform3D

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return

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
		
	# Position the engine light near the back of the ship (ship faces -Z, engines are at +Z)
	engine_light.position = Vector3(0, 0, 4.7)

func cleanup() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Restore the original visual transform
	if _player_visual and is_instance_valid(_player_visual):
		_player_visual.transform = _original_visual_transform
	# Restore camera offsets
	if _player_camera and is_instance_valid(_player_camera):
		_player_camera.h_offset = 0.0
		_player_camera.v_offset = 0.0

func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	_time_passed += delta
	
	# Rotate the tunnel mesh for vortex feel
	tunnel_cylinder.rotate_y(delta * 0.18)
	
	# Simulate ship flight wobble/turbulence on the real visual node
	if _player_visual and is_instance_valid(_player_visual):
		var roll = sin(_time_passed * 2.8) * 0.12
		var yaw = cos(_time_passed * 1.7) * 0.05
		var pitch = sin(_time_passed * 3.4) * 0.03
		
		# Slight translation oscillation (drifting inside the tunnel)
		var drift_x = sin(_time_passed * 1.5) * 0.35
		var drift_y = cos(_time_passed * 2.1) * 0.2
		
		_player_visual.rotation = Vector3(pitch, yaw, roll)
		_player_visual.position = Vector3(drift_x, drift_y, 0)
		
	# Camera vibration (shake) and FOV breathing on the player's actual camera
	if _player_camera and is_instance_valid(_player_camera):
		_player_camera.h_offset = randf_range(-_camera_shake_strength, _camera_shake_strength)
		_player_camera.v_offset = randf_range(-_camera_shake_strength, _camera_shake_strength)
		_player_camera.fov = _original_fov + sin(_time_passed * 4.5) * 1.8
		
	# Pulse engine light intensity
	engine_light.light_energy = 8.0 + sin(_time_passed * 25.0) * 2.5
