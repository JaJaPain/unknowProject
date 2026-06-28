shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 plume_color : source_color = vec4(0.25, 0.8, 1.0, 1.0);
uniform vec4 tip_color : source_color = vec4(1.0, 0.86, 0.52, 1.0);
uniform float alpha = 0.55;
uniform float edge_power = 1.4;
uniform float tip_strength = 0.25;

void fragment() {
	float axial = clamp(UV.y, 0.0, 1.0);
	float radial = abs(UV.x - 0.5) * 2.0;
	float tail_fade = smoothstep(1.0, 0.12, axial);
	float root_fade = smoothstep(0.0, 0.12, axial);
	float center = pow(1.0 - clamp(radial, 0.0, 1.0), edge_power);
	float warm_tip = smoothstep(0.52, 0.88, axial) * tail_fade * pow(1.0 - clamp(radial, 0.0, 1.0), 0.65);
	vec3 blue_body = plume_color.rgb * mix(0.75, 1.35, center);
	vec3 color = mix(blue_body, tip_color.rgb * 1.25, warm_tip * tip_strength);
	ALBEDO = color;
	EMISSION = color;
	ALPHA = alpha * tail_fade * root_fade * mix(0.28, 1.0, center + warm_tip * 0.25);
}
