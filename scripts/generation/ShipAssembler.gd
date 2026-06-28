class_name ShipAssembler
extends RefCounted

## Runtime kitbash ship assembler. Builds a convincing ship Node3D from the
## exported part library (res://assets/ship_parts) — NO Blender at runtime.
## Forward = -Z (Godot convention). Hull spine + rear engines + dorsal/side
## weapons in mirrored pairs, with a faction metal+normal material applied.

const PARTS_DIR := "res://assets/ship_parts"
const TEX_DIR := "res://assets/ship_parts/textures"
const CATALOG_PATH := "res://assets/ships/ship_designs.json"

static var _scene_cache: Dictionary = {}     # res path -> PackedScene
static var _catalog: Dictionary = {}         # role -> Array[recipe]
static var _catalog_loaded := false

# Cockpit strip heights as fractions of hull height (live-tunable from DevPanel).
static var cockpit_y_fracs: Array = [0.60, 0.41]
# Per-strip depth offset along +Z (into the hull) from the frontmost face.
# Positive pushes the strip inward so it sits flush on a recessed panel.
static var cockpit_z_offsets: Array = [0.0, 0.0]
# Strip thickness (Z depth). A thin box (not a flat plane) so the lit face
# always pokes out even where the hull surface is irregular.
static var cockpit_thickness: float = 0.10

const FACTION_STYLE := {
	"vanguard": {
		"metal": "RedMetal.png",
		"normal": "hull_normal.png",
		"metallic": 0.82,
		"roughness": 0.42,
		"engine": Color(1.0, 0.32, 0.08),
		"badge": "VanguardBadge.png",
	},
	"zenith": {
		"metal": "NavyBlueMetal.png",
		"normal": "hull_normal.png",
		"metallic": 0.82,
		"roughness": 0.42,
		"engine": Color(0.3, 0.6, 1.0),
		"badge": "ZenithBadge.png",
	},
	"aurelia": {
		"metal": "ForestGreenMetal.png",
		"normal": "hull_normal.png",
		"metallic": 0.82,
		"roughness": 0.42,
		"engine": Color(0.4, 1.0, 0.6),
		"badge": "AurelliaBadge.png",
	},
	# Neutral gunmetal grey — no faction badge. Player-ship / showcase use.
	"gunmetal": {
		"metal": "metal.png",
		"normal": "hull_normal.png",
		"metallic": 0.85,
		"roughness": 0.40,
		"engine": Color(0.6, 0.8, 1.0),
	},
}

# Hand-picked showcase ships (favourites / player-ship candidates). Built from a
# forced hull so they don't depend on the random catalog. role drives the
# engine/weapon layout + marker setup.
const SPECIAL_SHIPS := [
	{"name": "Gunmetal — Tall", "faction": "gunmetal", "role": "Gunner", "hull": "hull.tall", "weapon": "Turret_Set", "cockpit": true},
]

# Curated military part pools (file stem under each category folder).
const VANGUARD_HULLS := {
	"Interceptor": ["hull.knuckle", "hull.angle", "hull.slick"],
	"Gunner": ["hull.bullHead", "hull.block_split", "hull.lump", "hull.fish"],
	"Logistics": ["hull.beard", "hull.fish", "hull.Horse", "hull.lump"],
	"MiningHauler": ["hull.large", "hull.hangar", "hull.bullHead", "hull.long"],
}
const VANGUARD_ENGINES := ["Cube_Engine", "Bracket_Engine", "Trap-Engine", "eng.body.split", "5-Engine", "Block_Engine_single"]
const VANGUARD_WEAPONS := ["Big_Gun", "Turret_Set", "Med_Gun", "hardpoint.dev.hammer", "hardpoint.base.cap"]

# role -> [engine_count, weapon_pairs]
const ROLE_LAYOUT := {
	"Interceptor": [1, 1],
	"Gunner": [2, 2],
	"Logistics": [2, 1],
	"MiningHauler": [3, 1],
}


static func _part_path(cat: String, stem: String) -> String:
	return "%s/%s/%s.glb" % [PARTS_DIR, cat, stem]


