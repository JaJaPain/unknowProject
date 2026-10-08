extends Node3D

## The twin wreck field as a place in ordinary play (docs/wreck_field_event_plan_2026_10_07.md):
## ChatGPT's two broken ships and their debris, ringed by a radiation zone
## the ship can't safely enter. Four scan points sit just outside it; the
## hulls are a drone-dive wreck from the zone's edge. WreckFieldEvent owns
## the story; this node is the place.

signal zone_entered
signal zone_left

const MODEL_PATH := "res://assets/landmarks/twin_wreck_field_v3_batched.glb"
## The radiation zone round the field's centre (metres). The hulls and the
## thick of the debris are inside it.
const ZONE_RADIUS := 1550.0
## Scan points sit this far outside the zone's edge.
const SCAN_POINT_MARGIN := 150.0
## Hull damage per second inside the zone, as a share of the ship's max hull.
const RADIATION_SHARE_PER_S := 0.03
## The scan points, in order round the field: id, name, angle (degrees).
const SCAN_POINTS := [
	{"id": "bow", "name": "Bow section", "angle": 35.0},
	{"id": "stern", "name": "Stern section", "angle": 125.0},
	{"id": "decks", "name": "Deck modules", "angle": 215.0},
	{"id": "radiators", "name": "Radiator wings", "angle": 305.0},
]

var display_name := "Twin wrecks"
var _inside := false
var _tick := 0.0
var _points: Dictionary = {}


func _ready() -> void:
	add_to_group("wreck_field")
	# The hulls are a drone dive, launched from the zone's edge.
	add_to_group("derelict_hull")
	set_meta("dive_radius", ZONE_RADIUS)
	if ResourceLoader.exists(MODEL_PATH):
		var scene := load(MODEL_PATH) as PackedScene
		if scene != null:
			var model := scene.instantiate() as Node3D
			model.name = "Model"
			add_child(model)
			for anim in model.find_children("*", "AnimationPlayer", true, false):
				var player := anim as AnimationPlayer
				var names := player.get_animation_list()
				if not names.is_empty():
					player.get_animation(names[0]).loop_mode = Animation.LOOP_LINEAR
					player.play(names[0])
	_add_lights()
	_add_zone_shell()
	for p in SCAN_POINTS:
		_add_scan_point(p)
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.active_system_entities.append(self)
		gs.entities_changed.emit()


func _exit_tree() -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.active_system_entities.erase(self)
		for p in _points.values():
			gs.active_system_entities.erase(p)
		gs.entities_changed.emit()


## Fly to stops outside the zone, never in it.
func approach_stop_distance() -> float:
	return ZONE_RADIUS + SCAN_POINT_MARGIN


func radius() -> float:
	return ZONE_RADIUS


## The scan point node by id (bow, stern, decks, radiators), or null.
func scan_point(id: String) -> Node3D:
	return _points.get(id, null)


func scan_point_ids() -> Array:
	return SCAN_POINTS.map(func(p): return str(p["id"]))


## Marks a scan point done: its light goes out.
func mark_scanned(id: String) -> void:
	var point := scan_point(id)
	if point == null:
		return
	var lamp := point.get_node_or_null("Lamp") as MeshInstance3D
	if lamp != null:
		var mat := lamp.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = 0.4
	point.set("display_name", "%s (scanned)" % str(_point_name(id)))


func _point_name(id: String) -> String:
	for p in SCAN_POINTS:
		if str(p["id"]) == id:
			return str(p["name"])
	return id


func _physics_process(delta: float) -> void:
	var gs := get_node_or_null("/root/GlobalState")
	var player = gs.player if gs != null else null
	if not is_instance_valid(player) or bool(player.get("is_docked")) or bool(player.get("destroyed")):
		return
	var inside: bool = (player as Node3D).global_position.distance_to(global_position) < ZONE_RADIUS
	if inside != _inside:
		_inside = inside
		_tick = 0.0
		if inside:
			zone_entered.emit()
		else:
			zone_left.emit()
	if not inside:
		return
	_tick += delta
	if _tick >= 1.0:
		_tick -= 1.0
		if player.has_method("take_damage"):
			player.take_damage(float(player.get("max_health")) * RADIATION_SHARE_PER_S)


func _add_lights() -> void:
	# Far from any sun: a cold fill from two sides so the hulls read, holding
	# its strength out to its range at this scale.
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.78, 0.86, 1.0)
	fill.omni_range = ZONE_RADIUS * 4.0
	fill.light_energy = 1.3
	fill.omni_attenuation = 0.0
	fill.position = Vector3(0.75, 0.55, 0.9) * ZONE_RADIUS * 1.4
	add_child(fill)
	var back := OmniLight3D.new()
	back.light_color = Color(0.7, 0.8, 1.0)
	back.omni_range = ZONE_RADIUS * 4.0
	back.light_energy = 0.6
	back.omni_attenuation = 0.0
	back.position = Vector3(-0.8, -0.3, -0.7) * ZONE_RADIUS * 1.4
	add_child(back)


## A faint sickly shell marking the zone: seen from outside as a haze round
## the wrecks, from inside as a tint.
func _add_zone_shell() -> void:
	var shell := MeshInstance3D.new()
	shell.name = "RadiationZone"
	var sphere := SphereMesh.new()
	sphere.radius = ZONE_RADIUS
	sphere.height = ZONE_RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	shell.mesh = sphere
	# Only the rim glows (facing away from the eye), so the boundary reads
	# like a bubble's edge and the wrecks stay clear behind it.
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.5, 1.0, 0.45, 1.0);
uniform float strength = 0.22;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 4.0);
	ALBEDO = tint.rgb;
	ALPHA = rim * strength;
}
"""
	mat.shader = shader
	shell.material_override = mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)


func _add_scan_point(p: Dictionary) -> void:
	var point := Node3D.new()
	point.name = "ScanPoint_%s" % str(p["id"])
	point.set_script(load("res://scripts/world/WreckScanPoint.gd"))
	point.set("point_id", str(p["id"]))
	point.set("display_name", "%s (scan)" % str(p["name"]))
	var a := deg_to_rad(float(p["angle"]))
	var r := ZONE_RADIUS + SCAN_POINT_MARGIN
	point.position = Vector3(cos(a) * r, 40.0, sin(a) * r)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var ball := SphereMesh.new()
	ball.radius = 6.0
	ball.height = 12.0
	lamp.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.95, 1.0)
	mat.albedo_color = Color(0.55, 0.95, 1.0)
	mat.emission_energy_multiplier = 4.0
	lamp.material_override = mat
	point.add_child(lamp)
	add_child(point)
	_points[str(p["id"])] = point
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.active_system_entities.append(point)
