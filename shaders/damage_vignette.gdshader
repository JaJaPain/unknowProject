shader_type canvas_item;

// Screen-edge vignette for hits (red on the hull, blue on shields) and a slow
// pulse while the hull is low. `intensity` 0..1 is driven by DamageVignette.gd.
uniform vec4 tint : source_color = vec4(0.9, 0.08, 0.05, 1.0);
uniform float intensity = 0.0;

void fragment() {
	vec2 centred = UV - vec2(0.5);
	centred.x *= 1.6;
	float edge = smoothstep(0.62, 1.15, length(centred) * 1.25);
	COLOR = vec4(tint.rgb, edge * edge * intensity * 0.7);
}
