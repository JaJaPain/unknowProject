extends StaticBody3D

@export var display_name: String = ""
@export var world_id: String = ""
@export var station_type: String = "full_service"  # "full_service" or "outpost"
@export var model_path: String = ""                # GLB path, e.g. "res://assets/space_station1.glb"
@export var model_instance_scale: float = 1.0      # Extra scale applied to the GLB model itself
@export var minimum_docking_distance: float = 100.0

@onready var ring: MeshInstance3D = $Ring

# --- Kilometre-scale main stations (Abe, 2026-10-04) ---------------------------
# Models with authored berths (`Dock_*` nodes; assets/stations/, ChatGPT's
# Cinder Anchorage and Meridian Exchange and their liveries). The habitat
# rotor turns; the piers stay still. Collision is a box per section, not the
# full mesh.
#
# Abe's approach sphere: an invisible sphere around the station. Docking: the
# autopilot flies to the point on the sphere in line with the player's berth,
# the berth's tractor beam takes the ship there and pulls it in. Undocking:
# the beam pushes it back out to the sphere. The autopilot avoids the sphere,
# not the hull (autopilot_radius()).
var berths: Array[Node3D] = []
var player_berth: Node3D = null
var rotor: Node3D = null
## Habitat rotor turns per minute.
@export var rotor_rpm := 1.0
## The approach sphere's gap beyond the hull's farthest point.
const LANE_CLEARANCE := 150.0
## The autopilot's own margin for stations (PlayerShip): its avoidance
## envelope ends just inside the sphere, so a docking point on the sphere is
## outside it and the route still goes around the station.
const AUTOPILOT_STATION_MARGIN := 55.0
## How far out from its pier a berthed ship sits.
const BERTH_STANDOFF := 25.0
# --- Outposts (Abe, 2026-10-04): ChatGPT's Kestrel Depot and Crown Haven, built
# the same way (Dock_* markers, a turning Radar_Rotor) at outpost size. Their
# berths face along the marker's +X, which isn't always away from the centre
# (Crown Haven's pads face up), so the lane runs along the marker. Their meshes
# are joined by material, so a box per mesh would fill the open docking bays:
# they collide as the real mesh. Numbers from ChatGPT's harbor test.
const OUTPOST_BERTH_STANDOFF := 16.0
const OUTPOST_LANE_CLEARANCE := 60.0
## Outpost light drones, as a share of the main-station size.
const OUTPOST_LIGHT_SCALE := 0.15
var _outpost_berths := false
var _hull_radius := 0.0
var _hull_boxes: Array[AABB] = []

func _ready():
	add_to_group("station")
	add_to_group(WorldIdentity.IDENTITY_GROUP)
	if world_id.is_empty():
		push_error("[Station] Missing explicit world ID for '%s'." % name)
	
	# Register in the global entity list so NPCs / overview can find us
	if not GlobalState.active_system_entities.has(self):
		GlobalState.active_system_entities.append(self)
	
	# If a GLB model path is set, load it and hide the default procedural mesh
	if model_path != "":
		var model_scene = load(model_path)
		if model_scene:
			var model_instance = model_scene.instantiate()
			model_instance.scale = Vector3.ONE * model_instance_scale
			add_child(model_instance)
			
			# Auto-center: compute the AABB of the loaded model and shift
			# it so the visual center sits at the node origin (otherwise
			# the targeting reticle ends up at the model's feet/bottom).
			_center_model(model_instance)
			_setup_berths(model_instance)
			
			# Hide the default procedural Core + Ring meshes
			var core_node = get_node_or_null("Core")
			var ring_node = get_node_or_null("Ring")
			if core_node:
				core_node.visible = false
			if ring_node:
				ring_node.visible = false
				ring = null  # Don't try to spin the hidden ring
			print("[Station] GLB model loaded: ", model_path, " for '", name, "' scale=", model_instance_scale)
		else:
			push_warning("[Station] Could not load GLB: %s — using default mesh" % model_path)
	
	# Running lights, fitted once the model is in place.
	(func(): load("res://scripts/visuals/StationLights.gd").attach(self)).call_deferred()
	# Emit so overview refreshes with this station included
	GlobalState.entities_changed.emit()

func _center_model(model_root: Node3D) -> void:
	# Walk all MeshInstance3D descendants and build a merged AABB
	# in model_root-local space using the FULL transform chain
	var meshes: Array[MeshInstance3D] = []
	_find_meshes(model_root, meshes)
	if meshes.is_empty():
		return
	
	var first := true
	var combined_aabb: AABB
	for mesh in meshes:
		# Get the full transform from mesh-local to model_root-local
		var rel_xform := _relative_transform_to(mesh, model_root)
		var transformed_aabb := rel_xform * mesh.get_aabb()
		if first:
			combined_aabb = transformed_aabb
			first = false
		else:
			combined_aabb = combined_aabb.merge(transformed_aabb)
	
	# Center of the merged AABB in model_root-local space (pre-scale)
	var center := combined_aabb.get_center()
	# Shift model so its visual center sits at Station's origin.
	# model_root.position is in Station-local space, center is in
	# model_root-local (pre-scale), so multiply by scale to convert.
	model_root.position -= center * model_instance_scale
	print("[Station] Auto-centered '", name, "': AABB center=", center, " size=", combined_aabb.size)

