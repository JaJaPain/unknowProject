extends RefCounted

## Hull-scale normal maps for ChatGPT's station and outpost skins (polish,
## Abe 2026-10-04). Each textured skin material gets <colour>_normal.png,
## baked by tools/make_station_normal_maps.py (panel seams and wear, with
## the skin's own micro normal blended in), in place of the faint micro
## normal alone. The materials are shared by every copy of a model, so this
## is done once per material.
##
## `--no-station-normals` leaves the skins as exported (for comparisons).

const _DONE_META := &"station_normals_done"


static func apply(model: Node, force := false) -> int:
	if not force and "--no-station-normals" in OS.get_cmdline_user_args():
		return 0
	var changed := 0
	var skin := model.scene_file_path.get_basename()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			if _apply_one(mesh.surface_get_material(i) as StandardMaterial3D, skin):
				changed += 1
	return changed


static func _apply_one(mat: StandardMaterial3D, skin: String) -> bool:
	if mat == null or mat.has_meta(_DONE_META):
		return false
	mat.set_meta(_DONE_META, true)
	if mat.resource_name.ends_with("Recess_Black"):
		_metal_panel(mat, skin)
		return true
	if mat.albedo_texture == null:
		return false
	var src := mat.albedo_texture.resource_path
	if src.is_empty():
		return false
	var path := src.get_basename() + "_normal.png"
	if not ResourceLoader.exists(path):
		return false
	mat.normal_enabled = true
	mat.normal_texture = load(path)
	mat.normal_scale = 1.0
	return true


## The Cinder stations' black panels (Abe, 2026-10-05: "turn the metallic
## up"): exported as near-black, barely metallic and matte, so they read as
## flat paint. Metal shows its colour only in what it reflects (and here that's
## mostly black space), so the colour comes up to a gunmetal grey along with
## the metallic, and they're smoother, so the sun and the station lights
## glint off them. Plating from the ships' hull normal sheets (Abe: "more
## surfaces to reflect off"; <skin>_panel_normal.png, a different pattern per
## station) gives the light edges and rivets to catch. The panels have no
## usable UVs, so it's projected along the model's axes, one tile per
## PANEL_TILE units.
const PANEL_TILE := 40.0


static func _metal_panel(mat: StandardMaterial3D, skin: String) -> void:
	mat.albedo_color = Color(0.16, 0.17, 0.19)
	mat.metallic = 0.85
	mat.metallic_specular = 0.6
	mat.roughness = 0.38
	var plates := skin + "_panel_normal.png"
	if ResourceLoader.exists(plates):
		mat.normal_enabled = true
		mat.normal_texture = load(plates)
		mat.normal_scale = 1.0
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3.ONE / PANEL_TILE
