extends Node3D

## The broken jump gate the opening cinematic drags the ship through (Abe,
## 2026-09-30: "a broken Gateway that throws them into a strange system"; the
## old version was a hidden tunnel mesh and huge particles, spun about).
##
## Built around the ship and aligned with its heading (-Z is ahead):
## - a wide torn energy bore (shaders/broken_gate_tunnel.gdshader)
## - the gate's own ring structure streaming past in pieces: dark hull plates
##   with glowing seams, some missing, some knocked askew, a few tumbling free
## - electric arcs snapping between ring plates, with a light flash each time
## `surge()` makes the whole thing lurch; `exit_burst()` is the final throw.

const BORE_RADIUS := 70.0
const BORE_LENGTH := 1100.0
const RING_RADIUS := 44.0
const RING_COUNT := 7
const RING_SPACING := 150.0
const SEGMENTS := 14
const FLOW_SPEED := 240.0

var _bore_mat: ShaderMaterial
var _rings: Array[Node3D] = []
var _free_plates: Array[Dictionary] = []
var _arc_mesh: ImmediateMesh
var _arc_instance: MeshInstance3D
var _arc_light: OmniLight3D
var _arc_timer := 0.0
var _arc_life := 0.0
var _surge := 0.0
var _speed_scale := 1.0
var _rng := RandomNumberGenerator.new()
var _plate_mesh: BoxMesh
var _seam_mesh: BoxMesh
var _hull_mat: StandardMaterial3D
var _seam_mat: StandardMaterial3D
var _seam_hot_mat: StandardMaterial3D


func _ready() -> void:
	_rng.randomize()
	_build_bore()
	_build_materials()
	for i in RING_COUNT:
		var ring := _build_ring()
		ring.position = Vector3(0.0, 0.0, -120.0 - i * RING_SPACING)
		_rings.append(ring)
	_build_arcs()


func _build_bore() -> void:
	var bore := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = BORE_RADIUS
	mesh.bottom_radius = BORE_RADIUS
	mesh.height = BORE_LENGTH
	mesh.radial_segments = 48
	mesh.rings = 24
	mesh.cap_top = false
	mesh.cap_bottom = false
	bore.mesh = mesh
	_bore_mat = ShaderMaterial.new()
	_bore_mat.shader = load("res://shaders/broken_gate_tunnel.gdshader")
	bore.material_override = _bore_mat
	bore.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cylinder axis is Y; lay it along -Z, reaching far ahead and a little behind.
	bore.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	bore.position = Vector3(0.0, 0.0, -BORE_LENGTH * 0.5 + 120.0)
	bore.extra_cull_margin = 2000.0
	add_child(bore)
	var shell := MeshInstance3D.new()
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = BORE_RADIUS + 8.0
	shell_mesh.bottom_radius = BORE_RADIUS + 8.0
	shell_mesh.height = BORE_LENGTH + 400.0
	shell_mesh.radial_segments = 32
	shell_mesh.cap_top = true
	shell_mesh.cap_bottom = true
	shell.mesh = shell_mesh
	var shell_mat := StandardMaterial3D.new()
	shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell_mat.albedo_color = Color(0.004, 0.006, 0.02)
	shell.material_override = shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.rotation = bore.rotation
	shell.position = bore.position
	shell.extra_cull_margin = 2000.0
	add_child(shell)


func _build_materials() -> void:
	_plate_mesh = BoxMesh.new()
	_seam_mesh = BoxMesh.new()
	_hull_mat = StandardMaterial3D.new()
	_hull_mat.albedo_color = Color(0.22, 0.24, 0.28)
	_hull_mat.metallic = 0.6
	_hull_mat.roughness = 0.45
	# Lit by the gate's own glow: a faint cold fill so the plates read as metal.
	_hull_mat.emission_enabled = true
	_hull_mat.emission = Color(0.08, 0.14, 0.22)
	_hull_mat.rim_enabled = true
	_hull_mat.rim = 0.6
	_seam_mat = StandardMaterial3D.new()
	_seam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_seam_mat.albedo_color = Color(0.25, 0.85, 1.0)
	_seam_mat.emission_enabled = true
	_seam_mat.emission = Color(0.25, 0.85, 1.0)
	_seam_mat.emission_energy_multiplier = 4.0
	_seam_hot_mat = _seam_mat.duplicate() as StandardMaterial3D
	_seam_hot_mat.albedo_color = Color(1.0, 0.42, 0.12)
	_seam_hot_mat.emission = Color(1.0, 0.42, 0.12)


