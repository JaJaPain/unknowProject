extends Node3D
## Windowed preview: builds one ship per Vanguard role, renders each to PNG.
## Run: Godot --path . tools/assembler_preview/preview.tscn -- <out_dir>

const ROLES := ["Interceptor", "Gunner", "Logistics", "MiningHauler"]

func _ready() -> void:
	var out_dir := "user://assembler_preview"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	DisplayServer.window_set_size(Vector2i(1100, 1100))
	var cam: Camera3D = $Camera3D
	await get_tree().process_frame
	var views := {
		"hero": Vector3(0.62, 0.42, 0.66),
		"side": Vector3(1.0, 0.08, 0.05),
		"top": Vector3(0.05, 1.0, 0.05),
	}

	var idx := 0
	for role in ROLES:
		# Clear previous ship
		for c in $ShipHolder.get_children():
			c.queue_free()
		await get_tree().process_frame

		var ship := ShipAssembler.build("vanguard", role, 1000 + idx)
		if ship == null:
			push_error("build failed for %s" % role)
			idx += 1
			continue
		$ShipHolder.add_child(ship)

		# Frame the ship: fit camera to its AABB
		var mcount := [0]
		var aabb := _aabb(ship, mcount)
		var size: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		if size < 0.01:
			size = 30.0
		var center: Vector3 = aabb.position + aabb.size * 0.5
		var dist: float = maxf(size * 1.0, 5.0)
		print("  ", role, " meshes=", mcount[0], " aabb_size=", aabb.size)

		for view_name in views:
			var up := Vector3.UP if view_name != "top" else Vector3(0, 0, -1)
			cam.position = center + (views[view_name] as Vector3).normalized() * dist
			cam.look_at(center, up)
			for i in range(5):
				await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := "%s/%d_%s_%s.png" % [out_dir, idx, role, view_name]
			img.save_png(path)
		print("SAVED ", role, " parts=", ship.get_child_count())
		idx += 1

	print("PREVIEW_DONE ", ProjectSettings.globalize_path(out_dir))
	get_tree().quit()


func _aabb(node: Node3D, mcount: Array = []) -> AABB:
	var meshes: Array = []
	_collect(node, meshes)
	if mcount.size() > 0:
		mcount[0] = meshes.size()
	var combined := AABB()
	var first := true
	for mi in meshes:
		var rel: Transform3D = node.global_transform.affine_inverse() * mi.global_transform
		var box: AABB = rel * mi.get_aabb()
		if first:
			combined = box
			first = false
		else:
			combined = combined.merge(box)
	return combined


func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
