extends MeshInstance3D

## Scan Composition's bubble (Abe, 2026-10-04): a clear bubble grows out of
## the ship's centre to the edge of what the scan covers, holds a moment so
## you can see the area, then fades to nothing. Clear inside; only a faint
## glassy rim (brighter where you look along its surface) shows its shape,
## like a soap bubble, from outside or from within.

const GROW_S := 1.6
const HOLD_S := 0.5
const FADE_S := 1.2
const RIM_COLOUR := Color(0.62, 0.86, 1.0)

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 rim_colour = vec3(0.62, 0.86, 1.0);
uniform float strength = 1.0;
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 4.0);
	// A whisper of tint across the face so the bubble reads as a surface.
	ALBEDO = rim_colour;
	ALPHA = clamp((rim * 0.9 + 0.012) * strength, 0.0, 1.0);
}
"""

static var _shader: Shader = null


## A bubble at `at` growing to `radius`, under `parent`.
static func spawn(parent: Node, at: Vector3, radius: float) -> Node3D:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var bubble = load("res://scripts/effects/ScanBubble.gd").new()
	bubble.name = "OreScanBubble"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
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
	var tween: Tween = bubble.create_tween()
	tween.tween_property(bubble, "scale", Vector3.ONE * radius, GROW_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(HOLD_S)
	tween.tween_method(func(v: float): mat.set_shader_parameter("strength", v), 1.0, 0.0, FADE_S).set_ease(Tween.EASE_IN)
	tween.tween_callback(bubble.queue_free)
	return bubble
