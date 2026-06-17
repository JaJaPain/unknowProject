shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;

uniform float star_density : hint_range(0.01, 0.3) = 0.04;
uniform float twinkle_speed : hint_range(0.0, 2.0) = 0.4;
uniform float seed_offset : hint_range(0.0, 1000.0) = 0.0;
uniform float brightness_floor : hint_range(0.0, 1.0) = 0.4;
uniform vec3 tint : source_color = vec3(0.9, 0.92, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed_offset);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, hash21(p + 7.23));
}

void fragment() {
	vec2 uv = UV;
	uv.x *= 2.0;
	float grid = 260.0;
	vec2 id = floor(uv * grid);
	float lum = 0.0;

	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			vec2 neighbor = id + vec2(float(dx), float(dy));
			float chance = hash21(neighbor * 1.17);
			if (chance > star_density) continue;

			vec2 star_pos = hash22(neighbor * 3.71 + 100.0);
			vec2 diff = (neighbor + star_pos) - uv * grid;
			float dist = length(diff);

			float star_mag = hash21(neighbor * 2.53 + 200.0);
			star_mag = mix(brightness_floor, 1.0, star_mag);

			float twinkle = sin(TIME * twinkle_speed + star_mag * 62.8) * 0.25 + 0.75;
			float point = smoothstep(0.18, 0.0, dist);
			lum += point * star_mag * twinkle;
		}
	}

	ALBEDO = tint * lum;
	ALPHA = clamp(lum, 0.0, 1.0);
}
