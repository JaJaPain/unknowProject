shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec3 haze_color : source_color = vec3(.55,.72,1.0);
uniform vec3 sun_color : source_color = vec3(1.0);
uniform vec3 sun_direction = vec3(-.6,.35,.7);
uniform float density = .35;
varying vec3 radial;
void vertex() { radial=normalize((MODEL_NORMAL_MATRIX*NORMAL)); }
void fragment() {
 vec3 n=normalize(radial);
 float facing=abs(dot(normalize(NORMAL),VIEW));
 float limb=pow(1.0-facing,4.0)*smoothstep(0.0,.13,facing);
 float lit=smoothstep(-.08,.38,dot(n,normalize(sun_direction)));
 ALBEDO=haze_color*sun_color;
 ALPHA=limb*lit*density;
}
