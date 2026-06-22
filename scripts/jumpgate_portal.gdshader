shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 deep_color : source_color = vec4(0.01, 0.10, 0.32, 1.0);
uniform vec4 crest_color : source_color = vec4(0.10, 0.80, 1.0, 1.0);
uniform vec4 foam_color : source_color = vec4(0.80, 0.98, 1.0, 1.0);
uniform float animation_speed : hint_range(0.0, 3.0) = 0.5;
uniform float wave_scale : hint_range(1.0, 16.0) = 5.0;
uniform float caustic_sharpness : hint_range(1.0, 8.0) = 3.0;
uniform float edge_softness : hint_range(0.001, 0.3) = 0.07;
uniform float charge : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.02 + vec2(37.1, 17.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float radius = length(centered_uv);
	float t = TIME * animation_speed;

	// Domain-warped flowing water: two scrolling FBM fields warp a third.
	vec2 p = UV * wave_scale;
	vec2 warp = vec2(
		fbm(p + vec2(t * 0.6, t * 0.35)),
		fbm(p + vec2(-t * 0.45, t * 0.5) + 5.2)
	);
	float surface = fbm(p + warp * 1.8 + vec2(t * 0.25, -t * 0.2));

	// Ridged "caustic" highlights — bright thin veins like light through water.
	float caustic = 1.0 - abs(surface * 2.0 - 1.0);
	caustic = pow(caustic, caustic_sharpness);

	// Color: deep water -> cyan crest by surface height, foam veins on top.
	vec3 color = mix(deep_color.rgb, crest_color.rgb, smoothstep(0.25, 0.85, surface));
	color += foam_color.rgb * caustic * 0.9;

	// Soft circular portal mask + gentle center glow + bright rim.
	float circular_mask = 1.0 - smoothstep(1.0 - edge_softness, 1.0, radius);
	float center_glow = (1.0 - smoothstep(0.0, 0.95, radius)) * 0.25;
	float rim = smoothstep(0.7, 0.98, radius) * circular_mask;
	color += crest_color.rgb * (center_glow + rim * 1.1);

	// Charge ramps brightness during jump spool.
	color *= 1.0 + charge * 2.2;

	ALBEDO = color;
	EMISSION = color * (1.5 + charge * 3.5);
	ALPHA = circular_mask * (0.5 + surface * 0.35 + caustic * 0.4);
}
