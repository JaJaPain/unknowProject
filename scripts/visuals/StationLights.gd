extends Node3D

## Running lights on a station (next_level_plan P5): red and green side
## markers, white strobes top and bottom, and a slow amber pulse at the
## docking berth. Sized from the station model's bounds, so it fits any hull.
##
## Each light is carried by a small beacon drone holding station off the hull
## (Abe, 2026-09-30: the bare dots "come from nowhere"). The flash grows out of
## the drone's centre to full size, holds, and shrinks back into it, so the
## drone shows between flashes. Drones are plain black primitives for now.

const RED := Color(1.0, 0.18, 0.12)
const GREEN := Color(0.2, 1.0, 0.35)
const WHITE := Color(0.95, 0.97, 1.0)
const AMBER := Color(1.0, 0.7, 0.25)

## Flash timing, seconds: grow out, hold, shrink back; dark for the rest.
const MARKER_CYCLE := 1.6
const MARKER_GROW := 0.18
const MARKER_HOLD := 0.75
const MARKER_SHRINK := 0.22
const STROBE_CYCLE := 2.0
const STROBE_GROW := 0.05
const STROBE_HOLD := 0.05
const STROBE_SHRINK := 0.07

## [{"drone": Node3D, "light": Node3D, "kind": "marker"|"strobe"|"berth", "base": Vector3, "seed": float}]
var _beacons: Array[Dictionary] = []
var _berth_light: OmniLight3D
var _t := 0.0
static var _hull_mat: StandardMaterial3D


## Adds lights fitted to `station`'s visible meshes.
static func attach(station: Node3D) -> void:
	if station == null or station.get_node_or_null("StationLights") != null:
		return
	var box := _bounds(station)
	if box.size.length() < 1.0:
		return
	var lights = load("res://scripts/visuals/StationLights.gd").new()
	lights.name = "StationLights"
	station.add_child(lights)
	lights._build(box, station)


static func _bounds(station: Node3D) -> AABB:
	var inv := station.global_transform.affine_inverse()
	var merged := AABB()
	var first := true
	for mesh in station.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var local := (inv * m.global_transform) * m.get_aabb()
		merged = local if first else merged.merge(local)
		first = false
	return merged


func _build(box: AABB, station: Node3D) -> void:
	if station.has_method("is_berthed") and bool(station.call("is_berthed")):
		_build_main_station(box, station)
		return
	var c := box.get_center()
	var e := box.size * 0.5
	var dot := maxf(1.5, box.size.length() * 0.012)
	# Side markers: red to port (-X), green to starboard (+X).
	_beacon(c + Vector3(-e.x, 0, 0), RED, dot, "marker")
	_beacon(c + Vector3(e.x, 0, 0), GREEN, dot, "marker")
	_beacon(c + Vector3(-e.x * 0.7, e.y * 0.5, e.z * 0.7), RED, dot * 0.7, "marker")
	_beacon(c + Vector3(e.x * 0.7, e.y * 0.5, -e.z * 0.7), GREEN, dot * 0.7, "marker")
	# White strobes top and bottom.
	_beacon(c + Vector3(0, e.y, 0), WHITE, dot * 1.2, "strobe")
	_beacon(c + Vector3(0, -e.y, 0), WHITE, dot * 1.2, "strobe")
	# The berth glows amber where ships come in.
	var berth := c
	if station.has_method("get_docking_position"):
		berth = station.to_local(station.get_docking_position(station.global_position + Vector3(0, 0, 1000)))
	_berth_light = OmniLight3D.new()
	_berth_light.light_color = AMBER
	_berth_light.omni_range = maxf(30.0, box.size.length() * 0.15)
	_berth_light.light_energy = 1.5
	_berth_light.position = berth
	add_child(_berth_light)
	_beacon(berth, AMBER, dot, "berth")


## The kilometre-scale main stations (Abe, 2026-10-04: the drone lights from
## the old station, around the new ones too). Drones stay ship-sized; there
## are more of them: navigation markers round the rim (red to port, green to
## starboard), strobes top and bottom, and a line of amber beacons down the
## docking lane from the approach sphere to the berth, with the berth lit.
const MAIN_DOT := 10.0
const MAIN_RIM_MARKERS := 8
const MAIN_LANE_BEACONS := 4


func _build_main_station(box: AABB, station: Node3D) -> void:
	var c := box.get_center()
	var e := box.size * 0.5
	var rim := maxf(e.x, e.z) * 0.92
	for i in MAIN_RIM_MARKERS:
		var a := TAU * float(i) / float(MAIN_RIM_MARKERS)
		var at := c + Vector3(cos(a) * rim, 0.0, sin(a) * rim)
		_beacon(at, RED if at.x < c.x else GREEN, MAIN_DOT, "marker")
	_beacon(c + Vector3(0, e.y + 40.0, 0), WHITE, MAIN_DOT * 1.4, "strobe")
	_beacon(c + Vector3(0, -e.y - 40.0, 0), WHITE, MAIN_DOT * 1.4, "strobe")
	# The docking lane, in the station's own space.
	var berth := station.to_local(station.call("berth_position"))
	var entry := station.to_local(station.call("lane_entry_position"))
	for i in MAIN_LANE_BEACONS:
		var t := (float(i) + 0.5) / float(MAIN_LANE_BEACONS)
		_beacon(berth.lerp(entry, t) + Vector3.UP * 30.0, AMBER, MAIN_DOT * 0.8, "berth")
	_berth_light = OmniLight3D.new()
	_berth_light.light_color = AMBER
	_berth_light.omni_range = 150.0
	_berth_light.light_energy = 1.0
	_berth_light.position = berth
	add_child(_berth_light)