func _relative_transform_to(from_node: Node3D, to_ancestor: Node3D) -> Transform3D:
	## Returns the transform that maps from_node-local coords into to_ancestor-local coords,
	## walking the full chain of intermediate nodes (Skeleton3D, BoneAttachment, etc.).
	var xform := from_node.transform
	var node := from_node.get_parent()
	while node != to_ancestor and node != null:
		if node is Node3D:
			xform = (node as Node3D).transform * xform
		node = node.get_parent()
	return xform

func _find_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_find_meshes(child, out)

func _exit_tree():
	GlobalState.active_system_entities.erase(self)

func _physics_process(delta: float):
	if GlobalState.paused: return
	
	# Spin the station's outer ring (mirroring the Ursina behavior)
	if ring:
		ring.rotate_y(0.12 * delta)
	
	# Berthed main stations: only the habitat rotor turns (ships sit on the
	# piers). Everything else with a GLB model turns gently as before.
	if is_berthed():
		if is_instance_valid(rotor):
			rotor.rotate_y(TAU * rotor_rpm / 60.0 * delta)
	elif model_path != "":
		rotate_y(0.025 * delta)

func get_docking_position(approach_position: Vector3) -> Vector3:
	if is_berthed():
		return lane_entry_position()
	var away_from_station := approach_position - global_position
	if away_from_station.length_squared() < 0.001:
		away_from_station = global_transform.basis.z
	return global_position + away_from_station.normalized() * get_docking_distance()

func is_berthed() -> bool:
	return player_berth != null and is_instance_valid(player_berth)


## Find the berths, stop the model's own animation (the rotor turns in
## _physics_process instead), build the simplified collision. Only for models
## with authored berths.
func _setup_berths(model_root: Node3D) -> void:
	for node in model_root.find_children("Dock_*", "Node3D", true, false):
		berths.append(node as Node3D)
	if berths.is_empty():
		return
	berths.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	# The top tier: a clear approach on every model (the harbor test's choice).
	player_berth = berths[berths.size() - 2] if berths.size() >= 2 else berths[0]
	_outpost_berths = station_type == "outpost"
	rotor = model_root.find_child("Habitat_Rotor", true, false) as Node3D
	if rotor == null:
		rotor = model_root.find_child("Radar_Rotor", true, false) as Node3D
	for animation in model_root.find_children("*", "AnimationPlayer", true, false):
		(animation as AnimationPlayer).stop()
	# These models are built at their real size: the station node isn't scaled.
	scale = Vector3.ONE
	# The small default collision box doesn't fit; one box per section does.
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	var meshes: Array[MeshInstance3D] = []
	_find_meshes(model_root, meshes)
	for mesh in meshes:
		var box := _relative_transform_to(mesh, self) * mesh.get_aabb()
		if box.size.length() < 1.0:
			continue
		_hull_boxes.append(box)
		var holder := CollisionShape3D.new()
		holder.name = "HullBox_%s" % mesh.name
		if _outpost_berths and mesh.mesh != null:
			holder.shape = mesh.mesh.create_trimesh_shape()
			holder.transform = _relative_transform_to(mesh, self)
		else:
			var shape := BoxShape3D.new()
			shape.size = box.size
			holder.shape = shape
			holder.position = box.get_center()
		add_child(holder)
		for i in 8:
			_hull_radius = maxf(_hull_radius, box.get_endpoint(i).length())


## Where a ship sits in a berth (the player's by default), and how it faces.
func berth_position(berth: Node3D = null) -> Vector3:
	if berth == null:
		berth = player_berth
	var standoff := OUTPOST_BERTH_STANDOFF if _outpost_berths else BERTH_STANDOFF
	return berth.global_position + berth.global_basis.x.normalized() * standoff


## The berths traffic uses: every berth but the player's (Abe, 2026-10-05:
## freighters stop sharing the player's berth).
func traffic_berths() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for b in berths:
		if b != player_berth and is_instance_valid(b):
			out.append(b)
	return out


## Outposts are lit at this share of a main station's light size.
func light_scale() -> float:
	return OUTPOST_LIGHT_SCALE if _outpost_berths else 1.0


func berth_basis(berth: Node3D = null) -> Basis:
	if berth == null:
		berth = player_berth
	var radial := berth.global_position - global_position
	radial.y = 0.0
	return Basis.looking_at(radial.normalized(), Vector3.UP)


