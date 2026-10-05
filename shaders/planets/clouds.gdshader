shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, fog_disabled, shadows_disabled;
#include "common.gdshaderinc"
#include "weather.gdshaderinc"
void vertex() {sphere_position=VERTEX;radial_world=MODEL_NORMAL_MATRIX*NORMAL;}
void fragment() {
 vec3 p=normalize(sphere_position);vec3 n=normalize(radial_world);
 float density=cloud_field(p);
 float micro=fbm(cloud_coords(p)*130.0+seed_offset);
 float detail_fade=1.0-smoothstep(.003,.012,length(fwidth(p)));
 vec3 relief_n=relief_normal(n,density*.0007+micro*.00012,detail_fade);
 float mu=dot(relief_n,normalize(sun_direction));
 float thickness=mix(.55,.90,density)+micro*.10;
 float horizon=smoothstep(-.015,.10,dot(n,normalize(sun_direction)));
 float lit=pow(max(mu,0.0),.8)*horizon;
 float forward=pow(1.0-abs(dot(normalize(NORMAL),VIEW)),4.0)*smoothstep(-.15,.3,mu)*.13;
 ALBEDO=vec3(.65,.68,.73)*sun_color*sun_intensity*(thickness*lit+.001)+vec3(.3,.5,.8)*forward;
 ALPHA=density*.96;
}