## A beacon drone at `pos` carrying a light of radius `size`.
func _beacon(pos: Vector3, colour: Color, size: float, kind: String) -> void:
	var drone := _build_drone(size * 0.45)
	drone.position = pos
	add_child(drone)
	var light := _light_sphere(colour, size)
	drone.add_child(light)
	light.scale = Vector3.ONE * 0.001
	_beacons.append({"drone": drone, "light": light, "kind": kind, "base": pos, "seed": randf() * TAU})


## A small drone from primitives, about `r` in radius: a squat body, a ring
## round its middle, three arms with pods, and an antenna. Black for now.
func _build_drone(r: float) -> Node3D:
	if _hull_mat == null:
		_hull_mat = StandardMaterial3D.new()
		_hull_mat.albedo_color = Color(0.07, 0.07, 0.08)
		_hull_mat.metallic = 0.4
		_hull_mat.roughness = 0.55
	var drone := Node3D.new()
	var body := SphereMesh.new()
	body.radius = r
	body.height = r * 1.3
	body.radial_segments = 12
	body.rings = 6
	_part(drone, body, Vector3.ZERO, Vector3.ZERO)
	var ring := TorusMesh.new()
	ring.inner_radius = r * 1.05
	ring.outer_radius = r * 1.3
	ring.rings = 16
	ring.ring_segments = 6
	_part(drone, ring, Vector3.ZERO, Vector3.ZERO)
	for i in 3:
		var ang := TAU * i / 3.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var arm := BoxMesh.new()
		arm.size = Vector3(r * 1.1, r * 0.14, r * 0.14)
		_part(drone, arm, dir * r * 1.75, Vector3(0.0, -ang, 0.0))
		var pod := BoxMesh.new()
		pod.size = Vector3(r * 0.4, r * 0.3, r * 0.4)
		_part(drone, pod, dir * r * 2.3, Vector3(0.0, -ang, 0.0))
	var antenna := CylinderMesh.new()
	antenna.top_radius = r * 0.04
	antenna.bottom_radius = r * 0.07
	antenna.height = r * 1.4
	antenna.radial_segments = 6
	_part(drone, antenna, Vector3(0.0, r * 1.2, 0.0), Vector3.ZERO)
	return drone


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _hull_mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)


## The flash, styled like the player's orbiting drones: a small glossy
## glowing core, a soft see-through halo (shaders/beacon_halo.gdshader) and a
## real light that spills onto the drone and the hull. Scaled 0..1 by the
## flash envelope; the light's energy follows it.
func _light_sphere(colour: Color, size: float) -> Node3D:
	var flash := Node3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = size * 0.32
	core_mesh.height = size * 0.64
	core_mesh.radial_segments = 16
	core_mesh.rings = 8
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = colour
	core_mat.metallic = 0.9
	core_mat.roughness = 0.15
	core_mat.emission_enabled = true
	core_mat.emission = colour
	core_mat.emission_energy_multiplier = 3.0
	core_mesh.material = core_mat
	var core := MeshInstance3D.new()
	core.mesh = core_mesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.add_child(core)
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = size
	halo_mesh.height = size * 2.0
	halo_mesh.radial_segments = 24
	halo_mesh.rings = 12
	var halo_mat := ShaderMaterial.new()
	halo_mat.shader = load("res://shaders/beacon_halo.gdshader")
	halo_mat.set_shader_parameter("glow_color", colour)
	halo_mesh.material = halo_mat
	var halo := MeshInstance3D.new()
	halo.mesh = halo_mesh
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.add_child(halo)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = colour
	lamp.omni_range = size * 9.0
	lamp.light_energy = 0.0
	lamp.set_meta("full_energy", 7.0)
	flash.add_child(lamp)
	return flash


## 0..1 light size through one cycle: grow out, hold, shrink back, dark.
static func _envelope(t: float, grow: float, hold: float, shrink: float) -> float:
	if t < grow:
		var k := t / grow
		return 1.0 - (1.0 - k) * (1.0 - k)  # ease out
	if t < grow + hold:
		return 1.0
	if t < grow + hold + shrink:
		var k := (t - grow - hold) / shrink
		return 1.0 - k * k  # ease in
	return 0.0


func _process(delta: float) -> void:
	_t += delta
	for b in _beacons:
		var drone: Node3D = b["drone"]
		var light: Node3D = b["light"]
		var offset: float = b["seed"]
		# Holding station: a slow bob and turn.
		drone.position = (b["base"] as Vector3) + Vector3(0.0, sin(_t * 0.9 + offset) * 0.25, 0.0)
		drone.rotation.y = _t * 0.3 + offset
		var s := 0.0
		match str(b["kind"]):
			"strobe":
				# A quick double flash every cycle.
				var phase := fmod(_t, STROBE_CYCLE)
				s = maxf(_envelope(phase, STROBE_GROW, STROBE_HOLD, STROBE_SHRINK),
					_envelope(phase - 0.22, STROBE_GROW, STROBE_HOLD, STROBE_SHRINK) if phase >= 0.22 else 0.0)
			"berth":
				s = 0.6 + 0.4 * (0.5 + 0.5 * sin(_t * 1.8))
			_:
				s = _envelope(fmod(_t, MARKER_CYCLE), MARKER_GROW, MARKER_HOLD, MARKER_SHRINK)
		light.visible = s > 0.01
		light.scale = Vector3.ONE * maxf(s, 0.001)
		var lamp := light.get_node("Lamp") as OmniLight3D
		lamp.light_energy = float(lamp.get_meta("full_energy")) * s
	if _berth_light:
		_berth_light.light_energy = 1.0 + 0.8 * (0.5 + 0.5 * sin(_t * 1.8))
