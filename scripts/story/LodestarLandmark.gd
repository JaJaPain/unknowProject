extends Node3D

## The Lodestar itself, in its system (core loop step 12): a landmark the
## Captain flies to. Each kind ("landmark" in the card's arrival_scene) is one
## of ChatGPT's set pieces at true size (docs/set_piece_wishlist.md), with a
## few things alive: the gate's halo turns, the beacon pulses, wings track,
## lights blink, the conveyor runs. Primitives stand in if a model is missing.
## Placed by LodestarGuide; it lists itself in the overview by the place's
## name and is never hidden by sensors (SiteRevealModel LARGE_GROUPS).
## No collision: it's set well clear of the lanes; the autopilot stops at its
## edge (approach_stop_distance) and the scene plays before the ship reaches it.

const GOLD := Color(1.0, 0.82, 0.45)
## Primitive stand-ins are built at a modest size, shown three times larger.
const SCALE := 3.0
const MODELS := {
	"beacon": ["res://assets/landmarks/lighthouse.glb"],
	"fleet": ["res://assets/landmarks/silent_fleet.glb"],
	"ring": ["res://assets/landmarks/humming_gate.glb"],
	"survey": ["res://assets/landmarks/cartographer_mine.glb"],
	"garden": ["res://assets/landmarks/garden_keepers.glb"],
	"wrecks": ["res://assets/landmarks/twin_wreck_field_v3_batched.glb", "res://assets/landmarks/quiet_war_vault.glb"],
	# Set pieces reused as other places (docs/destinations_expansion_plan_2026_10_06.md).
	"market": ["res://assets/landmarks/cartographer_mine.glb"],
	"shipyard": ["res://assets/landmarks/lone_derelict.glb"],
}
## How a reused set piece becomes another place: parts hidden (by name),
## materials re-coloured (by name), a scale, and extras the code adds.
const VARIANTS := {
	# The Hollow Market: the mine's asteroid as an icy comet, its structures
	# gone, its worklights turned to warm lanterns, a tail behind it.
	"market": {
		"hide": ["Refinery", "Loading cranes", "Moored hauler", "Docking arm", "Storage tanks",
			"Conveyor", "Ore buckets", "Pit machinery", "Utility network", "Worklight fixtures"],
		"tint": {"Dark asteroid rock": Color(0.66, 0.74, 0.84), "Fresh cut rock": Color(0.86, 0.92, 1.0),
			"Mineral flecks": Color(0.7, 0.9, 1.0)},
		"glow": {"Cold worklights": Color(1.0, 0.7, 0.36), "Habitat amber": Color(1.0, 0.62, 0.3)},
		"tint_replaces_vertex_colors": true,
		"extras": ["comet_tail"],
	},
	# The Last Shipyard: the derelict hull, clean and three times the size,
	# its open side read as unfinished plating, inside a scaffold with sparks.
	"shipyard": {
		"scale": 3.0,
		"hide": ["DriftingCargo"],
		"tint": {"Neutral hull": Color(0.84, 0.86, 0.88), "Muted accent": Color(0.72, 0.56, 0.3)},
		"glow": {"Emergency emission": Color(0.75, 0.9, 1.0), "Beacon emission": Color(1.0, 0.8, 0.4)},
		"extras": ["scaffold"],
	},
}
## The Garden's green world: its radius, and how far below the station its
## centre sits (the station orbits over it).
const GARDEN_WORLD_RADIUS := 6000.0
const GARDEN_WORLD_DROP := 7800.0
## Where the Quiet War's vault sits inside the wreck field.
const VAULT_OFFSET := Vector3(0, -40, 0)
## The autopilot stops this far outside the model.
const STOP_MARGIN := 300.0

var display_name := "Destination"
var kind := "beacon"
var _spin: Node3D = null
var _light: OmniLight3D = null
var _t := 0.0
var _radius := 0.0
## Moving parts of a model: [{node, axis, speed}] turned every frame, and
## [{node, axis, base, amp, rate}] swung gently back and forth.
var _turners: Array = []
var _swingers: Array = []
## Lit materials that pulse, blink or breathe: [{mat, base, mode, phase}].
var _lamps: Array = []
var _belt: StandardMaterial3D = null
## The Last Shipyard's welding sparks (flicker in _process).
var _sparks: Array = []
var _gold_base := 2.4
var _gold_swing := 0.9


