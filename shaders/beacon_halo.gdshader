shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

// Soft glow round a station beacon: brightest where you look straight through
// the middle, fading to nothing at the rim, added on top of what's behind it
// (so the drone and hull show through). Same feel as the player's orbiting
// drones under bloom.

uniform vec4 glow_color : source_color = vec4(0.2, 1.0, 0.35, 1.0);
uniform float intensity = 0.9;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float glow = pow(facing, 4.0);
	ALBEDO = glow_color.rgb * glow * intensity;
}
