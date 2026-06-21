shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.0, 5.0) = 2.2;
uniform vec4 blueshift_color : source_color = vec4(0.12, 0.72, 1.0, 1.0);
uniform vec4 redshift_color : source_color = vec4(0.85, 0.08, 0.28, 1.0);

float noise(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

float smooth_noise(vec2 uv) {
	vec2 lv = fract(uv);
	vec2 id = floor(uv);
	lv = lv * lv * (3.0 - 2.0 * lv);
	float bl = noise(id);
	float br = noise(id + vec2(1.0, 0.0));
	float tl = noise(id + vec2(0.0, 1.0));
	float tr = noise(id + vec2(1.0, 1.0));
	float b = mix(bl, br, lv.x);
	float t = mix(tl, tr, lv.x);
	return mix(b, t, lv.y);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float radius = length(uv);
	float angle = atan(uv.y, uv.x);
	vec2 polar_uv = vec2(radius * 8.0 - TIME * speed, angle / 3.14159265);
	float n1 = smooth_noise(polar_uv * 2.0 + vec2(0.0, polar_uv.x * 0.4));
	float n2 = smooth_noise(polar_uv * 4.0 - vec2(TIME * speed * 0.5, polar_uv.x * 0.2));
	float combined_noise = mix(n1, n2, 0.5);
	vec3 tunnel_color = mix(redshift_color.rgb, blueshift_color.rgb, smoothstep(0.1, 0.45, radius));
	tunnel_color += vec3(1.0, 1.0, 1.0) * combined_noise * (1.0 - smoothstep(0.05, 0.25, radius));
	float alpha = intensity * smoothstep(0.0, 0.2, radius);
	float full_coverage = smoothstep(0.85, 1.0, intensity);
	COLOR = vec4(tunnel_color * intensity * (0.4 + combined_noise * 0.6), max(alpha, full_coverage));
}
