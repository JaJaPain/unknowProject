extends Node3D
## Offline catalog generator. For each role: generate many candidate recipes,
## score by proportion heuristics, auto-pick the best DISTINCT designs, freeze
## them to res://assets/ships/ship_designs.json, and render a contact sheet.
## Run: Godot --path . tools/assembler_preview/catalog_gen.tscn -- <sheet_dir>

const ROLES := ["Interceptor", "Gunner", "Logistics", "MiningHauler"]
const CANDIDATES_PER_ROLE := 20
const KEEP_PER_ROLE := 6
const CATALOG_PATH := "res://assets/ships/ship_designs.json"
# Target length/width aspect per role for scoring.
const ASPECT_TARGET := {"Interceptor": 3.6, "Gunner": 2.8, "Logistics": 3.4, "MiningHauler": 4.2}

var _gray: StandardMaterial3D

func _ready() -> void:
	var sheet_dir := "user://catalog_sheets"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		sheet_dir = args[0]
	DirAccess.make_dir_recursive_absolute(sheet_dir)
	DisplayServer.window_set_size(Vector2i(900, 900))

	_gray = StandardMaterial3D.new()
	_gray.albedo_color = Color(0.62, 0.64, 0.68)
	_gray.metallic = 0.55
	_gray.roughness = 0.45

	var cam: Camera3D = $Camera3D
	await get_tree().process_frame

	var catalog := {}
	for role in ROLES:
		var scored: Array = []
		var seen := {}
		for s in range(CANDIDATES_PER_ROLE):
			var recipe := ShipAssembler.generate_recipe(role, 7000 + s)
			if recipe.is_empty():
				continue
			var combo := "%s|%s|%s" % [recipe["hull"], _first_stem(recipe, "engines"), _first_stem(recipe, "weapons")]
			var node := ShipAssembler.build_from_recipe(recipe, "", false)
			if node == null:
				continue
			$ShipHolder.add_child(node)
			await get_tree().process_frame
			var box := _aabb(node)
			var score := _score(role, box)
			node.queue_free()
			# Keep only the best-scoring instance of each distinct part combo.
			if not seen.has(combo) or score > seen[combo]["score"]:
				seen[combo] = {"recipe": recipe, "score": score, "size": [box.size.x, box.size.y, box.size.z]}
		# Sort distinct combos by score desc, keep top N.
		scored = seen.values()
		scored.sort_custom(func(a, b): return a["score"] > b["score"])
		var chosen: Array = []
		for entry in scored.slice(0, KEEP_PER_ROLE):
			chosen.append(entry["recipe"])
		catalog[role] = chosen
		print("ROLE ", role, " distinct=", scored.size(), " kept=", chosen.size())
		await _render_sheet(role, chosen, cam, sheet_dir)

	# Write catalog JSON.
	var f := FileAccess.open(CATALOG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(catalog, "  "))
		f.close()
		print("WROTE ", ProjectSettings.globalize_path(CATALOG_PATH))
	else:
		print("ERR could not write ", CATALOG_PATH, " (", FileAccess.get_open_error(), ")")
	print("CATALOG_DONE")
	get_tree().quit()


func _first_stem(recipe: Dictionary, cat: String) -> String:
	for p in recipe.get("parts", []):
		if str(p["cat"]) == cat:
			return str(p["stem"])
	return "-"


## Proportion score: reward target aspect, penalize too-tall and extreme ratios.
func _score(role: String, box: AABB) -> float:
	var sx: float = maxf(box.size.x, 0.01)
	var sy: float = maxf(box.size.y, 0.01)
	var sz: float = maxf(box.size.z, 0.01)
	var aspect: float = sz / maxf(sx, sy)
	var target: float = float(ASPECT_TARGET.get(role, 3.0))
	var score: float = -absf(aspect - target)          # closer to target = better
	score -= maxf(0.0, sy / sx - 1.3) * 0.8            # penalize taller-than-wide
	if aspect < 1.5 or aspect > 7.0:
		score -= 2.0                                   # reject blobby / needle shapes
	return score


func _render_sheet(role: String, designs: Array, cam: Camera3D, out_dir: String) -> void:
	var cols := 3
	var rows := int(ceil(float(designs.size()) / cols))
	var cell := 300
	var sheet := Image.create(cols * cell, maxi(rows, 1) * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.02, 0.025, 0.04))
	for i in range(designs.size()):
		for c in $ShipHolder.get_children():
			c.queue_free()
		await get_tree().process_frame
		var node := ShipAssembler.build_from_recipe(designs[i], "", false)
		ShipAssembler._apply_material(node, _gray)
		$ShipHolder.add_child(node)
		var box := _aabb(node)
		var size: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
		var center: Vector3 = box.position + box.size * 0.5
		cam.position = center + Vector3(0.62, 0.42, 0.66).normalized() * maxf(size * 1.0, 5.0)
		cam.look_at(center, Vector3.UP)
		for _f in range(4):
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(cell, cell)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var col := i % cols
		var row := i / cols
		sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i(col * cell, row * cell))
	sheet.save_png("%s/sheet_%s.png" % [out_dir, role])


func _aabb(node: Node3D) -> AABB:
	var meshes: Array = []
	_collect(node, meshes)
	var combined := AABB()
	var first := true
	for mi in meshes:
		var rel: Transform3D = node.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = rel * mi.get_aabb()
		if first:
			combined = b; first = false
		else:
			combined = combined.merge(b)
	return combined

func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
