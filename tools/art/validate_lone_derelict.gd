extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the absolute Lone Derelict GLB path after --")
		quit(1)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(args[0], state) != OK:
		push_error("Lone Derelict GLB parse failed")
		quit(1)
		return
	var scene := document.generate_scene(state)
	if scene == null:
		push_error("Lone Derelict scene generation failed")
		quit(1)
		return
	root.add_child(scene)
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var cameras := scene.find_children("*", "Camera3D", true, false)
	var lights := scene.find_children("*", "Light3D", true, false)
	var surfaces := 0
	var bounds := AABB()
	var first := true
	for mesh in meshes:
		surfaces += mesh.mesh.get_surface_count()
		var current: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = current if first else bounds.merge(current)
		first = false
	var valid := meshes.size() == 13 and surfaces == 15 and cameras.is_empty() and lights.is_empty() and absf(bounds.size.x - 301.708) < 0.1
	for name in ["DriftingCargo_01", "DriftingCargo_02"]:
		valid = valid and scene.find_child(name, true, false) != null
	for name in ["Hull | Neutral hull tint", "Hull | Muted accent tint"]:
		var hull := scene.find_child(name, true, false) as MeshInstance3D
		if hull == null:
			valid = false
		else:
			var mat := hull.mesh.surface_get_material(0) as BaseMaterial3D
			valid = valid and mat != null and mat.vertex_color_use_as_albedo and mat.albedo_color.r < 0.8
	print("Lone Derelict GLB: meshes=%d surfaces=%d cameras=%d lights=%d bounds=%s valid=%s" % [meshes.size(), surfaces, cameras.size(), lights.size(), bounds.size, valid])
	scene.free()
	quit(0 if valid else 1)
