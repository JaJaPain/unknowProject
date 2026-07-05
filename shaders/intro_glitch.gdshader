shader_type canvas_item;

// Intro cinematic glitch (docs/plan_intro_cinematic.md): UV displacement in
// noise bands + chromatic aberration + scanline flicker + white-out, all
// driven by `intensity` (0..1) and `white_out` (0..1) which the sequence
// tweens. On a full-rect ColorRect in a high CanvasLayer.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float white_out : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

float rnd(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Horizontal tear bands: more, thinner bands as intensity climbs.
	float band = floor(uv.y * mix(9.0, 44.0, intensity));
	float band_roll = rnd(vec2(band, floor(TIME * 9.0)));
	float shift = (rnd(vec2(band, floor(TIME * 24.0))) - 0.5) * 0.3 * intensity;
	uv.x = fract(uv.x + shift * step(0.55, band_roll));
	// Occasional whole-frame horizontal jump.
	uv.x = fract(uv.x + step(0.92, rnd(vec2(floor(TIME * 13.0), 7.0))) * 0.06 * intensity);
	// Chromatic aberration.
	float ab = 0.014 * intensity;
	float r = texture(screen_tex, uv + vec2(ab, 0.0)).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - vec2(ab, 0.0)).b;
	vec3 col = vec3(r, g, b);
	// Scanline flicker + noise sparkle.
	col *= 1.0 - 0.16 * intensity * sin(uv.y * 640.0 + TIME * 60.0);
	col += (rnd(uv * vec2(917.0, 533.0) + vec2(TIME)) - 0.5) * 0.22 * intensity;
	col = mix(col, vec3(1.0), white_out);
	COLOR = vec4(col, clamp(max(intensity * 1.1, white_out), 0.0, 1.0));
}
