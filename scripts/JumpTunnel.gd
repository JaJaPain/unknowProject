extends Node3D

@onready var tunnel_cylinder: MeshInstance3D = $TunnelCylinder
@onready var ship_anchor: Node3D = $ShipAnchor
@onready var warp_camera: Camera3D = $WarpCamera
@onready var warp_particles: CPUParticles3D = $WarpParticles
@onready var engine_light: OmniLight3D = $EngineGlowLight

var _time_passed := 0.0
var _camera_shake_strength := 0.18
var _camera_shake_speed := 18.0
var _original_camera_pos := Vector3.ZERO
var _original_fov := 70.0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_original_camera_pos = warp_camera.transform.origin
	_original_fov = warp_camera.fov
	# Set current camera
	warp_camera.make_current()

func setup_ship_model(player_visual: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not player_visual:
		return
	var dup := player_visual.duplicate() as Node3D
	# Clear scripts from duplicated visual tree to prevent any running logic
	_clear_scripts(dup)
	
	# Add to ship anchor
	ship_anchor.add_child(dup)
	dup.position = Vector3.ZERO
	dup.rotation = Vector3.ZERO
	dup.visible = true
	
	# Position the engine light near the back of the ship (ship faces -Z, engines are at +Z)
	engine_light.position = Vector3(0, 0, 4.2)

func _clear_scripts(node: Node) -> void:
	node.set_script(null)
	for child in node.get_children():
		_clear_scripts(child)

func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
		
	_time_passed += delta
	
	# Rotate the tunnel mesh for vortex feel (local Y is longitudinal length after rotation)
	tunnel_cylinder.rotate_y(delta * 0.18)
	
	# Simulate ship flight wobble/turbulence
	# Gentle banking roll and yaw
	var roll = sin(_time_passed * 2.8) * 0.12
	var yaw = cos(_time_passed * 1.7) * 0.05
	var pitch = sin(_time_passed * 3.4) * 0.03
	ship_anchor.rotation = Vector3(pitch, yaw, roll)
	
	# Slight translation oscillation (drifting inside the tunnel)
	var drift_x = sin(_time_passed * 1.5) * 0.35
	var drift_y = cos(_time_passed * 2.1) * 0.2
	ship_anchor.position = Vector3(drift_x, drift_y, 0)
	
	# Camera vibration (shake)
	var shake_offset_x = randf_range(-_camera_shake_strength, _camera_shake_strength)
	var shake_offset_y = randf_range(-_camera_shake_strength, _camera_shake_strength)
	warp_camera.transform.origin = _original_camera_pos + Vector3(shake_offset_x, shake_offset_y, 0)
	
	# Camera FOV breathing
	warp_camera.fov = _original_fov + sin(_time_passed * 4.5) * 1.8
	
	# Pulse engine light intensity
	engine_light.light_energy = 8.0 + sin(_time_passed * 25.0) * 2.5
