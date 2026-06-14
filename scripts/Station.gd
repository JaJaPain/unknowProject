extends StaticBody3D

@export var display_name: String = ""
@export var world_id: String = ""
@export var station_type: String = "full_service"  # "full_service" or "outpost"
@export var model_path: String = ""                # GLB path, e.g. "res://assets/space_station1.glb"
@export var model_instance_scale: float = 1.0      # Extra scale applied to the GLB model itself
@export var minimum_docking_distance: float = 100.0

@onready var ring: MeshInstance3D = $Ring

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
	
	# Gentle slow rotation for outposts (GLB models)
	if model_path != "":
		rotate_y(0.025 * delta)

func get_docking_position(approach_position: Vector3) -> Vector3:
	var away_from_station := approach_position - global_position
	if away_from_station.length_squared() < 0.001:
		away_from_station = global_transform.basis.z
	return global_position + away_from_station.normalized() * get_docking_distance()

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
	var ui = GlobalState.get_ui_manager()
	if ui and ui.has_method("toggle_dock_menu"):
		ui.toggle_dock_menu(self)
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("save_game"):
		game_root.call_deferred("save_game")
