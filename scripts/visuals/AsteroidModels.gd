class_name AsteroidModels
extends RefCounted

const ATLAS_PATH := "res://assets/asteroidTextures.png"
const JSON_PATH := "res://assets/asteroids/asteroid_models.json"
const MODEL_DIR := "res://assets/asteroids/"
const CELL_SIZE := 1.0 / 3.0

static var _entries: Array[Dictionary] = []
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var atlas_texture := load(ATLAS_PATH) as Texture2D
	if not atlas_texture:
		push_error("[AsteroidModels] Could not load atlas texture")
		return

	var file := FileAccess.open(JSON_PATH, FileAccess.READ)
	if not file:
		push_error("[AsteroidModels] Could not open %s" % JSON_PATH)
		return
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var data: Dictionary = json.data

	var mat_cache := {}

	for entry in data["models"]:
		var scene := load(MODEL_DIR + entry["file"]) as PackedScene
		if not scene:
			continue

		var node := scene.instantiate()
		var mesh: Mesh = null
		if node is MeshInstance3D:
			mesh = node.mesh
		else:
			for child in node.get_children():
				if child is MeshInstance3D:
					mesh = child.mesh
					break

		if mesh == null:
			continue

		var cell: Array = entry["texture_cell"]
		var cx := int(cell[0])
		var cy := int(cell[1])
		var mat_key := "%d_%d" % [cx, cy]

		if mat_key not in mat_cache:
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = atlas_texture
			mat.roughness = 0.95
			mat.metallic = 0.1
			mat.uv1_scale = Vector3(CELL_SIZE, CELL_SIZE, 1.0)
			mat.uv1_offset = Vector3(float(cx) * CELL_SIZE, float(cy) * CELL_SIZE, 0.0)
			mat_cache[mat_key] = mat

		_entries.append({
			"mesh": mesh,
			"material": mat_cache[mat_key],
			"fragments_path": MODEL_DIR + str(entry.get("fragments_file", "")),
		})


static func apply_random_model(mesh_instance: MeshInstance3D, rng_seed: int) -> void:
	_ensure_loaded()
	if _entries.is_empty():
		return

	var idx := absi(rng_seed) % _entries.size()
	apply_model_index(mesh_instance, idx)


static func apply_model_index(mesh_instance: MeshInstance3D, idx: int) -> void:
	_ensure_loaded()
	if _entries.is_empty():
		return
	idx = wrapi(idx, 0, _entries.size())
	var entry: Dictionary = _entries[idx]
	mesh_instance.mesh = entry["mesh"]
	mesh_instance.set_surface_override_material(0, entry["material"])


static func model_index_for_seed(rng_seed: int) -> int:
	_ensure_loaded()
	if _entries.is_empty():
		return -1
	return absi(rng_seed) % _entries.size()


static func material_for_index(idx: int) -> Material:
	_ensure_loaded()
	if _entries.is_empty():
		return null
	idx = wrapi(idx, 0, _entries.size())
	return _entries[idx]["material"] as Material


static func fragment_scene_path_for_index(idx: int) -> String:
	_ensure_loaded()
	if _entries.is_empty():
		return ""
	idx = wrapi(idx, 0, _entries.size())
	return str(_entries[idx].get("fragments_path", ""))