static func _load_part(cat: String, stem: String) -> Node3D:
	var path := _part_path(cat, stem)
	if not _scene_cache.has(path):
		if not ResourceLoader.exists(path):
			push_warning("[ShipAssembler] Missing part: %s" % path)
			return null
		_scene_cache[path] = load(path)
	var packed: PackedScene = _scene_cache[path]
	if packed == null:
		return null
	return packed.instantiate() as Node3D


## Combined AABB of all MeshInstance3D under `node`, expressed in node's space.
static func _node_aabb(node: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(node, meshes)
	var combined := AABB()
	var first := true
	for mi in meshes:
		var rel := node.transform.affine_inverse() * mi.transform
		var box := rel * mi.get_aabb()
		if first:
			combined = box
			first = false
		else:
			combined = combined.merge(box)
	return combined


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)


# Per-category look tweaks layered on top of the faction metal. Tune freely.
#   tint        : multiplies the metal albedo (darken/shift)
#   metallic/rough overrides; emission adds a faint glow in `emit` colour.
const PART_LOOK := {
	"hull":   {"tint": Color(1, 1, 1),       "metallic": 0.82, "rough": 0.42, "emit_energy": 0.0},
	# Engine section is dark faction metal (body can't be split from the small
	# exhaust nozzle — parts are single merged meshes). Exhaust glow is added
	# in-game by NPCShip._create_engine_glow at the engine_* markers.
	"engine": {"tint": Color(0.5, 0.5, 0.55), "metallic": 0.7, "rough": 0.55, "emit_energy": 0.0},
	"weapon": {"tint": Color(0.42, 0.43, 0.48), "metallic": 0.95, "rough": 0.3,  "emit_energy": 0.0},
	# Thruster nozzles (split out of 5-Engine in Blender): crisp dark METAL — no
	# emission. The glow is the thrust plume coming out of them (engine glow at the
	# engine_* markers), not the part emitting. Surfaces named "Thruster".
	"thruster": {"tint": Color(0.32, 0.33, 0.36), "metallic": 0.9, "rough": 0.22, "emit_energy": 0.0},
}


## Build a faction metal+normal material for a part kind (triplanar — parts have
## no clean UVs). kind in {"hull","engine","weapon"}.
static func _build_part_material(faction: String, kind: String = "hull") -> StandardMaterial3D:
	var style: Dictionary = FACTION_STYLE.get(faction, FACTION_STYLE["vanguard"])
	var look: Dictionary = PART_LOOK.get(kind, PART_LOOK["hull"])
	var mat := StandardMaterial3D.new()
	# A part-look can override the faction metal with a neutral texture (thrusters).
	var metal_file := str(look.get("metal", style["metal"]))
	var metal_path := "%s/metals/%s" % [TEX_DIR, metal_file]
	if ResourceLoader.exists(metal_path):
		mat.albedo_texture = load(metal_path)
	mat.albedo_color = look["tint"]
	var normal_path := "%s/normals/%s" % [TEX_DIR, style["normal"]]
	if ResourceLoader.exists(normal_path):
		mat.normal_enabled = true
		mat.normal_texture = load(normal_path)
		mat.normal_scale = 1.0
	mat.metallic = float(look.get("metallic", 0.82))
	mat.roughness = float(look.get("rough", 0.42))
	var emit_energy := float(look.get("emit_energy", 0.0))
	if emit_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = style.get("engine", Color(1.0, 0.32, 0.08))
		mat.emission_energy_multiplier = emit_energy
	# Triplanar world-ish mapping so the metal tiles evenly over every part.
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	return mat


## Backwards-compatible hull material (used by neutral previews etc.).
static func _build_material(faction: String) -> StandardMaterial3D:
	return _build_part_material(faction, "hull")


## Apply one material to every mesh under root (used for neutral gray previews).
static func _apply_material(root: Node3D, mat: Material) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	for mi in meshes:
		var surf := mi.mesh.get_surface_count() if mi.mesh else 0
		for s in range(maxi(surf, 1)):
			mi.set_surface_override_material(s, mat)