func _ready() -> void:
	add_to_group("lodestar")
	if not _build_models():
		scale = Vector3.ONE * SCALE
		match kind:
			"fleet": _build_fleet()
			"ring": _build_ring()
			"survey": _build_survey()
			"garden": _build_garden()
			"wrecks": _build_wrecks()
			_: _build_beacon()
	_radius = _measure()
	if kind == "garden" and uses_model():
		_add_garden_world()
	var reach := maxf(_radius, 300.0)
	# A gold glow every kind shares, so it reads as the place from far off.
	_light = OmniLight3D.new()
	_light.light_color = GOLD
	_light.omni_range = maxf(2200.0, reach * 2.6)
	_light.light_energy = 3.0
	add_child(_light)
	# The set pieces have their own colours: the gold only warms them.
	_gold_base = 2.4 if not uses_model() else 0.6
	_gold_swing = 0.9 if not uses_model() else 0.2
	# A soft white fill so hulls read out here, far from any sun.
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.8, 0.88, 1.0)
	fill.omni_range = maxf(2600.0, reach * 3.0)
	fill.light_energy = 1.2 if not uses_model() else 1.4
	fill.position = Vector3(220, 160, 260) if not uses_model() else Vector3(0.75, 0.55, 0.9) * reach
	add_child(fill)
	if uses_model():
		# A second, dimmer fill from the other side so no face is pitch black.
		var back := OmniLight3D.new()
		back.light_color = Color(0.75, 0.82, 1.0)
		back.omni_range = reach * 3.0
		back.light_energy = 0.7
		back.position = Vector3(-0.8, -0.3, -0.7) * reach
		add_child(back)
		# At kilometre scale the usual falloff leaves almost nothing: these
		# lights hold their strength out to their range.
		for light in [_light, fill, back]:
			(light as OmniLight3D).omni_attenuation = 0.0
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.active_system_entities.append(self)
		gs.entities_changed.emit()


## How far out the place reaches from its centre (metres, as shown).
func radius() -> float:
	return _radius


## The autopilot's APPROACH stops here: outside the model, never inside it.
func approach_stop_distance() -> float:
	return _radius + STOP_MARGIN


## True when this place is ChatGPT's model rather than the stand-in.
func uses_model() -> bool:
	return get_node_or_null("Model0") != null or get_node_or_null("Model1") != null


func _build_models() -> bool:
	var paths: Array = MODELS.get(kind, [])
	var built := 0
	for i in paths.size():
		var path := str(paths[i])
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var model := scene.instantiate() as Node3D
		model.name = "Model%d" % i
		if path.contains("quiet_war_vault"):
			model.position = VAULT_OFFSET
		add_child(model)
		var variant: Dictionary = VARIANTS.get(kind, {})
		if not variant.is_empty():
			_apply_variant(model, variant)
		_wire_model(model)
		built += 1
	return built > 0


## Re-dresses a reused set piece (VARIANTS): hides parts, re-colours
## materials, scales it, and adds the extras.
func _apply_variant(model: Node3D, variant: Dictionary) -> void:
	model.scale = Vector3.ONE * float(variant.get("scale", 1.0))
	for node in model.find_children("*", "Node3D", true, false):
		for part in variant.get("hide", []):
			if str(node.name).contains(str(part)):
				(node as Node3D).visible = false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null:
				continue
			for key in variant.get("tint", {}):
				if m.resource_name.contains(str(key)):
					var own := m.duplicate() as StandardMaterial3D
					own.albedo_color = variant["tint"][key]
					if bool(variant.get("tint_replaces_vertex_colors", false)):
						own.vertex_color_use_as_albedo = false
					mi.set_surface_override_material(i, own)
			for key in variant.get("glow", {}):
				if m.resource_name.contains(str(key)):
					var lit := m.duplicate() as StandardMaterial3D
					lit.emission_enabled = true
					lit.emission = variant["glow"][key]
					lit.albedo_color = variant["glow"][key]
					mi.set_surface_override_material(i, lit)
	for extra in variant.get("extras", []):
		match str(extra):
			"comet_tail": _add_comet_tail(model)
			"scaffold": _add_scaffold(model)


