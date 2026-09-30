shader_type sky;

// Per-system nebula backdrop (next_level_plan P5): seamless 3D value-noise
// clouds sampled on the view direction, tinted by the system's star type,
// with dark dust lanes. The starfield stays a separate layer; this is only
// the faint wash behind it. `seed` makes every system's sky different.
uniform vec3 tint_a : source_color = vec3(0.55, 0.25, 0.15);
uniform vec3 tint_b : source_color = vec3(0.25, 0.1, 0.3);
uniform vec3 base : source_color = vec3(0.006, 0.009, 0.022);
uniform float seed = 0.0;
uniform float strength = 0.35;
uniform float coverage = 0.5;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419) + seed * 0.013);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR) * 2.2 + vec3(seed * 0.37, seed * 0.11, -seed * 0.23);
	float cloud = fbm(d);
	float band = fbm(d * 2.4 + 5.0);
	float neb = smoothstep(1.0 - coverage, 1.0, cloud);
	float lanes = smoothstep(0.45, 0.75, fbm(d * 4.0 + 11.0));
	vec3 col = mix(tint_b, tint_a, band) * neb * (1.0 - 0.7 * lanes);
	COLOR = base + col * strength;
}