## The approach sphere's radius (around the station's centre).
func approach_sphere_radius() -> float:
	return _hull_radius + (OUTPOST_LANE_CLEARANCE if _outpost_berths else LANE_CLEARANCE)


## How big the autopilot should treat this station: the sphere, less its own
## station margin and a little, so its envelope stays inside the sphere.
func autopilot_radius() -> float:
	return approach_sphere_radius() - AUTOPILOT_STATION_MARGIN - 20.0


## Where docking starts and undocking ends: the point on the approach sphere
## straight out from the berth. The autopilot flies here; the beam does the
## rest along the line to the berth.
func lane_entry_position(berth: Node3D = null) -> Vector3:
	# The player's main-station berth keeps its radial lane (unchanged); every
	# outpost berth, and every traffic berth, runs along its own marker's +X.
	var along_marker := _outpost_berths or (berth != null and berth != player_berth)
	if berth == null:
		berth = player_berth
	if along_marker:
		# Where the berth's lane meets the sphere. Outposts: along the marker's
		# +X. A main station's traffic berths: straight down onto the pier from
		# above, as ChatGPT's station harbor test brings ships in (its tested
		# clear corridors; the marker's +X there runs along the arm).
		var from := berth_position(berth) - global_position
		var dir := berth.global_basis.x.normalized()
		if not _outpost_berths:
			# The piers sit inside the turning habitat ring: a lane straight out
			# from the centre would pass through it (seen in the traffic
			# snapshot). Down from above clears it, as in ChatGPT's harbor test.
			# (The coarse hull box over the ring covers its open middle, so a
			# ray test calls this lane blocked; the snapshot shows it clear.)
			dir = global_basis.y.normalized()
		var along := from.dot(dir)
		var r := approach_sphere_radius()
		var t := -along + sqrt(maxf(0.0, along * along + r * r - from.length_squared()))
		return global_position + from + dir * t
	var out := player_berth.global_position - global_position
	if out.length_squared() < 1.0:
		out = global_basis.x
	return global_position + out.normalized() * approach_sphere_radius()


## The node the tractor beam comes from: the berth on a berthed station.
func beam_origin(berth: Node3D = null) -> Node3D:
	if berth != null:
		return berth
	return player_berth if is_berthed() else self


## How far `from` is from the hull (the section boxes), not the centre. For
## other stations: the centre distance, as before.
func surface_distance(from: Vector3) -> float:
	if _hull_boxes.is_empty():
		return from.distance_to(global_position)
	var local := to_local(from)
	var best := INF
	for box in _hull_boxes:
		var nearest := Vector3(clampf(local.x, box.position.x, box.end.x), clampf(local.y, box.position.y, box.end.y), clampf(local.z, box.position.z, box.end.z))
		best = minf(best, local.distance_to(nearest))
	return best


func get_world_id() -> String:
	return world_id

func get_world_type_id() -> String:
	return "entity_type.station"

func get_docking_distance() -> float:
	var collision := find_child("CollisionShape3D", true, false) as CollisionShape3D
	if collision and collision.shape is BoxShape3D:
		var box := collision.shape as BoxShape3D
		var world_scale := collision.global_transform.basis.get_scale().abs()
		var half_extents := box.size * 0.5 * world_scale
		var horizontal_radius := Vector2(half_extents.x, half_extents.z).length()
		return max(minimum_docking_distance, horizontal_radius + 16.0)
	return minimum_docking_distance

func dock_player():
	# Refuse to dock mid-fight: an autopilot dock (e.g. the completed-mission
	# "Dock at Station" button) can carry the ship to a station while combat starts
	# en route, leaving the dock panel open over the combat wheel. Bail if a combat
	# window is active — the player must clear hostiles first.
	if PlayerInteractionQueue.in_combat_window():
		var busy_ui = GlobalState.get_ui_manager()
		if busy_ui and busy_ui.has_method("show_hud_warning"):
			busy_ui.show_hud_warning("Can't dock while under fire — clear the hostiles first.")
		return
	var ui = GlobalState.get_ui_manager()
	if ui and ui.has_method("toggle_dock_menu"):
		ui.toggle_dock_menu(self)


func begin_dock_tractor(ship: Node3D) -> void:
	if PlayerInteractionQueue.in_combat_window():
		var busy_ui = GlobalState.get_ui_manager()
		if busy_ui and busy_ui.has_method("show_hud_warning"):
			busy_ui.show_hud_warning("Can't dock while under fire — clear the hostiles first.")
		return
	var ui = GlobalState.get_ui_manager()
	if ui and ui.has_method("begin_docking_procedure"):
		ui.begin_docking_procedure(self, ship)
		return
	dock_player()
