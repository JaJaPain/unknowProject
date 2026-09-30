shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

// The inside of a failing jump gate (intro cinematic): a swirling energy bore
// that should be clean cyan but is torn open. Dark tears drift across it with
// hot rims, filaments race toward the camera, and `surge` (0..1) floods the
// whole wall when the gate lurches. UV.y runs along the bore, UV.x around it.

uniform vec4 energy_color : source_color = vec4(0.10, 0.75, 1.0, 1.0);
uniform vec4 corrupt_color : source_color = vec4(0.55, 0.10, 0.95, 1.0);
uniform vec4 tear_color : source_color = vec4(1.0, 0.35, 0.08, 1.0);
uniform float flow_speed = 1.6;
uniform float swirl = 0.35;
uniform float surge : hint_range(0.0, 1.0) = 0.0;
uniform float brightness = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Tiling around the bore: x wraps every `period` cells.
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.0, 3.0);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float t = TIME;
	// Around-the-bore coordinate as an angle so the seam never shows.
	float ang = UV.x * 6.2831853;
	vec2 ring = vec2(cos(ang), sin(ang));
	float along = UV.y * 18.0;
	// Filaments: long streaks racing down the bore, twisting as they go.
	float twist = along * swirl + t * 0.4;
	vec2 fp = vec2(ring.x * cos(twist) - ring.y * sin(twist), along * 0.25 + t * flow_speed * 1.8);
	float fil = fbm(vec2(ang * 5.0 + twist * 3.0, along * 1.2 + t * flow_speed * 6.0));
	float streak = pow(smoothstep(0.55, 0.95, fil), 3.0);
	// Body of the energy: slow billowing clouds.
	float cloud = fbm(vec2(ring * 2.2 + fp.xy * 0.5) + vec2(along * 0.35 + t * flow_speed, t * 0.2));
	// Tears: large dark ragged holes with a burning edge, drifting slowly.
	float tear_field = fbm(vec2(ang * 1.6 + t * 0.07, along * 0.22 + t * flow_speed * 0.5) * 1.3);
	float hole = smoothstep(0.62, 0.66, tear_field);
	// A thin burning edge: white-hot at the lip, orange just outside it.
	float rim = smoothstep(0.59, 0.62, tear_field) * (1.0 - hole);
	float lip = smoothstep(0.615, 0.625, tear_field) * (1.0 - hole);
	// Colour: clean energy corrupted toward violet in patches.
	float corrupt = smoothstep(0.35, 0.75, fbm(vec2(ang * 0.8, along * 0.1 - t * 0.3)));
	vec3 base = mix(energy_color.rgb, corrupt_color.rgb, corrupt);
	vec3 col = base * (cloud * 0.8 + streak * 2.6);
	col += tear_color.rgb * rim * (0.9 + surge * 1.5);
	col += vec3(1.0, 0.85, 0.7) * lip * (1.2 + surge);
	col *= 1.0 - hole * 0.97;
	// Surge: the wall floods bright and hot for an instant.
	col += base * surge * 0.9 * cloud;
	// Fade the far end into the vanishing point and the near end out of view.
	float far_fade = smoothstep(0.0, 0.22, UV.y) * smoothstep(1.0, 0.8, UV.y);
	ALBEDO = col * brightness * far_fade;
}
