extends Node3D

## Running lights on a station (next_level_plan P5): red and green side
## markers, white strobes top and bottom, and a slow amber pulse at the
## docking berth. Sized from the station model's bounds, so it fits any hull.
## Emissive dots with glow, plus a couple of real lights for the berth area.

const RED := Color(1.0, 0.18, 0.12)
const GREEN := Color(0.2, 1.0, 0.35)
const WHITE := Color(0.95, 0.97, 1.0)
const AMBER := Color(1.0, 0.7, 0.25)

var _strobes: Array[MeshInstance3D] = []
var _markers: Array[MeshInstance3D] = []
var _berth_light: OmniLight3D
var _t := 0.0


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
	var c := box.get_center()
	var e := box.size * 0.5
	var dot := maxf(1.5, box.size.length() * 0.012)
	# Side markers: red to port (-X), green to starboard (+X).
	_markers.append(_dot(c + Vector3(-e.x, 0, 0), RED, dot))
	_markers.append(_dot(c + Vector3(e.x, 0, 0), GREEN, dot))
	_markers.append(_dot(c + Vector3(-e.x * 0.7, e.y * 0.5, e.z * 0.7), RED, dot * 0.7))
	_markers.append(_dot(c + Vector3(e.x * 0.7, e.y * 0.5, -e.z * 0.7), GREEN, dot * 0.7))
	# White strobes top and bottom.
	_strobes.append(_dot(c + Vector3(0, e.y, 0), WHITE, dot * 1.2))
	_strobes.append(_dot(c + Vector3(0, -e.y, 0), WHITE, dot * 1.2))
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
	_dot(berth, AMBER, dot)


func _dot(pos: Vector3, colour: Color, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 4.0
	sphere.material = mat
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_t += delta
	# Strobes: a quick double flash every 2 s.
	var phase := fmod(_t, 2.0)
	var on := phase < 0.08 or (phase > 0.22 and phase < 0.3)
	for s in _strobes:
		s.visible = on
	# Side markers: a slow steady blink.
	var marker_on := fmod(_t, 1.6) < 1.1
	for m in _markers:
		m.visible = marker_on
	if _berth_light:
		_berth_light.light_energy = 1.0 + 0.8 * (0.5 + 0.5 * sin(_t * 1.8))
