extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err := document.append_from_file("res://assets/landmarks/archive.glb", state)
	if err != OK:
		push_error("Archive GLB import failed: %s" % err)
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
	var bounds := AABB()
	var first := true
	var surfaces := 0
	var materials := {}
	var emitters := {}
	for mesh in meshes:
		var current: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = current if first else bounds.merge(current)
		first = false
		surfaces += mesh.mesh.get_surface_count()
		for i in mesh.mesh.get_surface_count():
			var mat = mesh.mesh.surface_get_material(i)
			materials[mat.resource_name] = true
			if mat is StandardMaterial3D and mat.emission_enabled:
				emitters[mat.resource_name] = true
	var pivots_ok := true
	for label in ["Envelope01_Pivot", "Envelope02_Pivot", "Envelope03_Pivot"]:
		var pivot = scene.find_child(label, true, false)
		pivots_ok = pivots_ok and pivot != null
		if pivot != null:
			pivots_ok = pivots_ok and pivot.get_child_count() >= 2
	var valid := meshes.size() < 50 and surfaces == meshes.size() and materials.size() <= 8
	valid = valid and cameras.is_empty() and lights.is_empty() and pivots_ok and emitters.size() == 3
	valid = valid and absf(bounds.size.x - 600.0) < 3.0 and bounds.size.y > bounds.size.x
	var report := {"valid":valid,"meshes":meshes.size(),"surfaces":surfaces,"materials":materials.keys(),
		"emission_materials":emitters.keys(),"cameras":cameras.size(),"lights":lights.size(),
		"godot_dimensions_m":[bounds.size.x,bounds.size.y,bounds.size.z],"envelope_pivots_valid":pivots_ok}
	var file := FileAccess.open("res://art/archive/validation_godot.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("Archive validation: ",JSON.stringify(report))
	scene.free()
	quit(0 if valid else 1)
