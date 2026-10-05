shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec3 sun_direction = vec3(-.55,.3,.78);
uniform vec3 sun_color : source_color = vec3(1.0);
uniform float sun_intensity = 1.4;
uniform vec3 haze_color : source_color = vec3(.19,.48,.9);
uniform float density = .42;
varying vec3 radial;
void vertex() {radial=MODEL_NORMAL_MATRIX*NORMAL;}
void fragment() {
 float facing=abs(dot(normalize(NORMAL),VIEW));
 float limb=pow(1.0-facing,4.0)*smoothstep(0.0,.16,facing);
 float lit=smoothstep(-.12,.4,dot(normalize(radial),normalize(sun_direction)));
 ALBEDO=haze_color*sun_color*sun_intensity;
 ALPHA=limb*lit*density;
}
