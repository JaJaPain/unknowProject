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
		_wire_model(model)
		built += 1
	return built > 0


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
