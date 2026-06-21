shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float radial_blur_strength : hint_range(0.0, 0.15) = 0.0;
uniform float shockwave_amplitude : hint_range(0.0, 0.1) = 0.0;
uniform float shockwave_progress : hint_range(0.0, 1.5) = 0.0;
uniform float shockwave_width : hint_range(0.05, 0.5) = 0.18;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = vec2(0.5);
	vec2 diff = uv - center;
	float dist = length(diff);

	if (shockwave_progress > 0.0 && dist > 0.0) {
		float wave = 1.0 - smoothstep(shockwave_progress - shockwave_width, shockwave_progress, dist)
			* smoothstep(shockwave_progress + shockwave_width, shockwave_progress, dist);
		float offset = sin(dist * 60.0 - shockwave_progress * 15.0) * shockwave_amplitude * wave;
		uv += normalize(diff) * offset;
	}

	vec4 color = vec4(0.0);
	int samples = 8;
	for (int i = 0; i < samples; i++) {
		color += texture(screen_texture, uv - diff * radial_blur_strength * float(i) / float(samples));
	}
	color /= float(samples);

	COLOR = color;
}