## A soft tail of drifting ice dust streaming off the comet (Hollow Market).
func _add_comet_tail(model: Node3D) -> void:
	var tail := GPUParticles3D.new()
	tail.name = "CometTail"
	tail.amount = 260
	tail.lifetime = 26.0
	tail.preprocess = 26.0
	tail.visibility_aabb = AABB(Vector3(-9000, -2500, -2500), Vector3(18000, 5000, 5000))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 520.0
	process.direction = Vector3(-1, 0.05, 0)
	process.spread = 6.0
	process.initial_velocity_min = 220.0
	process.initial_velocity_max = 380.0
	process.gravity = Vector3.ZERO
	process.scale_min = 0.6
	process.scale_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(0.75, 0.88, 1.0, 0.0))
	fade.add_point(0.12, Color(0.75, 0.88, 1.0, 0.07))
	fade.set_color(fade.get_point_count() - 1, Color(0.6, 0.75, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	tail.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(420, 420)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.7, 0.85, 1.0)
	# A soft round puff, not a square.
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1, 1, 1, 1))
	falloff.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = falloff
	mat.albedo_texture = puff
	quad.material = mat
	tail.draw_pass_1 = quad
	model.add_child(tail)


## An open scaffold cradle around the hull, with two cranes and welding
## sparks that flicker (Last Shipyard).
func _add_scaffold(model: Node3D) -> void:
	var box := _model_bounds(model)
	if box.size == Vector3.ZERO:
		return
	box = box.grow(box.size.length() * 0.06)
	var beams := MultiMeshInstance3D.new()
	beams.name = "Scaffold"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var beam := BoxMesh.new()
	beam.size = Vector3(1, 1, 1)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.36, 0.34, 0.3)
	steel.metallic = 0.7
	steel.roughness = 0.5
	beam.material = steel
	mm.mesh = beam
	var xforms: Array = []
	var thick := box.size.length() * 0.011
	var ribs := 13
	for r in ribs + 1:
		var x := box.position.x + box.size.x * float(r) / float(ribs)
		var mid_y := box.get_center().y
		var mid_z := box.get_center().z
		xforms.append(_beam(Vector3(x, mid_y, box.position.z), Vector3(thick, box.size.y, thick)))
		xforms.append(_beam(Vector3(x, mid_y, box.end.z), Vector3(thick, box.size.y, thick)))
		xforms.append(_beam(Vector3(x, box.end.y, mid_z), Vector3(thick, thick, box.size.z)))
		xforms.append(_beam(Vector3(x, box.position.y, mid_z), Vector3(thick, thick, box.size.z)))
	# Long rails tying the ribs together.
	for corner in [Vector2(box.position.y, box.position.z), Vector2(box.position.y, box.end.z),
			Vector2(box.end.y, box.position.z), Vector2(box.end.y, box.end.z)]:
		xforms.append(_beam(Vector3(box.get_center().x, corner.x, corner.y), Vector3(box.size.x, thick, thick)))
	# Two crane towers rising over the top rail, each with a boom.
	for f in [0.3, 0.72]:
		var cx: float = box.position.x + box.size.x * float(f)
		xforms.append(_beam(Vector3(cx, box.end.y + box.size.y * 0.35, box.position.z), Vector3(thick * 2.0, box.size.y * 0.7, thick * 2.0)))
		xforms.append(_beam(Vector3(cx, box.end.y + box.size.y * 0.7, box.get_center().z), Vector3(thick * 1.5, thick * 1.5, box.size.z * 0.9)))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	beams.multimesh = mm
	model.add_child(beams)
	# Welding sparks: small bright points that flicker along the hull.
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(0.8, 0.92, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(0.8, 0.92, 1.0)
	spark_mat.emission_energy_multiplier = 6.0
	var dot := SphereMesh.new()
	dot.radius = thick * 0.9
	dot.height = thick * 1.8
	var rng := RandomNumberGenerator.new()
	rng.seed = 731
	for i in 10:
		var spark := MeshInstance3D.new()
		spark.mesh = dot
		spark.material_override = spark_mat
		spark.position = Vector3(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y),
			box.end.z if i % 2 == 0 else box.position.z)
		model.add_child(spark)
		_sparks.append(spark)


