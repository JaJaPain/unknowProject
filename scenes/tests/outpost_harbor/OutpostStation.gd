extends StaticBody3D

## Test-only adapter for the authored stations. Does not replace Station.gd.
const Lights := preload("res://scripts/visuals/StationLights.gd")
var display_name := ""
var world_id := ""
var station_type := "outpost"
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
	rotor = model.find_child("Radar_Rotor", true, false) as Node3D
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
	var lights := get_node_or_null("StationLights")
	if lights != null:
		var lane_index := 0
		for beacon in lights._beacons:
			beacon.drone.scale = Vector3.ONE * 0.15
			if beacon.kind == "berth":
				beacon.base = to_local(berth_position()).lerp(to_local(lane_entry_position()), (lane_index + 0.5) / 4.0) + Vector3(18, 0, 0)
				lane_index += 1
				beacon.drone.position = beacon.base
		lights._berth_light.position = to_local(berth_position(player_berth))
	GlobalState.entities_changed.emit()

func _physics_process(delta: float) -> void:
	if is_instance_valid(rotor) and not GlobalState.paused:
		rotor.rotate_y(TAU * rpm / 60.0 * delta)

func berth_position(berth: Node3D = null) -> Vector3:
	if berth == null: berth = player_berth
	return berth.global_position + berth.global_basis.x.normalized() * 16.0

func approach_position(berth: Node3D) -> Vector3:
	# Intersect the marker's outward ray with the approach sphere.
	var point := berth_position(berth) - global_position
	var direction := berth.global_basis.x.normalized()
	var projection := point.dot(direction)
	var radius := approach_sphere_radius()
	var distance := -projection + sqrt(maxf(0.0, projection * projection + radius * radius - point.length_squared()))
	return global_position + point + direction * distance

func berth_basis(berth: Node3D = null) -> Basis:
	if berth == null: berth = player_berth
	var radial := berth.global_position - global_position
	radial.y = 0.0
	return Basis.looking_at(radial.normalized(), Vector3.UP)

func get_docking_position(_approach: Vector3) -> Vector3:
	return lane_entry_position() if player_berth != null else global_position

func get_docking_distance() -> float:
	return global_position.distance_to(get_docking_position(global_position))

func begin_dock_tractor(ship: Node3D) -> void:
	get_tree().current_scene.begin_player_docking(self, ship)

func dock_player() -> void:
	begin_dock_tractor(GlobalState.player)

func _exit_tree() -> void:
	GlobalState.active_system_entities.erase(self)

# Same public navigation hooks as scripts/Station.gd. Kept test-local.
func approach_sphere_radius() -> float:
	return 155.0

func autopilot_radius() -> float:
	return approach_sphere_radius() - 55.0 - 20.0

func lane_entry_position() -> Vector3:
	return approach_position(player_berth)

func beam_origin() -> Node3D:
	return player_berth

func is_berthed() -> bool:
	return is_instance_valid(player_berth)
