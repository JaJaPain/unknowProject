shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float speed = 5.0;
uniform vec4 base_color : source_color = vec4(0.02, 0.08, 0.35, 1.0); // Deep space blue/purple
uniform vec4 neon_color : source_color = vec4(0.1, 0.8, 1.0, 1.0);    // Vibrant cyan/blue
uniform vec4 accent_color : source_color = vec4(0.8, 0.1, 0.6, 1.0);  // Hot pink/magenta
uniform float ring_frequency = 15.0;
uniform float ring_speed = 8.0;
uniform float noise_scale = 3.0;

// Pseudo-random noise functions
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	// UV.x wraps around (0 to 1) -> angle
	// UV.y is along length (0 to 1) -> distance
	vec2 uv = UV;
	
	// Scroll along the length (Y-axis) to simulate forward travel
	float time_offset = TIME * speed;
	vec2 scroll_uv1 = vec2(uv.x * noise_scale, uv.y * noise_scale - time_offset);
	vec2 scroll_uv2 = vec2(uv.x * noise_scale + 0.5, uv.y * noise_scale * 1.5 - time_offset * 1.3);
	
	// Swirling nebula clouds using FBM
	float n1 = fbm(scroll_uv1);
	float n2 = fbm(scroll_uv2);
	float plasma = mix(n1, n2, 0.5);
	
	// Concentric energy bands / rings rushing down the tunnel
	float ring_phase = uv.y * ring_frequency - TIME * ring_speed;
	float ring = sin(ring_phase);
	ring = pow(max(0.0, ring), 4.0); // Make them sharp and bright
	
	// Add some noise to the rings to make them look like plasma loops rather than perfect circles
	float ring_distort = noise(vec2(uv.x * 5.0, uv.y * 2.0 - TIME * 2.0));
	ring *= 0.3 + 0.7 * ring_distort;
	
	// Mix color gradients
	// Base space background
	vec3 final_color = base_color.rgb;
	
	// Swirling nebula glows
	final_color = mix(final_color, neon_color.rgb, plasma * 0.7);
	final_color = mix(final_color, accent_color.rgb, n2 * n2 * 0.5);
	
	// Add bright energy rings
	final_color += neon_color.rgb * ring * 2.0;
	
	// Vanishing point fading at both ends of the tunnel (so it doesn't clip harshly)
	// Y is from 0.0 (top) to 1.0 (bottom)
	// We want it to fade out near the start (Y=0.0) and end (Y=1.0) of the cylinder
	float edge_fade = smoothstep(0.0, 0.15, uv.y) * smoothstep(1.0, 0.85, uv.y);
	
	ALBEDO = final_color;
	EMISSION = final_color * (1.2 + ring * 2.5); // Emissive bloom glow!
	ALPHA = edge_fade * (0.85 + plasma * 0.15);
}
