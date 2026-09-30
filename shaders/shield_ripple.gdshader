shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

// A shield shell hit: bright at the silhouette (fresnel), clear in the middle,
// plus a hot spot around the contact point. `fade` goes 1 -> 0 over the hit.
uniform vec4 tint : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float fade = 1.0;
uniform vec3 contact_dir = vec3(0.0, 0.0, 1.0);

varying vec3 local_normal;

void vertex() {
	local_normal = normalize(VERTEX);
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float spot = pow(max(dot(local_normal, normalize(contact_dir)), 0.0), 12.0);
	float a = (rim * 0.9 + spot * 1.4) * fade;
	ALBEDO = tint.rgb * a;
}
