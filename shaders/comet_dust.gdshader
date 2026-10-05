shader_type spatial;
// Distant comet fine dust sprites (test_comet/refined; wired 2026-10-05).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
void fragment() {
 vec2 p=UV*2.0-1.0;
 float r=dot(p,p);
 float soft=exp(-r*3.5)*(1.0-smoothstep(.5,1.0,r));
 ALBEDO=COLOR.rgb*COLOR.a*soft;
 ALPHA=1.0;
}
