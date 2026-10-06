extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the absolute Garden Keepers GLB path after --")
		quit(1)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(args[0], state) != OK:
		push_error("Garden Keepers GLB parse failed")
		quit(1)
		return
	var scene := document.generate_scene(state)
	if scene == null:
		push_error("Garden Keepers scene generation failed")
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
	var valid := meshes.size() == 17 and surfaces == 17 and cameras.is_empty() and lights.is_empty() and absf(bounds.size.z - 600.0) < 0.1
	var glass_node := scene.find_child("Greenhouse glass*", true, false) as MeshInstance3D
	if glass_node == null:
		valid = false
	else:
		var glass := glass_node.mesh.surface_get_material(0) as BaseMaterial3D
		print("Imported glass transparency=%s alpha=%s" % [glass.transparency if glass != null else -1, glass.albedo_color.a if glass != null else -1])
		valid = valid and glass != null and glass.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS] and absf(glass.albedo_color.a - 0.19) < 0.001
	for name in ["SolarPort_Pivot", "SolarStarboard_Pivot"]:
		var pivot := scene.find_child(name, true, false)
		print("Solar pivot %s children=%s" % [name, pivot.get_child_count() if pivot != null else -1])
		valid = valid and pivot != null and pivot.get_child_count() == 2
	print("Garden Keepers GLB: meshes=%d surfaces=%d cameras=%d lights=%d bounds=%s valid=%s" % [meshes.size(), surfaces, cameras.size(), lights.size(), bounds.size, valid])
	scene.free()
	quit(0 if valid else 1)
