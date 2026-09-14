extends StaticBody3D

var being_salvaged: bool = false
var last_attacker_faction: String = ""  # Set by NPCShip.die() so salvager knows if player killed this

func initialize(original_hull: Node3D):
	if original_hull:
		var duplicate_hull = original_hull.duplicate()
		_apply_wrecked_material(duplicate_hull)
		add_child(duplicate_hull)
		
		# Align with local coordinates
		duplicate_hull.position = Vector3.ZERO
		duplicate_hull.rotation = Vector3.ZERO
		duplicate_hull.scale = original_hull.scale
		
	# Add a collision shape dynamically so the wreckage is targetable
	var col_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 4.0
	col_shape.shape = sphere
	add_child(col_shape)

func _apply_wrecked_material(node: Node):
	if node is MultiMeshInstance3D:
		node.queue_free()
		return
	if node is Light3D:
		node.queue_free()
		return
	if node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			node.set_surface_override_material(i, null)

		var new_mat = StandardMaterial3D.new()
		new_mat.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
		new_mat.roughness = 0.85
		new_mat.metallic = 0.6
		node.set_surface_override_material(0, new_mat)

	for child in node.get_children():
		_apply_wrecked_material(child)

func _physics_process(delta: float):
	if GlobalState.paused: return
	# Slow tumble in deep space
	rotate_y(0.04 * delta)
	rotate_x(0.02 * delta)

func _exit_tree():
	# Refresh overview list when wreckage is salvaged and removed
	GlobalState.entities_changed.emit()