## Apply per-category faction materials: hull / engine / weapon each differ.
static func _apply_faction_materials(root: Node3D, faction: String) -> void:
	var hull_mat := _build_part_material(faction, "hull")
	var engine_mat := _build_part_material(faction, "engine")
	var weapon_mat := _build_part_material(faction, "weapon")
	var thruster_mat := _build_part_material(faction, "thruster")
	for child in root.get_children():
		if not (child is Node3D):
			continue
		var cname := str(child.name)
		if cname == "FactionBadge":
			continue                                  # keeps its own override
		var is_engine := cname.begins_with("mount_engines")
		var mat: Material = hull_mat
		if is_engine:
			mat = engine_mat
		elif cname.begins_with("mount_weapons"):
			mat = weapon_mat
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(child, meshes)
		for mi in meshes:
			var surf := mi.mesh.get_surface_count() if mi.mesh else 0
			for s in range(maxi(surf, 1)):
				# Engines may have a split-out "Thruster" surface — give the
				# nozzles their own crisp material, body keeps engine metal.
				if is_engine and _surface_is_thruster(mi, s):
					mi.set_surface_override_material(s, thruster_mat)
				else:
					mi.set_surface_override_material(s, mat)


## True if a mesh surface's source material is the split-out thruster material.
static func _surface_is_thruster(mi: MeshInstance3D, s: int) -> bool:
	if mi.mesh == null or s >= mi.mesh.get_surface_count():
		return false
	var src := mi.mesh.surface_get_material(s)
	return src != null and "thruster" in str(src.resource_name).to_lower()


