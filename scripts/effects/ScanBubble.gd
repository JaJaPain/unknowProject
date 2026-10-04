extends MeshInstance3D

## Scan Composition's bubble (Abe, 2026-10-04): a clear bubble grows out of
## the ship's centre to the edge of what the scan covers, holds a moment so
## you can see the area, then fades to nothing.
##
## Playtest 2026-10-04 c finding 5: it looked full-size at once and its edge
## couldn't be seen. The camera is always deep inside a 320 m bubble, where a
## soap-bubble rim (which shows only when you look along the surface) is
## invisible. So the bubble now:
## - grows steadily (GROW_S, eased at both ends) so the front visibly travels;
## - carries a faint grid on its shell, seen from inside or out;
## - has a ring where it cuts the ship's level, sweeping out over the belt;
## - makes each rock flash as the front reaches it.

## Growth time for the largest bubble (OreScan.RANGE); smaller ones are
## quicker, never under GROW_MIN_S, so the front is always seen to travel.
const GROW_S := 3.5
const GROW_MIN_S := 2.0
const HOLD_S := 0.6
const FADE_S := 1.2
const RIM_COLOUR := Color(0.62, 0.86, 1.0)
const ROCK_FLASH := Color(0.45, 0.85, 1.0, 0.85)
const ROCK_FLASH_S := 0.7

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 rim_colour = vec3(0.62, 0.86, 1.0);
uniform float strength = 1.0;
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 4.0);
	// A faint grid on the shell (24 meridians, 12 parallels): visible from
	// inside, where the rim isn't.
	vec2 g = abs(fract(UV * vec2(24.0, 12.0)) - 0.5);
	float line_w = fwidth(UV.x * 24.0) * 1.2;
	float grid = 1.0 - smoothstep(0.0, line_w, min(g.x, g.y * 2.0) - 0.0);
	ALBEDO = rim_colour;
	ALPHA = clamp((rim * 0.8 + grid * 0.22 + 0.01) * strength, 0.0, 1.0);
}
"""

static var _shader: Shader = null

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _rocks: Array = []  # [{"node": rock, "dist": float}], nearest first


## A bubble at `at` growing to `radius`, under `parent`. `rocks` (scanned
## asteroids) flash as the front reaches them.
static func spawn(parent: Node, at: Vector3, radius: float, rocks: Array = []) -> Node3D:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var bubble = load("res://scripts/effects/ScanBubble.gd").new()
	bubble.name = "OreScanBubble"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	bubble.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("rim_colour", RIM_COLOUR)
	mat.set_shader_parameter("strength", 1.0)
	bubble.material_override = mat
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(bubble)
	bubble.global_position = at
	bubble.scale = Vector3.ONE * 2.0
	bubble._build_ring()
	for rock in rocks:
		if rock is Node3D and is_instance_valid(rock):
			bubble._rocks.append({"node": rock, "dist": (rock as Node3D).global_position.distance_to(at)})
	bubble._rocks.sort_custom(func(a, b) -> bool: return float(a["dist"]) < float(b["dist"]))
	var tween: Tween = bubble.create_tween()
	var grow_s := clampf(GROW_S * radius / 1600.0, GROW_MIN_S, GROW_S)
	tween.tween_property(bubble, "scale", Vector3.ONE * radius, grow_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(HOLD_S)
	tween.tween_method(func(v: float):
		mat.set_shader_parameter("strength", v)
		bubble._ring_mat.albedo_color.a = 0.55 * v, 1.0, 0.0, FADE_S).set_ease(Tween.EASE_IN)
	tween.tween_callback(bubble.queue_free)
	return bubble


## The ring where the bubble meets the ship's level: a thin torus that grows
## with the bubble (a child, so it scales with it).
func _build_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.985
	torus.outer_radius = 1.0
	torus.rings = 128
	torus.ring_segments = 6
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = Color(RIM_COLOUR.r, RIM_COLOUR.g, RIM_COLOUR.b, 0.55)
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring = MeshInstance3D.new()
	_ring.name = "ScanRing"
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _process(_delta: float) -> void:
	# Flash every rock the front has reached since last frame.
	var reach := scale.x
	while not _rocks.is_empty() and float(_rocks[0]["dist"]) <= reach:
		var rock = _rocks.pop_front()["node"]
		if rock != null and is_instance_valid(rock):
			_flash_rock(rock as Node3D)


## A brief cyan glow over the rock, fading out.
func _flash_rock(rock: Node3D) -> void:
	var mesh := rock.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = ROCK_FLASH
	mesh.material_overlay = glow
	var t := mesh.create_tween()
	t.tween_property(glow, "albedo_color:a", 0.0, ROCK_FLASH_S).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		if is_instance_valid(mesh) and mesh.material_overlay == glow:
			mesh.material_overlay = null)
