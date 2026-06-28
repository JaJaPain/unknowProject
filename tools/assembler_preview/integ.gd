extends Node3D
## Integration check: spawn REAL NPCShip instances as Vanguard, screenshot each.
## Run: Godot --path . tools/assembler_preview/integ.tscn -- <out_dir>

const ROLES := ["Interceptor", "Gunner", "Logistics", "MiningHauler"]
const NPC_SCENE := "res://scenes/npc_ship.tscn"

func _ready() -> void:
	var out_dir := "user://assembler_integ"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	DisplayServer.window_set_size(Vector2i(1100, 1100))
	var cam: Camera3D = $Camera3D
	var packed := load(NPC_SCENE) as PackedScene
	await get_tree().process_frame

	var idx := 0
	for role in ROLES:
		for c in $ShipHolder.get_children():
			c.queue_free()
		await get_tree().process_frame

		var ship := packed.instantiate()
		ship.set("faction", "vanguard")
		ship.set("ship_role", role)
		$ShipHolder.add_child(ship)
		# Let _ready/_setup_hull build the kitbash hull, then settle physics.
		for i in range(8):
			await get_tree().process_frame
		ship.global_position = Vector3.ZERO

		var visual: Node3D = ship.get_node_or_null("Visual")
		var aabb := _aabb(visual if visual else ship)
		var size: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		if size < 0.01:
			size = 30.0
		var center: Vector3 = (visual.global_position if visual else ship.global_position) + Vector3(0, 0, 0)
		var dist: float = maxf(size * 1.05, 6.0)
		print("  ", role, " hull_size=", size, " hardpoints=", ship.get("hardpoints").size() if ship.get("hardpoints") else 0)

		for view_name in {"hero": Vector3(0.62, 0.42, 0.66), "side": Vector3(1, 0.07, 0.04)}:
			cam.position = center + (Vector3(0.62, 0.42, 0.66) if view_name == "hero" else Vector3(1, 0.07, 0.04)).normalized() * dist
			cam.look_at(center, Vector3.UP)
			for i in range(5):
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%d_%s_%s.png" % [out_dir, idx, role, view_name])
		print("SAVED ", role)
		idx += 1

	print("INTEG_DONE")
	get_tree().quit()


func _aabb(node: Node3D) -> AABB:
	var meshes: Array = []
	_collect(node, meshes)
	var combined := AABB()
	var first := true
	for mi in meshes:
		var rel: Transform3D = node.global_transform.affine_inverse() * mi.global_transform
		var box: AABB = rel * mi.get_aabb()
		if first:
			combined = box; first = false
		else:
			combined = combined.merge(box)
	return combined

func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
