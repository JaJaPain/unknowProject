shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Procedural gas giant (playtest 2026-10-02: every gas giant looked like
// Jupiter). Latitude bands warped by noise, fine streaks, an optional storm,
// a soft atmosphere rim, and a slow drift. Works on the object-space surface
// direction, so there is no UV seam and no pinching at the poles. The look
// (palette, bands, turbulence, storm) comes from GasGiantLook.gd per planet.

uniform vec3 color_a : source_color = vec3(0.93, 0.86, 0.72);
uniform vec3 color_b : source_color = vec3(0.78, 0.62, 0.44);
uniform vec3 color_c : source_color = vec3(0.62, 0.38, 0.24);
uniform vec3 color_d : source_color = vec3(0.95, 0.92, 0.85);
uniform float band_count = 9.0;
uniform float turbulence = 0.6;
uniform float band_sharpness = 1.0;
uniform float flow_speed = 0.004;
uniform vec3 seed_offset = vec3(0.0);
uniform vec3 storm_dir = vec3(0.0, 0.2, 1.0);
uniform float storm_size = 0.0; // 0 = no storm
uniform vec3 storm_color : source_color = vec3(0.8, 0.45, 0.3);
uniform vec3 rim_color : source_color = vec3(0.6, 0.7, 0.9);
uniform float rim_strength = 0.35;

varying vec3 surface_dir;

void vertex() {
	surface_dir = normalize(VERTEX);
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * value_noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amp *= 0.5;
	}
	return sum;
}

vec3 palette(float v) {
	if (v < 0.33) {
		return mix(color_a, color_b, v / 0.33);
	} else if (v < 0.66) {
		return mix(color_b, color_c, (v - 0.33) / 0.33);
	}
	return mix(color_c, color_d, (v - 0.66) / 0.34);
}

void fragment() {
	vec3 p = surface_dir;
	float t = TIME * flow_speed;
	// Large swirls that bend the bands.
	vec3 q = p * 2.2 + seed_offset;
	float warp_a = fbm(q + vec3(t, 0.0, 0.0));
	float warp_b = fbm(q * 1.7 + vec3(5.2, 1.3, -t));
	float lat = p.y
		+ turbulence * 0.12 * (warp_a - 0.5)
		+ turbulence * 0.03 * (fbm(p * 6.0 + seed_offset + vec3(warp_b * 3.0)) - 0.5);
	// Bands along latitude: a main wave plus a slower one, so band widths vary
	// the way real ones do; soft fine streaks stretched along them.
	float bands = 0.7 * sin(lat * band_count * 3.14159) + 0.3 * sin(lat * band_count * 0.37 * 3.14159 + 1.3);
	float streaks = fbm(vec3(p.x * 2.0, lat * 30.0, p.z * 2.0) + seed_offset);
	float v = clamp(0.5 + 0.5 * bands * band_sharpness + (streaks - 0.5) * 0.28, 0.0, 1.0);
	vec3 col = palette(v);
	// A storm: an oval vortex with rings, sitting on one band.
	if (storm_size > 0.0) {
		vec3 c = normalize(storm_dir);
		vec3 d3 = p - c;
		float d = length(vec2(length(d3.xz) * 0.7, d3.y * 1.4));
		float inside = smoothstep(storm_size, storm_size * 0.35, d);
		float rings = 0.65 + 0.35 * sin(d / storm_size * 14.0 + warp_a * 4.0);
		col = mix(col, storm_color * rings, inside * 0.85);
	}
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	// A soft atmosphere at the limb.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color * fresnel * rim_strength;
}