static func _add_marker(parent: Node3D, marker_name: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	parent.add_child(m)


## Generate a DESIGN RECIPE (pure data) for a role from a seed. This is the
## offline step — runs the RNG placement and freezes the result as a dict.
## Schema:
##   {role, hull, parts:[{cat,stem,pos:[x,y,z]}...],
##    engine_markers:[[x,y,z]...], weapon_markers:[[x,y,z]...]}
static func generate_recipe(role: String, seed_value: int, hull_override: String = "", weapon_override: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var hull_pool: Array = VANGUARD_HULLS.get(role, VANGUARD_HULLS["Gunner"])
	var layout: Array = ROLE_LAYOUT.get(role, [2, 1])
	var engine_count: int = int(layout[0])
	var weapon_pairs: int = int(layout[1])

	var hull_stem: String = hull_override if hull_override != "" else hull_pool[rng.randi() % hull_pool.size()]
	var hb = _measure_part("hulls", hull_stem)
	if hb == null:
		return {}
	var rear_z: float = hb.position.z + hb.size.z   # +Z = rear
	var nose_z: float = hb.position.z               # -Z = nose
	var top_y: float = hb.position.y + hb.size.y
	var length: float = hb.size.z
	var half_w: float = hb.size.x * 0.5

	var parts: Array = []
	var engine_markers: Array = []
	var weapon_markers: Array = []

	# Engines clustered at the rear, spread across X (mirrored).
	var eng_stem: String = VANGUARD_ENGINES[rng.randi() % VANGUARD_ENGINES.size()]
	var eb = _measure_part("engines", eng_stem)
	if eb != null:
		var spread := maxf(half_w * 0.55, 0.6)
		var xs := _spread_positions(engine_count, spread)
		for i in range(engine_count):
			var pz: float = rear_z - eb.position.z - eb.size.z * 0.18
			parts.append({"cat": "engines", "stem": eng_stem, "pos": [xs[i], 0.0, pz]})
			engine_markers.append([xs[i], 0.0, pz + eb.position.z + eb.size.z])

	# Weapons on dorsal surface in mirrored pairs, forward half.
	var wpn_stem: String = weapon_override if weapon_override != "" else VANGUARD_WEAPONS[rng.randi() % VANGUARD_WEAPONS.size()]
	var wb = _measure_part("weapons", wpn_stem)
	if wb != null:
		for p in range(weapon_pairs):
			var frac := 0.32 + 0.22 * float(p)
			var wz: float = nose_z + length * frac
			var wx: float = maxf(half_w * 0.5, 0.4)
			var py: float = top_y - wb.position.y - wb.size.y * 0.25
			for sign_x in [-1.0, 1.0]:
				parts.append({"cat": "weapons", "stem": wpn_stem, "pos": [sign_x * wx, py, wz]})
				weapon_markers.append([sign_x * wx, py + wb.size.y, wz - wb.size.z])

	return {
		"role": role,
		"hull": hull_stem,
		"parts": parts,
		"engine_markers": engine_markers,
		"weapon_markers": weapon_markers,
	}


## Instantiate a ship Node3D (forward = -Z) from a frozen recipe.
## apply_mat=false yields neutral, faction-agnostic geometry.
static func build_from_recipe(recipe: Dictionary, faction: String = "", apply_mat: bool = true) -> Node3D:
	if recipe.is_empty() or not recipe.has("hull"):
		return null
	var root := Node3D.new()
	root.name = "AssembledShip"

	var hull := _load_part("hulls", str(recipe["hull"]))
	if hull == null:
		root.free()
		return null
	hull.name = "Hull"
	root.add_child(hull)

	var counters := {"engines": 0, "weapons": 0, "greebles": 0, "detail": 0}
	for part in recipe.get("parts", []):
		var cat := str(part["cat"])
		var n := _load_part(cat, str(part["stem"]))
		if n == null:
			continue
		n.position = _arr_vec3(part["pos"])
		n.name = "mount_%s_%d" % [cat, int(counters.get(cat, 0))]
		counters[cat] = int(counters.get(cat, 0)) + 1
		root.add_child(n)

	var ei := 0
	for m in recipe.get("engine_markers", []):
		_add_marker(root, "engine_%d" % ei, _arr_vec3(m))
		ei += 1
	var wi := 0
	for m in recipe.get("weapon_markers", []):
		_add_marker(root, "weapon_%d" % wi, _arr_vec3(m))
		wi += 1

	if apply_mat:
		_apply_faction_materials(root, faction)
		_add_badge(root, faction)
	return root


## Place the faction badge as a flat dorsal decal near the bow.
static func _add_badge(root: Node3D, faction: String) -> void:
	var style: Dictionary = FACTION_STYLE.get(faction, {})
	var badge_file := str(style.get("badge", ""))
	if badge_file == "":
		return
	var badge_path := "%s/badges/%s" % [TEX_DIR, badge_file]
	if not ResourceLoader.exists(badge_path):
		return
	# Anchor to the hull part (not the whole assembly, whose top is the engines).
	var hull := root.get_node_or_null("Hull") as Node3D
	var box := _node_aabb(hull) if hull else _node_aabb(root)
	if box.size == Vector3.ZERO:
		return
	var tex: Texture2D = load(badge_path)
	var quad := MeshInstance3D.new()
	quad.name = "FactionBadge"
	var mesh := QuadMesh.new()
	# Width tracks hull width; height respects the badge's aspect ratio so the
	# emblem isn't distorted. Length axis (Z) is the long one on the hull.
	var w: float = clampf(box.size.x * 0.7, 0.8, box.size.z * 0.4)
	var aspect: float = 1.0
	if tex and tex.get_width() > 0:
		aspect = float(tex.get_height()) / float(tex.get_width())
	mesh.size = Vector2(w, w * aspect)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.emission_enabled = true
	mat.emission_texture = tex
	mat.emission_energy_multiplier = 0.9
	quad.material_override = mat
	# Lay flat on the dorsal hull, facing up (+Y). The badge's height runs along
	# the hull length (-Z forward), so rotate about X then yaw so text reads bow-up.
	quad.rotation_degrees = Vector3(-90.0, 180.0, 0.0)
	var top_y := box.position.y + box.size.y
	var mid_z := box.position.z + box.size.z * 0.45
	quad.position = Vector3(0.0, top_y + 0.05, mid_z)
	root.add_child(quad)


## Convenience: generate + build in one call (used for live previews/tests).
static func build(faction: String, role: String, seed_value: int, apply_mat: bool = true) -> Node3D:
	return build_from_recipe(generate_recipe(role, seed_value), faction, apply_mat)


## Load the frozen design catalog once (plain JSON, readable in exported builds).
static func _ensure_catalog() -> void:
	if _catalog_loaded:
		return
	_catalog_loaded = true
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("[ShipAssembler] No design catalog at %s" % CATALOG_PATH)
		return
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		_catalog = data


## Pick a frozen design for a role, deterministic by seed. Falls back to live
## generation only if the catalog has no entry for the role.
static func pick_design(role: String, seed_value: int) -> Dictionary:
	_ensure_catalog()
	var pool: Array = _catalog.get(role, [])
	if pool.is_empty():
		return generate_recipe(role, seed_value)
	return pool[abs(seed_value) % pool.size()]


## Build a ship from the frozen catalog (the runtime path). Reskins per faction.
static func build_catalog_ship(faction: String, role: String, seed_value: int, apply_mat: bool = true) -> Node3D:
	return build_from_recipe(pick_design(role, seed_value), faction, apply_mat)


## Roles present in the catalog (for tools/UI dropdowns).
static func catalog_roles() -> Array:
	_ensure_catalog()
	return _catalog.keys()


## Number of frozen designs for a role.
static func design_count(role: String) -> int:
	_ensure_catalog()
	return (_catalog.get(role, []) as Array).size()


## Factions that have a defined reskin style (for tools/UI dropdowns).
## Excludes "gunmetal" — that's a neutral showcase style, surfaced via specials.
static func styled_factions() -> Array:
	var out: Array = []
	for k in FACTION_STYLE.keys():
		if k != "gunmetal":
			out.append(k)
	return out


## Names of the hand-picked showcase ships (for tools/UI dropdowns).
static func special_ship_names() -> Array:
	var out: Array = []
	for s in SPECIAL_SHIPS:
		out.append(str(s["name"]))
	return out


## Build a showcase ship by index into SPECIAL_SHIPS.
static func build_special(index: int, apply_mat: bool = true) -> Node3D:
	if index < 0 or index >= SPECIAL_SHIPS.size():
		return null
	var spec: Dictionary = SPECIAL_SHIPS[index]
	var recipe := generate_recipe(str(spec["role"]), hash(str(spec["name"])),
		str(spec["hull"]), str(spec.get("weapon", "")))
	var node := build_from_recipe(recipe, str(spec["faction"]), apply_mat)
	if node and apply_mat and bool(spec.get("cockpit", false)):
		_add_cockpit_strips(node)
	return node


## Two emissive white "cockpit window" strips on the hull's +Z (camera-facing) face.
static func _add_cockpit_strips(root: Node3D) -> void:
	var hull := root.get_node_or_null("Hull") as Node3D
	if hull == null:
		return
	var hb := _node_aabb(hull)
	if hb.size == Vector3.ZERO:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.93, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var front_z: float = hb.position.z - 0.05                  # -Z face (camera-facing in game)
	var w: float = hb.size.x * 0.6
	var h: float = hb.size.y * 0.035
	# Two strips on the two flat hull panels; heights are live-tunable.
	var ys: Array = []
	for fr in cockpit_y_fracs:
		ys.append(hb.position.y + hb.size.y * float(fr))
	for i in range(ys.size()):
		var q := MeshInstance3D.new()
		q.name = "CockpitStrip_%d" % i
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, cockpit_thickness)   # thin box, not a flat plane
		q.mesh = bm
		q.material_override = mat
		var zoff: float = float(cockpit_z_offsets[i]) if i < cockpit_z_offsets.size() else 0.0
		q.position = Vector3(0.0, ys[i], front_z + zoff)
		root.add_child(q)


## Measure a part's AABB without keeping the instance. Returns null if missing.
static func _measure_part(cat: String, stem: String):
	var n := _load_part(cat, stem)
	if n == null:
		return null
	var box := _node_aabb(n)
	n.free()
	return box


static func _arr_vec3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Symmetric X offsets for n items around 0.
static func _spread_positions(n: int, spread: float) -> Array:
	if n <= 1:
		return [0.0]
	var out: Array = []
	for i in range(n):
		var t := float(i) / float(n - 1)        # 0..1
		out.append(lerpf(-spread, spread, t))
	return out
