extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(args[0], state) != OK:
		push_error("Mine GLB parse failed")
		quit(1)
		return
	var scene := document.generate_scene(state)
	if scene == null:
		quit(1)
		return
	root.add_child(scene)
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var cameras := scene.find_children("*", "Camera3D", true, false)
	var lights := scene.find_children("*", "Light3D", true, false)
	var asteroid := scene.find_child("Asteroid exterior*", true, false) as MeshInstance3D
	var pit := scene.find_child("Terraced excavation*", true, false) as MeshInstance3D
	var belts := scene.find_child("Conveyor belts*", true, false) as MeshInstance3D
	var surfaces := 0
	for mesh in meshes:
		surfaces += mesh.mesh.get_surface_count()
	var valid := meshes.size() == 29 and surfaces == 29 and cameras.is_empty() and lights.is_empty() and asteroid != null and pit != null and belts != null
	var rock_width := 0.0
	if asteroid != null:
		rock_width = asteroid.get_aabb().size.x
		valid = valid and absf(rock_width - 1500.0) < 0.1
	print("Cartographer Mine GLB: meshes=%d surfaces=%d cameras=%d lights=%d asteroid_width=%.2fm pit=%s belt=%s valid=%s" % [meshes.size(), surfaces, cameras.size(), lights.size(), rock_width, pit != null, belts != null, valid])
	scene.free()
	quit(0 if valid else 1)
