shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float radial_blur_strength : hint_range(0.0, 0.15) = 0.0;
uniform float chromatic_strength : hint_range(0.0, 0.02) = 0.0;
uniform float shockwave_amplitude : hint_range(0.0, 0.1) = 0.0;
uniform float shockwave_progress : hint_range(0.0, 1.5) = 0.0;
uniform float shockwave_width : hint_range(0.05, 0.5) = 0.18;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = vec2(0.5);
	vec2 diff = uv - center;
	float dist = length(diff);
	vec2 dir = dist > 0.0 ? normalize(diff) : vec2(0.0);

	// Shockwave ripple — ring mask centered on shockwave_progress radius
	if (shockwave_progress > 0.0) {
		float ring = smoothstep(shockwave_progress - shockwave_width, shockwave_progress, dist)
			* (1.0 - smoothstep(shockwave_progress, shockwave_progress + shockwave_width, dist));
		float wave_offset = sin(dist * 50.0 - shockwave_progress * 12.0) * shockwave_amplitude * ring;
		uv += dir * wave_offset;
	}

	// Radial blur (warp acceleration streaks) with chromatic aberration
	if (radial_blur_strength > 0.001 || chromatic_strength > 0.0001) {
		vec4 color_r = vec4(0.0);
		vec4 color_g = vec4(0.0);
		vec4 color_b = vec4(0.0);
		int samples = 10;
		float ca = chromatic_strength;
		for (int i = 0; i < samples; i++) {
			float t = float(i) / float(samples);
			vec2 offset = diff * radial_blur_strength * t;
			color_r += texture(screen_texture, uv - offset - dir * ca);
			color_g += texture(screen_texture, uv - offset);
			color_b += texture(screen_texture, uv - offset + dir * ca);
		}
		float inv = 1.0 / float(samples);
		COLOR = vec4(color_r.r * inv, color_g.g * inv, color_b.b * inv, color_g.a * inv);
	} else {
		COLOR = texture(screen_texture, uv);
	}
}
