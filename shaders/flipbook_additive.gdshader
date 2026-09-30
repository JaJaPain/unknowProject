shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Plays one cell of a square flipbook sheet on a camera-facing quad. Black is
// transparent (additive), so fire glows and fades with no alpha channel.
uniform sampler2D sheet : source_color, filter_linear_mipmap;
uniform int columns = 4;
uniform int rows = 4;
uniform float frame = 0.0;
uniform float brightness = 1.4;

void vertex() {
	// Billboard: keep the quad facing the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	int f = clamp(int(frame), 0, columns * rows - 1);
	vec2 cell = vec2(float(f % columns), float(f / columns));
	vec2 uv = (cell + UV) / vec2(float(columns), float(rows));
	ALBEDO = texture(sheet, uv).rgb * brightness;
}
