shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 deep_color : source_color = vec4(0.01, 0.12, 0.38, 1.0);
uniform vec4 crest_color : source_color = vec4(0.12, 0.85, 1.0, 1.0);
uniform float animation_speed : hint_range(0.0, 3.0) = 0.55;
uniform float ripple_density : hint_range(2.0, 30.0) = 12.0;
uniform float edge_softness : hint_range(0.001, 0.2) = 0.055;
uniform float charge : hint_range(0.0, 1.0) = 0.0;

float wave_layer(vec2 point, vec2 direction, float frequency, float phase) {
	return sin(dot(point, direction) * frequency + phase);
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float radius = length(centered_uv);
	float time = TIME * animation_speed;

	float waves = wave_layer(centered_uv, normalize(vec2(1.0, 0.45)), ripple_density, time * 2.1);
	waves += wave_layer(centered_uv, normalize(vec2(-0.35, 1.0)), ripple_density * 1.37, -time * 1.65);
	waves += wave_layer(centered_uv, normalize(vec2(0.7, -1.0)), ripple_density * 0.63, time * 1.2);
	waves = waves / 3.0;

	float radial_ripples = sin(radius * 34.0 - time * 4.5 + waves * 1.8);
	float water_pattern = clamp(0.5 + waves * 0.24 + radial_ripples * 0.18, 0.0, 1.0);
	float circular_mask = 1.0 - smoothstep(1.0 - edge_softness, 1.0, radius);
	float bright_rim = smoothstep(0.72, 0.98, radius) * circular_mask;
	float center_glow = 1.0 - smoothstep(0.0, 0.9, radius);

	vec3 color = mix(deep_color.rgb, crest_color.rgb, water_pattern);
	color += crest_color.rgb * (bright_rim * 1.4 + center_glow * 0.22);
	color *= 1.0 + charge * 2.2;

	ALBEDO = color;
	EMISSION = color * (1.7 + charge * 3.5);
	ALPHA = circular_mask * (0.58 + water_pattern * 0.3);
}
