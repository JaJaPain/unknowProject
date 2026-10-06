extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the absolute Quiet War Vault GLB path after --")
		quit(1)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(args[0], state) != OK:
		push_error("Quiet War Vault GLB parse failed")
		quit(1)
		return
	var scene := document.generate_scene(state)
	if scene == null:
		push_error("Quiet War Vault scene generation failed")
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
	var valid := meshes.size() == 13 and surfaces == 15 and cameras.is_empty() and lights.is_empty() and absf(bounds.size.x - 500.0) < 0.1 and absf(bounds.size.y - 141.975) < 0.1
	var door := scene.find_child("VaultDoor", true, false) as MeshInstance3D
	var pivot := scene.find_child("VaultDoor_Pivot", true, false)
	valid = valid and door != null and pivot != null
	if door != null and pivot != null:
		valid = valid and door.get_parent() == pivot and door.mesh.get_surface_count() == 3
	for plate in ["LoosePlate_01*", "LoosePlate_02*", "LoosePlate_03*"]:
		valid = valid and scene.find_child(plate, true, false) != null
	print("Quiet War Vault GLB: meshes=%d surfaces=%d cameras=%d lights=%d bounds=%s valid=%s" % [meshes.size(), surfaces, cameras.size(), lights.size(), bounds.size, valid])
	scene.free()
	quit(0 if valid else 1)
