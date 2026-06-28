extends Node3D
## Render every hull (bare, gray) in a labeled grid so solid vs open/holed hulls
## are easy to spot. Run: Godot --path . tools/assembler_preview/hull_sheet.tscn -- <out_dir>

const PARTS_DIR := "res://assets/ship_parts"

func _ready() -> void:
	var out_dir := "user://hull_sheet"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(820, 820))

	var gray := StandardMaterial3D.new()
	gray.albedo_color = Color(0.62, 0.64, 0.68)
	gray.metallic = 0.5
	gray.roughness = 0.45

	var cam: Camera3D = $Camera3D
	await get_tree().process_frame

	# Load manifest to enumerate every category.
	var f := FileAccess.open("%s/manifest.json" % PARTS_DIR, FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	for cat in ["hulls", "engines", "weapons"]:
		var entries: Array = manifest.get(cat, [])
		entries.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
		var cols := 6
		var rows := int(ceil(float(entries.size()) / cols))
		var cell := 260
		var sheet := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.02, 0.025, 0.04))
		print("=== ", cat, " ===")
		for i in range(entries.size()):
			var name := str(entries[i]["name"])
			print("  [%d] %s" % [i, name])
			for c in $ShipHolder.get_children():
				c.queue_free()
			await get_tree().process_frame
			var path := "%s/%s/%s.glb" % [PARTS_DIR, cat, name.replace(" ", "_")]
			if not ResourceLoader.exists(path):
				continue
			var node := (load(path) as PackedScene).instantiate()
			ShipAssembler._apply_material(node, gray)
			$ShipHolder.add_child(node)
			var box := _aabb(node)
			var size: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
			var center: Vector3 = box.position + box.size * 0.5
			cam.position = center + Vector3(0.5, 0.5, 0.7).normalized() * maxf(size * 1.05, 4.0)
			cam.look_at(center, Vector3.UP)
			for _fr in range(4):
				await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.resize(cell, cell)
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
		sheet.save_png("%s/sheet_%s.png" % [out_dir, cat])
		print("SAVED sheet_", cat)

	print("HULL_SHEET_DONE")
	get_tree().quit()


func _aabb(node: Node3D) -> AABB:
	var meshes: Array = []
	_collect(node, meshes)
	var combined := AABB()
	var first := true
	for mi in meshes:
		var rel: Transform3D = node.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = rel * mi.get_aabb()
		if first:
			combined = b; first = false
		else:
			combined = combined.merge(b)
	return combined

func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
