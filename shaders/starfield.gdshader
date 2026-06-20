shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;

uniform float star_density : hint_range(0.01, 0.3) = 0.04;
uniform float seed_offset : hint_range(0.0, 1000.0) = 0.0;
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

			float star_lum = 0.0;
			float galaxy_chance = hash21(neighbor * 10.31 + 900.0);
			bool is_galaxy = galaxy_chance < 0.008;

			if (is_galaxy) {
				// Distant galaxy: small fuzzy elongated smudge
				float angle = hash21(neighbor * 11.07 + 950.0) * 3.14159;
				float cos_a = cos(angle);
				float sin_a = sin(angle);
				vec2 rotated = vec2(
					diff.x * cos_a + diff.y * sin_a,
					-diff.x * sin_a + diff.y * cos_a
				);
				float stretch = 1.6 + hash21(neighbor * 11.89 + 970.0) * 1.0;
				float galaxy_dist = length(vec2(rotated.x, rotated.y * stretch));
				float galaxy_size = 0.2 + hash21(neighbor * 12.43 + 990.0) * 0.12;
				float galaxy_bright = 0.2 + hash21(neighbor * 13.17 + 1010.0) * 0.15;

				// Soft fuzzy core
				float core = smoothstep(galaxy_size, 0.0, galaxy_dist);
				core *= core;
				star_lum = core * galaxy_bright;
			} else {
				// Brightness: cube the random to skew most stars dim, few bright
				float raw_mag = hash21(neighbor * 2.53 + 200.0);
				float star_mag = raw_mag * raw_mag * raw_mag;
				star_mag = mix(0.15, 1.0, star_mag);

				// Size: most stars are tiny pinpoints, brighter ones are slightly larger
				float size_rand = hash21(neighbor * 3.17 + 350.0);
				float base_size = 0.08 + size_rand * 0.06;
				float star_size = base_size + star_mag * 0.08;

				// Core point
				float point = smoothstep(star_size, 0.0, dist);
				star_lum = point * star_mag;

				// Soft glow halo on brighter stars
				if (star_mag > 0.55) {
					float glow_radius = star_size + 0.12 + star_mag * 0.1;
					float glow = smoothstep(glow_radius, star_size * 0.5, dist);
					glow *= glow;
					star_lum += glow * star_mag * 0.25;
				}

				// ~10% of stars twinkle
				float twinkle_chance = hash21(neighbor * 4.37 + 300.0);
				if (twinkle_chance < 0.1) {
					float rate1 = 0.15 + hash21(neighbor * 5.91 + 400.0) * 0.35;
					float rate2 = 0.08 + hash21(neighbor * 6.73 + 500.0) * 0.2;
					float phase1 = hash21(neighbor * 7.19 + 600.0) * 62.83;
					float phase2 = hash21(neighbor * 8.41 + 700.0) * 62.83;
					float wave1 = sin(TIME * rate1 + phase1);
					float wave2 = sin(TIME * rate2 + phase2);
					float combined = (wave1 * 0.6 + wave2 * 0.4);
					float depth = 0.3 + hash21(neighbor * 9.53 + 800.0) * 0.65;
					star_lum *= 1.0 - depth * (combined * 0.5 + 0.5);
				}
			}

			lum += star_lum;
		}
	}

	ALBEDO = tint * lum;
	ALPHA = clamp(lum, 0.0, 1.0);
}