## One ring of the gate: plates around the circle, each with a glowing inner
## seam. Some are missing and some are knocked out of line; broken ends burn.
func _build_ring() -> Node3D:
	var ring := Node3D.new()
	add_child(ring)
	var arc := TAU / SEGMENTS
	var plate_len := RING_RADIUS * arc * 0.92
	for s in SEGMENTS:
		var roll := _rng.randf()
		if roll < 0.2:
			continue  # a missing plate: the ring is broken here
		var holder := Node3D.new()
		holder.rotation.z = arc * s
		ring.add_child(holder)
		var plate := MeshInstance3D.new()
		plate.mesh = _plate_mesh
		plate.scale = Vector3(plate_len, 5.5, 9.0)
		plate.material_override = _hull_mat
		plate.position = Vector3(0.0, RING_RADIUS, 0.0)
		holder.add_child(plate)
		var seam := MeshInstance3D.new()
		seam.mesh = _seam_mesh
		seam.scale = Vector3(plate_len * 0.96, 0.5, 1.4)
		seam.position = Vector3(0.0, RING_RADIUS - 2.9, 0.0)
		# The plates next to a gap burn orange: that's where it tore.
		seam.material_override = _seam_hot_mat if roll < 0.34 else _seam_mat
		holder.add_child(seam)
		if roll > 0.86:
			# Knocked askew by whatever broke the gate.
			holder.rotation.x = _rng.randf_range(-0.25, 0.25)
			holder.position = Vector3(0.0, 0.0, _rng.randf_range(-6.0, 6.0))
			plate.rotation.z = _rng.randf_range(-0.3, 0.3)
	ring.rotation.z = _rng.randf() * TAU
	ring.set_meta("spin", _rng.randf_range(-0.25, 0.25))
	return ring


func _build_arcs() -> void:
	_arc_mesh = ImmediateMesh.new()
	_arc_instance = MeshInstance3D.new()
	_arc_instance.mesh = _arc_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.85, 1.0)
	mat.emission_energy_multiplier = 8.0
	_arc_instance.material_override = mat
	_arc_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arc_instance.extra_cull_margin = 2000.0
	add_child(_arc_instance)
	_arc_light = OmniLight3D.new()
	_arc_light.light_color = Color(0.6, 0.8, 1.0)
	_arc_light.omni_range = 120.0
	_arc_light.light_energy = 0.0
	add_child(_arc_light)


func _process(delta: float) -> void:
	var step := FLOW_SPEED * _speed_scale * delta
	for ring in _rings:
		ring.position.z += step
		ring.rotation.z += float(ring.get_meta("spin")) * delta
		if ring.position.z > 60.0:
			# Recycle far ahead, sometimes shedding a plate that tumbles free.
			ring.position.z -= RING_COUNT * RING_SPACING
			if _rng.randf() < 0.5:
				_shed_plate(ring)
	for plate in _free_plates.duplicate():
		var node: Node3D = plate["node"]
		node.position += (plate["vel"] as Vector3) * delta + Vector3(0.0, 0.0, step)
		node.rotate(plate["axis"], float(plate["spin"]) * delta)
		if node.position.z > 80.0:
			node.queue_free()
			_free_plates.erase(plate)
	_surge = move_toward(_surge, 0.0, delta * 2.2)
	if _bore_mat != null:
		_bore_mat.set_shader_parameter("surge", _surge)
		_bore_mat.set_shader_parameter("flow_speed", 1.6 * _speed_scale)
	_arc_timer -= delta
	_arc_life -= delta
	if _arc_timer <= 0.0:
		_arc_timer = _rng.randf_range(0.18, 0.7) * (0.4 if _surge > 0.3 else 1.0)
		_strike_arc()
	elif _arc_life > 0.0 and _rng.randf() < 0.5:
		_strike_arc(true)  # the same arc crawls: redraw it jittered
	if _arc_life <= 0.0:
		_arc_mesh.clear_surfaces()
		_arc_light.light_energy = move_toward(_arc_light.light_energy, 0.0, delta * 60.0)


