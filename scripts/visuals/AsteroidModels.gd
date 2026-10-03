class_name AsteroidModels
extends RefCounted

const ATLAS_PATH := "res://assets/asteroidTextures.png"
const JSON_PATH := "res://assets/asteroids/asteroid_models.json"
const MODEL_DIR := "res://assets/asteroids/"
const CELL_SIZE := 1.0 / 3.0
## Per-ore atlases in the same 3x3 layout as ATLAS_PATH (OreTypes ids).
const ORE_ATLAS_DIR := "res://assets/asteroid_ores/"

static var _ore_materials := {}

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
			_add_normal(mat, ATLAS_PATH)
			mat.roughness = 0.95
			mat.metallic = 0.1
			mat.uv1_scale = Vector3(CELL_SIZE, CELL_SIZE, 1.0)
			mat.uv1_offset = Vector3(float(cx) * CELL_SIZE, float(cy) * CELL_SIZE, 0.0)
			mat_cache[mat_key] = mat

		_entries.append({
			"mesh": mesh,
			"cell": Vector2i(cx, cy),
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


## The material for a model in an ore's own atlas (same cell as the plain
## rock), or null when that ore has no atlas yet (the caller tints instead).
## The atlas carries the ore's look itself (thorium's veins are bright
## already), so these do not glow.
static func ore_material_for_index(idx: int, ore_type: String) -> Material:
	_ensure_loaded()
	if _entries.is_empty():
		return null
	idx = wrapi(idx, 0, _entries.size())
	var cell: Vector2i = _entries[idx].get("cell", Vector2i.ZERO)
	var key := "%s|%d_%d" % [ore_type, cell.x, cell.y]
	if _ore_materials.has(key):
		return _ore_materials[key]
	var path := ORE_ATLAS_DIR + ore_type + ".png"
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	var mat: StandardMaterial3D = null
	if tex != null:
		mat = StandardMaterial3D.new()
		mat.albedo_texture = tex
		_add_normal(mat, path)
		mat.roughness = 0.9
		mat.metallic = 0.15
		mat.uv1_scale = Vector3(CELL_SIZE, CELL_SIZE, 1.0)
		mat.uv1_offset = Vector3(float(cell.x) * CELL_SIZE, float(cell.y) * CELL_SIZE, 0.0)
	_ore_materials[key] = mat
	return mat


## The rock's normal map, baked from its atlas by tools/make_normal_maps.py
## (<atlas>_normal.png, same cell layout, so the albedo's uv1 offset lines it
## up). Playtest 2026-10-03 finding 4: rocks read flat without it.
const NORMAL_SCALE := 0.7


static func _add_normal(mat: StandardMaterial3D, atlas_path: String) -> void:
	var normal_path := atlas_path.get_basename() + "_normal.png"
	if not ResourceLoader.exists(normal_path):
		return
	mat.normal_enabled = true
	mat.normal_texture = load(normal_path) as Texture2D
	mat.normal_scale = NORMAL_SCALE


static func fragment_scene_path_for_index(idx: int) -> String:
	_ensure_loaded()
	if _entries.is_empty():
		return ""
	idx = wrapi(idx, 0, _entries.size())
	return str(_entries[idx].get("fragments_path", ""))
