shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_add;

uniform sampler2D nebula_texture : source_color, filter_linear_mipmap;
uniform vec3 tint_color : source_color = vec3(0.45, 0.2, 0.7);
uniform float brightness : hint_range(0.0, 1.5) = 0.5;

void fragment() {
	float mask = texture(nebula_texture, UV).r;
	// Power curve to deepen contrast — thin edges fade, dense cores glow
	mask = pow(mask, 1.8);
	// Feather the quad's rectangular borders so the billboard dissolves into
	// empty space instead of showing a hard straight cutoff at its edge.
	vec2 edge = smoothstep(0.0, 0.15, UV) * smoothstep(1.0, 0.85, UV);
	mask *= edge.x * edge.y;
	ALBEDO = tint_color * brightness * mask;
	ALPHA = 1.0;
}