## A lightning arc between two points on the nearest rings.
var _arc_from := Vector3.ZERO
var _arc_to := Vector3.ZERO


func _strike_arc(rejitter: bool = false) -> void:
	if not rejitter:
		var ring_a: Node3D = _rings[_rng.randi() % _rings.size()]
		var ang_a := _rng.randf() * TAU
		var ang_b := ang_a + _rng.randf_range(0.6, 2.4) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_arc_from = ring_a.position + Vector3(cos(ang_a), sin(ang_a), 0.0) * (RING_RADIUS - 3.0)
		var z_b := ring_a.position.z + _rng.randf_range(-RING_SPACING, RING_SPACING) * 0.6
		_arc_to = Vector3(cos(ang_b) * (RING_RADIUS - 3.0), sin(ang_b) * (RING_RADIUS - 3.0), z_b)
		_arc_life = _rng.randf_range(0.06, 0.16)
		_arc_light.position = (_arc_from + _arc_to) * 0.5
		_arc_light.light_energy = 14.0
	_arc_mesh.clear_surfaces()
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var points: Array[Vector3] = [_arc_from]
	var n := 14
	var span := _arc_from.distance_to(_arc_to)
	for i in range(1, n):
		var t := float(i) / n
		var p := _arc_from.lerp(_arc_to, t)
		p += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * span * 0.06
		points.append(p)
	points.append(_arc_to)
	for i in points.size() - 1:
		_arc_mesh.surface_add_vertex(points[i])
		_arc_mesh.surface_add_vertex(points[i + 1])
		# A second, offset strand thickens it.
		_arc_mesh.surface_add_vertex(points[i] + Vector3(0.3, 0.3, 0.0))
		_arc_mesh.surface_add_vertex(points[i + 1] + Vector3(0.3, 0.3, 0.0))
	_arc_mesh.surface_end()


func _shed_plate(ring: Node3D) -> void:
	var node := MeshInstance3D.new()
	node.mesh = _plate_mesh
	node.material_override = _hull_mat
	node.scale = Vector3(RING_RADIUS * TAU / SEGMENTS * 0.9, 5.5, 9.0)
	var ang := _rng.randf() * TAU
	node.position = ring.position + Vector3(cos(ang), sin(ang), 0.0) * RING_RADIUS
	node.rotation.z = ang - PI * 0.5
	add_child(node)
	_free_plates.append({
		"node": node,
		"vel": Vector3(-cos(ang), -sin(ang), 0.0) * _rng.randf_range(4.0, 12.0),
		"axis": Vector3(_rng.randf(), _rng.randf(), _rng.randf()).normalized(),
		"spin": _rng.randf_range(1.0, 3.0),
	})


## The gate lurches: the wall floods, arcs come fast, a big flash.
func surge(strength: float = 1.0) -> void:
	_surge = clampf(maxf(_surge, strength), 0.0, 1.0)
	_arc_timer = 0.0


## The final throw out of the gate: everything accelerates into the white-out.
func exit_burst(duration: float) -> void:
	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_property(self, "_speed_scale", 6.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_surge = 1.0
	if _bore_mat != null:
		var bright := create_tween().set_ignore_time_scale(true)
		bright.tween_method(func(v: float) -> void: _bore_mat.set_shader_parameter("brightness", v), 1.0, 4.0, duration)
