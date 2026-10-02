shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Procedural gas giant (playtest 2026-10-02: every gas giant looked like
// Jupiter). Latitude bands warped by noise, fine streaks, churning storms,
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
// Up to three storms (Abe, 2026-10-02: "think Jupiter's storm"): rough,
// roughly circular vortices of swirling noise that keep turning. Size 0 = off.
uniform vec3 storm_dir_1 = vec3(0.0, 0.2, 1.0);
uniform vec3 storm_dir_2 = vec3(1.0, -0.25, 0.0);
uniform vec3 storm_dir_3 = vec3(-0.7, 0.1, -0.7);
uniform vec3 storm_sizes = vec3(0.0); // one size per storm
uniform vec3 storm_spins = vec3(1.0, -1.0, 1.0); // turn direction and speed
uniform vec3 storm_color : source_color = vec3(0.8, 0.45, 0.3);
uniform float storm_speed = 0.25;
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

// One storm: a vortex of swirling noise around centre_dir on the surface,
// with a rough, wobbling edge. The swirl turns with time, fastest near the
// eye, so the inside churns rather than sitting still.
vec3 storm(vec3 p, vec3 centre_dir, float size, float spin, float id, float time, vec3 col) {
	if (size <= 0.0) {
		return col;
	}
	vec3 c = normalize(centre_dir);
	vec3 offset = p - c * dot(p, c);
	vec3 axis_u = normalize(cross(c, abs(c.y) > 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
	vec3 axis_v = cross(c, axis_u);
	// Squashed east-west a little, like real storms riding a band.
	vec2 local = vec2(dot(offset, axis_u) * 0.75, dot(offset, axis_v));
	if (dot(p, c) < 0.0) {
		return col;
	}
	float r = length(local);
	float angle = atan(local.y, local.x);
	float t = time * storm_speed;
	// A rough edge that breathes slowly.
	float edge = size * (0.75 + 0.5 * fbm(vec3(cos(angle) * 1.6, sin(angle) * 1.6, t * 0.4 + id * 7.0)));
	float inside = smoothstep(edge, edge * 0.55, r);
	if (inside <= 0.0) {
		return col;
	}
	// The swirl: turn the noise faster towards the eye.
	float twist = spin * t * (1.6 - clamp(r / size, 0.0, 1.0)) + r / size * 3.0 * spin;
	float a = angle + twist;
	vec2 swirled = vec2(cos(a), sin(a)) * r / size;
	float churn = fbm(vec3(swirled * 3.5, id * 11.0 + t * 0.3) + seed_offset);
	float rings = 0.5 + 0.5 * sin(r / size * 13.0 - spin * t * 2.0 + churn * 3.0);
	vec3 storm_col = mix(storm_color * 0.7, storm_color * 1.25, churn) * (0.8 + 0.25 * rings);
	// The storm's own wake: the band colours dragged into it near the rim.
	vec3 dragged = mix(col, storm_col, smoothstep(0.0, 0.7, churn + (1.0 - r / edge) * 0.6));
	return mix(col, dragged, inside);
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
	col = storm(p, storm_dir_1, storm_sizes.x, storm_spins.x, 1.0, TIME, col);
	col = storm(p, storm_dir_2, storm_sizes.y, storm_spins.y, 2.0, TIME, col);
	col = storm(p, storm_dir_3, storm_sizes.z, storm_spins.z, 3.0, TIME, col);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	// A soft atmosphere at the limb.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color * fresnel * rim_strength;
}
