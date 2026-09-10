shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
// driven_speed is animated by script during warp snap-in for acceleration feel
uniform float driven_speed : hint_range(0.0, 20.0) = 2.5;
uniform vec4 blueshift_color : source_color = vec4(0.1, 0.65, 1.0, 1.0);
uniform vec4 redshift_color : source_color = vec4(0.75, 0.05, 0.25, 1.0);
uniform float streak_brightness : hint_range(0.0, 2.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float smooth_noise(vec2 uv) {
	vec2 lv = fract(uv);
	vec2 id = floor(uv);
	lv = lv * lv * (3.0 - 2.0 * lv);
	float bl = hash(id);
	float br = hash(id + vec2(1.0, 0.0));
	float tl = hash(id + vec2(0.0, 1.0));
	float tr = hash(id + vec2(1.0, 1.0));
	return mix(mix(bl, br, lv.x), mix(tl, tr, lv.x), lv.y);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	float radius = length(uv);
	float angle = atan(uv.y, uv.x);

	// ---- Noise cloud layer (background nebula-like gas) ----
	vec2 polar = vec2(radius * 6.0 - TIME * driven_speed, angle / 3.14159265);
	float n1 = smooth_noise(polar * 2.0 + vec2(0.0, polar.x * 0.3));
	float n2 = smooth_noise(polar * 5.0 - vec2(TIME * driven_speed * 0.4, 0.0));
	float cloud = mix(n1, n2, 0.4);

	// ---- Radial streak lanes ----
	// Divide angle space into discrete sectors; each has its own speed seed
	float lane_count = 80.0;
	float lane_id = floor((angle + 3.14159265) / 6.2831853 * lane_count);
	float lane_seed = hash(vec2(lane_id, 0.0));
	float lane_speed = driven_speed * (0.8 + lane_seed * 0.6);
	// Streak: bright leading edge, long tail, moving outward from center
	float streak_phase = fract(radius * (30.0 + lane_seed * 20.0) - TIME * lane_speed);
	float streak = pow(max(0.0, 1.0 - streak_phase * 6.0), 2.0);
	// Only show streaks away from center, fade to zero at center and edge
	streak *= smoothstep(0.04, 0.18, radius) * smoothstep(0.6, 0.35, radius);
	streak *= (0.4 + lane_seed * 0.6); // vary brightness per lane

	// ---- Core bright spot (tunnel vanishing point) ----
	float core = pow(max(0.0, 1.0 - radius * 6.0), 3.0);

	// ---- Color ----
	// Doppler shift: blue at center, red-pink at edges
	vec3 tunnel_color = mix(redshift_color.rgb, blueshift_color.rgb, smoothstep(0.08, 0.42, radius));
	// Streaks are near-white with a blue tint
	vec3 streak_color = mix(vec3(0.6, 0.85, 1.0), vec3(1.0), streak);
	tunnel_color = mix(tunnel_color, streak_color, streak * streak_brightness);
	// Cloud texture adds variation
	tunnel_color += vec3(0.15, 0.3, 0.5) * cloud * (1.0 - smoothstep(0.1, 0.5, radius)) * 0.5;
	// Core glow
	tunnel_color += vec3(0.5, 0.8, 1.0) * core;

	// ---- Alpha ----
	// At full intensity: entire screen covered. At partial: ring from center outward.
	float ring_alpha = intensity * smoothstep(0.0, 0.15, radius);
	float full_coverage = smoothstep(0.8, 1.0, intensity);
	float alpha = max(ring_alpha + core * intensity, full_coverage);

	COLOR = vec4(tunnel_color * intensity, clamp(alpha, 0.0, 1.0));
}
