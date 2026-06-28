shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 plume_color : source_color = vec4(0.25, 0.8, 1.0, 1.0);
uniform float alpha = 0.55;
uniform float edge_power = 1.4;

void fragment() {
	float axial = clamp(UV.y, 0.0, 1.0);
	float radial = abs(UV.x - 0.5) * 2.0;
	float tail_fade = smoothstep(1.0, 0.12, axial);
	float root_fade = smoothstep(0.0, 0.12, axial);
	float center = pow(1.0 - clamp(radial, 0.0, 1.0), edge_power);
	vec3 color = plume_color.rgb * mix(0.75, 1.35, center);
	ALBEDO = color;
	EMISSION = color;
	ALPHA = alpha * tail_fade * root_fade * mix(0.28, 1.0, center);
}
