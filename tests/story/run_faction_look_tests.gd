extends SceneTree

## Faction looks: a generated faction's ships wear its DNA (hull silhouette,
## paint, wear), the same every time, different between factions.
##   Godot --headless --path . --script res://tests/story/run_faction_look_tests.gd --log-file <path>

const DNA := preload("res://scripts/story/premise/FactionDNA.gd")
const Assembler := preload("res://scripts/generation/ShipAssembler.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var a := DNA.ship_look(DNA.for_faction("faction.gen.tarn_guild"))
	_check(a == DNA.ship_look(DNA.for_faction("faction.gen.tarn_guild")), "a faction's look is stable")
	_check(a["silhouette"] in DNA.SILHOUETTES and a["wear"] in DNA.WEAR and float(a["hue"]) >= 0.0 and float(a["hue"]) <= 1.0, "and complete: %s" % str(a))
	var hues := {}
	for i in 12:
		hues[snappedf(float(DNA.ship_look(DNA.for_faction("faction.gen.%d" % i))["hue"]), 0.1)] = true
	_check(hues.size() >= 5, "factions differ in paint (%d hue bands across 12)" % hues.size())

	# Silhouettes pick matching hulls where the role has one.
	var boxy := Assembler.pick_design_for_silhouette("MiningHauler", 3, "boxy")
	_check(str(boxy["hull"]) in Assembler.SILHOUETTE_HULLS["boxy"], "a boxy faction flies a boxy hauler: %s" % boxy["hull"])
	var spiky := Assembler.pick_design_for_silhouette("Interceptor", 5, "spiky")
	_check(str(spiky["hull"]) in Assembler.SILHOUETTE_HULLS["spiky"], "a spiky faction flies a spiky interceptor: %s" % spiky["hull"])
	_check(not Assembler.pick_design_for_silhouette("MiningHauler", 3, "spiky").is_empty(), "no match falls back to any design")

	# Paint and wear really change the hull.
	var plain := Assembler.build_catalog_ship("zenith", "Gunner", 11)
	var painted := Assembler.build_catalog_ship_with_look("zenith", "Gunner", 11, {"silhouette": "", "hue": 0.05, "wear": "scorched"})
	_check(plain != null and painted != null, "both ships build")
	if plain != null and painted != null:
		var p_mat := _first_hull_material(plain)
		var s_mat := _first_hull_material(painted)
		_check(p_mat != null and s_mat != null and not p_mat.albedo_color.is_equal_approx(s_mat.albedo_color), "the paint shows")
		_check(s_mat != null and is_equal_approx(s_mat.roughness, Assembler.WEAR_LOOK["scorched"][2]), "and so does the wear")
		plain.free()
		painted.free()

	if _failures.is_empty():
		print("[PASS] Faction looks")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _first_hull_material(root: Node3D) -> StandardMaterial3D:
	for child in root.get_children():
		if child is Node3D and not str(child.name).begins_with("mount_engines") and str(child.name) != "FactionBadge":
			var meshes: Array[MeshInstance3D] = []
			Assembler._collect_meshes(child, meshes)
			for mi in meshes:
				if mi.mesh != null and mi.mesh.get_surface_count() > 0:
					var m := mi.get_surface_override_material(0) as StandardMaterial3D
					if m != null:
						return m
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