func _beam(center: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), center)


## The bounds of everything visible in `model`, in the model's own space.
func _model_bounds(model: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inverse := model.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var box: AABB = (inverse * mi.global_transform) * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## The few live things on each set piece (pivots and emissive materials named
## in each model's README under art/).
func _wire_model(model: Node3D) -> void:
	for pair in [["InnerRing_Pivot", 0.035], ["EmitterRing_Pivot", 0.25]]:
		var pivot := model.find_child(str(pair[0]), true, false) as Node3D
		if pivot != null:
			_turners.append({"node": pivot, "axis": Vector3.UP, "speed": float(pair[1])})
	for wing in ["SolarPort_Pivot", "SolarStarboard_Pivot"]:
		var pivot := model.find_child(wing, true, false) as Node3D
		if pivot != null:
			_swingers.append({"node": pivot, "axis": Vector3.BACK, "base": pivot.transform.basis, "amp": 0.22, "rate": 0.02})
	for plate in model.find_children("LoosePlate_*", "Node3D", true, false):
		_turners.append({"node": plate, "axis": Vector3(0.3, 1.0, 0.2).normalized(), "speed": 0.02 + 0.01 * (_turners.size() % 3)})
	for anim in model.find_children("*", "AnimationPlayer", true, false):
		var player := anim as AnimationPlayer
		var names := player.get_animation_list()
		if not names.is_empty():
			player.get_animation(names[0]).loop_mode = Animation.LOOP_LINEAR
			player.play(names[0])
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null:
				continue
			var belt := m.resource_name.contains("Conveyor rubber")
			var mode := lamp_mode(m.resource_name)
			if mode.is_empty() and not belt:
				continue
			# Each place gets its own copy, so one pulsing never touches another.
			var own := m.duplicate() as StandardMaterial3D
			mi.set_surface_override_material(i, own)
			if belt:
				_belt = own
				continue
			var base := own.emission_energy_multiplier if own.emission_enabled else 1.0
			own.emission_enabled = true
			_lamps.append({"mat": own, "base": maxf(base, 0.5), "mode": mode, "phase": float(_lamps.size()) * 0.7})


## How each glowing material lives: "pulse" (the beacon), "blink" (navigation
## lights), "breathe" (slow and faint) or "" (left alone).
static func lamp_mode(material_name: String) -> String:
	if material_name.contains("Beacon emission"):
		return "pulse"
	if material_name.contains("Navigation emission") or material_name.contains("Dock navigation"):
		return "blink"
	if material_name.contains("Faint core status") or material_name.contains("Sealed door seam") \
			or material_name.contains("Segment point emission"):
		return "breathe"
	return ""


## The farthest point of any mesh from the centre, as shown (the Garden's
## world aside: it's scenery, not the place).
func _measure() -> float:
	var inverse := global_transform.affine_inverse()
	var best := 0.0
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := mi.get_aabb()
		var to_me := inverse * mi.global_transform
		for i in 8:
			best = maxf(best, (to_me * box.get_endpoint(i)).length())
	return best


## The Garden's green world below the station, dressed by the planet shaders
## (an archipelago world, its land pushed greener).
func _add_garden_world() -> void:
	var world := Node3D.new()
	world.name = "GardenWorld"
	world.position = Vector3(0, -GARDEN_WORLD_DROP, 0)
	add_child(world)
	var body := MeshInstance3D.new()
	body.name = "MeshInstance3D"
	var sphere := SphereMesh.new()
	sphere.radius = GARDEN_WORLD_RADIUS
	sphere.height = GARDEN_WORLD_RADIUS * 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	body.mesh = sphere
	world.add_child(body)
	preload("res://scripts/generation/TerrestrialLook.gd").apply(world, hash("garden_world"), 4)
	var surface := body.material_override as ShaderMaterial
	if surface != null:
		surface.set_shader_parameter("land_color", Color(0.24, 0.42, 0.16))
		surface.set_shader_parameter("land_amount", 0.62)


func _exit_tree() -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.active_system_entities.erase(self)
		gs.entities_changed.emit()


func _process(delta: float) -> void:
	_t += delta
	if _light != null:
		_light.light_energy = _gold_base + _gold_swing * sin(_t * 1.6)
	if _spin != null:
		_spin.rotate_y(delta * (0.6 if kind == "beacon" else 0.05))
	for t in _turners:
		(t["node"] as Node3D).rotate_object_local(t["axis"], float(t["speed"]) * delta)
	for w in _swingers:
		var node := w["node"] as Node3D
		node.transform.basis = (w["base"] as Basis) * Basis(w["axis"], float(w["amp"]) * sin(_t * float(w["rate"]) * TAU))
	for lamp in _lamps:
		var mat := lamp["mat"] as StandardMaterial3D
		var base := float(lamp["base"])
		var phase := float(lamp["phase"])
		match str(lamp["mode"]):
			"pulse":
				mat.emission_energy_multiplier = base * (0.55 + 0.75 * pow(0.5 + 0.5 * sin(_t * 1.6 + phase), 3.0))
			"blink":
				mat.emission_energy_multiplier = base * (1.6 if fmod(_t + phase, 2.2) < 0.35 else 0.15)
			"breathe":
				mat.emission_energy_multiplier = base * (0.6 + 0.4 * sin(_t * 0.5 + phase))
	if _belt != null:
		_belt.uv1_offset.y = fmod(_t * 0.08, 1.0)
	for i in _sparks.size():
		var spark := _sparks[i] as Node3D
		if is_instance_valid(spark):
			spark.visible = fmod(_t * 3.1 + float(i) * 0.37, 1.0) < 0.22


func _mat(color: Color, emission: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.metallic = 0.6
	m.roughness = 0.45
	m.emission_enabled = true
	if emission > 0.0:
		m.emission = color
		m.emission_energy_multiplier = emission
	else:
		# Hulls glow faintly, so their shapes never vanish into the black.
		m.emission = color.lightened(0.3)
		m.emission_energy_multiplier = 0.35
		m.rim_enabled = true
		m.rim = 0.6
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _part(mesh: Mesh, mat: Material, at: Vector3, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	if parent == null:
		parent = self
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("lodestar_landmark:" + kind)
	return rng


## The Lighthouse: a tall spire, a lit lamp and a sweeping beam.
func _build_beacon() -> void:
	var hull := _mat(Color(0.32, 0.34, 0.38))
	var spire := CylinderMesh.new()
	spire.top_radius = 4.0
	spire.bottom_radius = 10.0
	spire.height = 140.0
	_part(spire, hull, Vector3(0, 0, 0))
	for i in 3:
		_part(_box(Vector3(26, 10, 18)), hull, Vector3(0, -40.0 + i * 28.0, 0), self, Vector3(0, i * 1.1, 0))
	var lamp := SphereMesh.new()
	lamp.radius = 9.0
	lamp.height = 18.0
	_part(lamp, _mat(GOLD, 6.0), Vector3(0, 76, 0))
	_spin = Node3D.new()
	_spin.position = Vector3(0, 76, 0)
	add_child(_spin)
	var beam := CylinderMesh.new()
	beam.top_radius = 1.0
	beam.bottom_radius = 16.0
	beam.height = 320.0
	_part(beam, _mat(GOLD, 2.0, 0.12), Vector3(160, 0, 0), _spin, Vector3(0, 0, PI / 2.0))


## The Silent Fleet: rows of dark hulls, a few windows lit.
func _build_fleet() -> void:
	var rng := _rng()
	var hull := _mat(Color(0.22, 0.24, 0.27))
	var lit := _mat(Color(1.0, 0.85, 0.6), 3.0)
	for row in 4:
		for col in 6:
			var at := Vector3((col - 2.5) * 46.0, (row - 1.5) * 26.0 + rng.randf_range(-4, 4), rng.randf_range(-10, 10))
			var length := rng.randf_range(28.0, 46.0)
			_part(_box(Vector3(10, 7, length)), hull, at)
			if rng.randf() < 0.4:
				_part(_box(Vector3(1.5, 1.5, 1.5)), lit, at + Vector3(5.5, 1.0, rng.randf_range(-length / 3.0, length / 3.0)))


## The Humming Gate: a perfect ring with a shimmering heart.
func _build_ring() -> void:
	_spin = Node3D.new()
	add_child(_spin)
	var ring := TorusMesh.new()
	ring.inner_radius = 78.0
	ring.outer_radius = 92.0
	ring.rings = 64
	_part(ring, _mat(Color(0.75, 0.78, 0.85), 0.0), Vector3.ZERO, _spin, Vector3(PI / 2.0, 0, 0))
	var glow := TorusMesh.new()
	glow.inner_radius = 74.0
	glow.outer_radius = 77.0
	glow.rings = 64
	_part(glow, _mat(Color(0.55, 0.9, 1.0), 4.0), Vector3.ZERO, _spin, Vector3(PI / 2.0, 0, 0))
	var heart := QuadMesh.new()
	heart.size = Vector2(150, 150)
	_part(heart, _mat(Color(0.6, 0.85, 1.0), 1.5, 0.15), Vector3.ZERO, self)


## The circled system: a lone survey station, panels out, one light blinking.
func _build_survey() -> void:
	var hull := _mat(Color(0.4, 0.38, 0.33))
	var panel := _mat(Color(0.12, 0.2, 0.4), 0.4)
	_part(_box(Vector3(30, 18, 30)), hull, Vector3.ZERO)
	_part(_box(Vector3(12, 40, 12)), hull, Vector3(0, 28, 0))
	var mast := CylinderMesh.new()
	mast.top_radius = 0.6
	mast.bottom_radius = 1.2
	mast.height = 70.0
	_part(mast, hull, Vector3(0, 82, 0))
	for side in [-1.0, 1.0]:
		_part(_box(Vector3(60, 1, 22)), panel, Vector3(side * 48.0, 6, 0))
	_part(_box(Vector3(3, 3, 3)), _mat(Color(1.0, 0.3, 0.2), 5.0), Vector3(0, 118, 0))


## The Garden: a green world, hazy with air.
func _build_garden() -> void:
	var world := SphereMesh.new()
	world.radius = 110.0
	world.height = 220.0
	var green := _mat(Color(0.2, 0.62, 0.26))
	green.metallic = 0.0
	green.roughness = 0.9
	green.emission = Color(0.25, 0.7, 0.3)
	green.emission_energy_multiplier = 0.5
	_part(world, green, Vector3.ZERO)
	var air := SphereMesh.new()
	air.radius = 118.0
	air.height = 236.0
	_part(air, _mat(Color(0.55, 0.85, 1.0), 0.4, 0.07), Vector3.ZERO)


## The Quiet War: a field of broken hulls, still roughly in formation.
func _build_wrecks() -> void:
	var rng := _rng()
	var hull := _mat(Color(0.26, 0.22, 0.2))
	var ember := _mat(Color(1.0, 0.45, 0.15), 3.0)
	for i in 40:
		var at := Vector3(rng.randf_range(-160, 160), rng.randf_range(-40, 40), rng.randf_range(-160, 160))
		var rot := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		_part(_box(Vector3(rng.randf_range(6, 14), rng.randf_range(4, 8), rng.randf_range(14, 40))), hull, at, self, rot)
		if rng.randf() < 0.25:
			_part(_box(Vector3(2, 2, 2)), ember, at + Vector3(0, 4, 0))
