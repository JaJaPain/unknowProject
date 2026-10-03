extends StaticBody3D

## Test-only adapter for the authored stations. Does not replace Station.gd.
const Lights := preload("res://scripts/visuals/StationLights.gd")
var display_name := ""
var world_id := ""
var station_type := "full_service"
var model_path := ""
var rpm := 1.0
var berths: Array[Node3D] = []
var reservations: Dictionary = {}
var rotor: Node3D
var player_berth: Node3D
var completed_docks := 0

func _ready() -> void:
	add_to_group("station")
	add_to_group(WorldIdentity.IDENTITY_GROUP)
	GlobalState.active_system_entities.append(self)
	# Load the review GLB directly: no Blender auto-import or source modification.
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(model_path, state)
	if error != OK:
		push_error("Harbor model failed to load: %s (%s)" % [model_path, error])
		return
	var model := document.generate_scene(state)
	add_child(model)
	rotor = model.find_child("Habitat_Rotor", true, false) as Node3D
	for node in model.find_children("Dock_*", "Node3D", true, false):
		berths.append(node as Node3D)
	berths.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	# Keep every pier fixed; only the rotor turns. Avoid two animation drivers.
	for animation in model.find_children("*", "AnimationPlayer", true, false):
		(animation as AnimationPlayer).stop()
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).create_trimesh_collision()
		for body in mesh.get_children():
			if body is StaticBody3D:
				body.collision_layer = 4
				body.collision_mask = 3
	# The top tier gives a clear vertical approach even on the three-tier tower.
	player_berth = berths[berths.size() - 2] if not berths.is_empty() else null
	Lights.attach(self)
	# Keep the amber beacon beside the berth, outside the ship's parking volume.
	var lights := get_node_or_null("StationLights")
	if lights != null and player_berth != null:
		for beacon in lights._beacons:
			# These kilometer-scale hulls need ship-size drones at close range.
			beacon.drone.scale = Vector3.ONE * 0.2
			if beacon.kind == "berth":
				var radial := player_berth.position
				radial.y = 0.0
				beacon.base += Vector3.UP * 70.0 + radial.normalized() * 120.0
				beacon.drone.position = beacon.base
		lights._berth_light.omni_range = 120.0
		lights._berth_light.light_energy = 0.7
	GlobalState.entities_changed.emit()

func _physics_process(delta: float) -> void:
	if is_instance_valid(rotor) and not GlobalState.paused:
		rotor.rotate_y(TAU * rpm / 60.0 * delta)

func berth_position(berth: Node3D) -> Vector3:
	return berth.global_position + berth.global_basis.x.normalized() * 25.0

func approach_position(berth: Node3D) -> Vector3:
	return berth_position(berth) + Vector3.UP * 180.0

func berth_basis(berth: Node3D) -> Basis:
	var radial := berth.global_position - global_position
	radial.y = 0.0
	return Basis.looking_at(radial.normalized(), Vector3.UP)

func get_docking_position(_approach: Vector3) -> Vector3:
	return berth_position(player_berth) if player_berth != null else global_position

func get_docking_distance() -> float:
	return global_position.distance_to(get_docking_position(global_position))

func begin_dock_tractor(ship: Node3D) -> void:
	get_tree().current_scene.begin_player_docking(self, ship)

func dock_player() -> void:
	begin_dock_tractor(GlobalState.player)

func _exit_tree() -> void:
	GlobalState.active_system_entities.erase(self)
