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
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			if _apply_one(mesh.surface_get_material(i) as StandardMaterial3D):
				changed += 1
	return changed


static func _apply_one(mat: StandardMaterial3D) -> bool:
	if mat == null or mat.albedo_texture == null or mat.has_meta(_DONE_META):
		return false
	mat.set_meta(_DONE_META, true)
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
