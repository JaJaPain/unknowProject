shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, transparent;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.05;
uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.008;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec4 rim_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);

void fragment() {
	// NORMAL is view-space normal. NORMAL.xy gives us screen-space tangent direction
	vec2 offset = NORMAL.xy * refraction_strength;
	
	// Chromatic aberration offsets
	vec2 offset_r = NORMAL.xy * (refraction_strength + chromatic_aberration);
	vec2 offset_b = NORMAL.xy * (refraction_strength - chromatic_aberration);
	
	float r = texture(screen_texture, SCREEN_UV + offset_r).r;
	float g = texture(screen_texture, SCREEN_UV + offset).g;
	float b = texture(screen_texture, SCREEN_UV + offset_b).b;
	
	vec3 distorted = vec3(r, g, b);
	
	// Fresnel rim glow
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.5);
	vec3 final_color = mix(distorted, rim_color.rgb, fresnel * alpha * 0.7);
	
	ALBEDO = final_color;
	ALPHA = alpha;
}
