extends Node3D

## The Lodestar itself, in its system (core loop step 12): a landmark the
## Captain flies to, built from primitives per card ("landmark" in the card's
## arrival_scene). Placed by LodestarGuide; it lists itself in the overview as
## "Lodestar" and is never hidden by sensors (SiteRevealModel LARGE_GROUPS).
## No collision: it's set well clear of the lanes, and the scene plays before
## the ship reaches it.

const GOLD := Color(1.0, 0.82, 0.45)
## Built at a modest size, shown three times larger: a destination, not a prop.
const SCALE := 3.0

var display_name := "Lodestar"
var kind := "beacon"
var _spin: Node3D = null
var _light: OmniLight3D = null
var _t := 0.0


func _ready() -> void:
	add_to_group("lodestar")
	scale = Vector3.ONE * SCALE
	match kind:
		"fleet": _build_fleet()
		"ring": _build_ring()
		"survey": _build_survey()
		"garden": _build_garden()
		"wrecks": _build_wrecks()
		_: _build_beacon()
	# A gold glow every kind shares, so it reads as the place from far off.
	_light = OmniLight3D.new()
	_light.light_color = GOLD
	_light.omni_range = 2200.0
	_light.light_energy = 3.0
	add_child(_light)
	# A soft white fill so hulls read out here, far from any sun.
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.8, 0.88, 1.0)
	fill.omni_range = 2600.0
	fill.light_energy = 1.2
	fill.position = Vector3(220, 160, 260)
	add_child(fill)
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.active_system_entities.append(self)
		gs.entities_changed.emit()


func _exit_tree() -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.active_system_entities.erase(self)
		gs.entities_changed.emit()


func _process(delta: float) -> void:
	_t += delta
	if _light != null:
		_light.light_energy = 2.4 + 0.9 * sin(_t * 1.6)
	if _spin != null:
		_spin.rotate_y(delta * (0.6 if kind == "beacon" else 0.05))


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
